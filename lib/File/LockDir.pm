use strict;
use warnings;

package File::LockDir;

=head1 NAME

File::LockDir - file-level locking with state caching

=head1 SYNOPSIS

    # at startup
    use File::LockDir;

    my $locker = File::LockDir->new(
      logger => \&logger_function,
      fatal  => \&fatal_function,

    );
    File::LockDir::init(logger => \&logging_function,
                        fatal  => \&fatal_function);

=head1 DESCRIPTION

C<File::LockDir> maintains a lockfile for each file referenced in the wiki's
page storage. The page storage directory is assumed to be writeable by the
wiki script.

This module provides very basic filename-level locks. It was originally designed
to be used on a single machine being time-shared between multiple developers, but
should still work in a standard web environment. It may not be fast enough in an
enviroment with many people editing the wiki at once.

The original version was written for Perl 4 and expected the wiki files to reside
on NFS (hence the need for the `hostname` parameter). It was not updated to more contemporary
standards; this module would be better if it instantiated an object and stored the
C<logger> and C<fatal> functions there, for instance, and might better handle things
by storing the locking info in a DB table instead. As it is, there can be only
one C<File::LockDir> configuration per wiki instance.

Locking is done by creating a lock directory instead of opening, writing,
and closing a file because the wiki was on a shared NFS volume; creating a directory
was (is?) atomic on NFS.

The object maintains a lock status cache; originally this was because page
archive lived on an NFS volume, and access to the files in the archive
was much slower than regular disk access. It still serves to speed up
some operations, so it's been kept in this new version.

=cut

use constant DEFAULT_SLEEP_TIME => 5;
use constant DEFAULT_TRIES      => 10;

use Cwd;
use Fcntl;
use Sys::Hostname;
use File::Basename;
use Carp;

# This should be stored in an object, not in the module's namespace.
my %Locked_Files = ();

=head1 CLASS METHODS

=head2 new(%params)

Creates the object. Parameters:

=over

=item note: note() callback. Defaults to print to STDERR.

=item fatal: fatal() callback. Defaults to croak().

=item debug: 1 if debug is to be enabled. Defaults to 0 (no debugging).

=item sleep: number of seconds to sleep between tries. Defaults to DEFAULT_SLEEP_TIME.

=item tries: Number of tries before we give up. Defaults to DEFAULT_TRIES.

=back

=cut

sub new {
    my ($class, %params) = @_;
    my $self = {};
    bless $self, $class;

    $self->locked_files({});

    # If a valid log function was supplied, use it. Otherwise, print
    # log/debug messages to STDERR.
    if (defined $params{logger}) {
      croak "logger is not a code ref" unless ref $params{logger} eq "CODE";
    }
    $self->note($params{logger} ? $params{logger} : sub { carp @_ });

    # If a valid fatal function was supplied, use it. Else, use croak instead.
    if (defined $params{fatal}) {
      croak "fatal is not a code ref" unless ref $params{fatal} eq "CODE";
    }
    $self->fatal($params{fatal} ? $params{fatal} : sub { croak @_ });

    $self->debug($params{debug} ? 1 : 0);
    $self->sleep(+$params{sleep} || DEFAULT_SLEEP_TIME);
    $self->tries(+$params{tries} || DEFAULT_TRIES);

    return $self;
}

=head2 note(@args)

Setter/getter for the note callback.

=cut

sub note {
  my($self, $callback) = @_;
  $self->{_note} = $callback if defined $callback;
  $self->{_note};
}

=head2 fatal

Setter/getter for the fatal callback.

=cut

sub fatal {
  my($self, $callback) = @_;
  $self->{_fatal} = $callback if defined $callback;
  $self->{_fatal};
}

=head1 INSTANCE METHODS

=head2 locked_files()

Can be called with a hashref to initialize the locked files, a key to fetch an entry,
or a key and value to set an entry.

Returns a value only when fetching an entry.

=cut

sub locked_files {
  my ( $self, @args ) = @_;

  return $self->{_locked_files} unless @args;

  if ( @args == 1 and ref $args[0] eq 'HASH' ) {
    $self->{_locked_files} = $args[0];
    return $args[0];
  } else {
    my ( $key, $value ) = @args;

    if ( defined $key ) {
      if ( @args == 1 ) {
        return $self->{_locked_files}{ $args[0] };
      } else {
        $self->{_locked_files}{ $args[0] } = $args[1];
        return $args[1];
      }
    }
  }
}

=head2 sleep

Setter/getter for the sleep interval.

=cut

sub sleep {
  my($self, $interval) = @_;
  $self->{_sleep_seconds} = $interval if defined $interval;
  return $self->{_sleep_seconds};
}

=head3 debug

Setter/getter for the debug flag.

=cut

sub debug {
  my($self, $setting) = @_;
  $self->{_debug} = $setting if defined $setting;
  return $self->{_debug};
}

=head3 tries

Setter/getter for the try count.

=cut

sub tries {
  my ($self, $count) = @_;
  $self->{_tries} = $count if defined $count;
  return $self->{_tries};
}

=head2 nflock($path, $delay, $locking_user, $hostname)

nflock actually locks a file if possible by creating a lockfile
in the same directory and storing the locking user and host into it.

=over

=item $path

The filepath of the file being locked. This file must reside in a
directory writeable by the caller.

=item $delay

We delay this long before retrying the lock. If set to zero, we
keep retrying forever. (XXX: this is probably the wrong choice now,
but was useful when all of the users of the wiki knew each other's
phone numbers and could call to ask the other person to release the
lock.)


=item $locking_user

The wiki username of the user locking the file.

=item $hostname

The hostname of the host locking the file.

=back

This function I<only> locks the file if possible. It does not verify
that the requestor owns the lock if the file is already locked; the
requestor I<must> check the returned owner value.

Locking is done by creating a "lockdir" and writing a status file into it.
The lockdir was used because creating it is an atomic transaction on NFS.

Returns 1 if the file is locked.

Dies if the file cannot be locked.

=cut

# usage: nflock(FILE; NAPTILL; LOCKER; LOCKHOST)
sub nflock {
  my ( $self, $pathname, $naptime, $locker, $lockhost ) = @_;
  defined $pathname or croak "no pathname supplied";
  defined $naptime  or $naptime  = 0;
  defined $locker   or $locker   = "anonymous";
  defined $lockhost or $lockhost = hostname();

  my $lockname = _name2lock($pathname);
  my $whos_got = File::Spec->catfile($lockname,"owner");

  # if in the locked file cache, return the contents
  if ( my $owner = $self->locked_files($pathname) ) {
    $self->note->("$pathname already locked");
    return (1, $owner);
  }

  # Stay in this block until we either successfully create the
  # lock directory, we run out of tries, or we time out.
  my $tries_left = $self->tries;
  $self->note->("lock $pathname: attempt to obtain lock") if $self->debug;
SPIN:
  while (1) {
    $self->note->("lock $pathname: try $tries_left") if $self->debug;
    $tries_left--;

    # If the mkdir succeeds, we have control and can lock.
    # (If the directory is already there, the mkdir fails;
    # when we create the directory, no one else can do so,
    # so the process that successfully creates the directory
    # itself wins the race and can atomically write the lock.)
    #
    # If there's a permissions problem -- there shouldn't be,
    # but it's possible -- then the mkdir will fail until we
    # reach the timeout and then we'll return a lock fail.
    last if mkdir( $lockname, 0700 );
    $self->note->("lock $pathname: did not get lock") if $self->debug;

    # If we've run out of tries, and we still don't have the lock,
    # die. (Caller is expecting this.)
    $self->fatal->("can't obtain lock $lockname: $!")
      if $tries_left == 0 && !-d $lockname;

    # Wwe have tries left, so wait a bit, try to read the owner
    # info, and log it if we got it and we're debugging. If
    # we've used up our time, return failure and the current
    # owner info.
    CORE::sleep $self->sleep;

    my $locking_user = _read_lock_info($whos_got) // "(unknown)";
    $self->note->("lock #pathname: Lock held by '$locking_user'") if $self->debug;

    if ( $tries_left == 0) {
      $self->note->("lock $pathname: failed - held by $locking_user") if $self->debug;
      return ( 0, $locking_user );
    }
  }

  # We dropped out of the SPIN loop, so we were able to create
  # the lock directory, and we have possession of the lock.
  # Write the owner info out and return success.
  sysopen( my $owner, $whos_got, O_WRONLY | O_CREAT | O_EXCL )
    or $self->fatal->("can't create $whos_got $!");

  my $locktime = scalar( localtime() );
  chomp $locktime;

  my $line = sprintf( "%s from %s since %s\n", $locker, $lockhost, $locktime );
  print $owner $line;

  close($owner)
    or $self->fatal->("close failed for $whos_got $!");

  $self->locked_files( $pathname, $line );
  $self->note->("lock $pathname: successful") if $self->debug;
  return ( 1, $line );
}

=head2 nfunlock($pathnane)

Unlocks the supplied path by removing the lock data file and then
removing the lock directory (again, an atomic operation on NFS).

=over

=item $pathname - full pathname of the file to be unlocked.

=back

=cut

sub nfunlock {
  my($self, $pathname) = @_;
  croak "No pathname passed to nfunlock" unless defined $pathname;
  my $lockname = _name2lock($pathname);
  my $whos_got = "$lockname/owner";
  unlink($whos_got);
  $self->note->("releasing lock on $lockname") if $self->debug;
  $self->_delete_lock_for($pathname);
  return rmdir($lockname);
}

sub _delete_lock_for {
  my ( $self, $pathname ) = @_;
  delete $self->{_locked_files}{$pathname};
}

=head2 nlock_state($pathname)

Checks lock state for the given path.

=cut

# check the state of the lock, bu don't try to get it
sub nlock_state {
  my($self, $pathname) = @_;
  croak "No pathname supplied to nlock_state" unless defined $pathname;

  my $is_locked = $self->locked_files($pathname);
  # If in the lock cache, we don't have to look at the disk.
  return ( 1, $is_locked ) if $is_locked;

  # Wasn't in the cache. If the lock dir doesn't exist, we're unlocked.
  my $lockname  = _name2lock($pathname);
  return ( undef, undef ) if !-d $lockname;

  # Lock dir exists, read the owner info.
  my $whos_got = _owner_file($lockname);
  my $locking_user = _read_lock_info($whos_got);
  return ( 1, $locking_user );
}

# helper functions

sub _owner_file {
  my($lockname) = shift;
  return File::Spec->catfile($lockname, "owner");
}

sub _name2lock {
  my $pathname = shift;
  my $dir      = dirname($pathname);
  my $file     = basename($pathname);
  $dir = getcwd() if $dir eq '.';
  my $lockname = "$dir/$file.LOCKDIR";
  return $lockname;
}

sub _read_lock_info {
  my ($whos_got) = @_;
  open( my $owner, "<", $whos_got ) || return;
  my $locking_user = <$owner>;
  close $owner;
  chomp($locking_user);
  return $locking_user;
}
1;

