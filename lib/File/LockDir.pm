use strict;
use warnings;

package File::LockDir;

=head1 NAME

File::LockDir - file-level locking

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
    $self->{_notesub} = $params{logger} ? $params{logger} : sub { warn @_, "\n" };

    # If a valid fatal function was supplied, use it. Else, use croak instead.
    if (defined $params{fatal}) {
      croak "fatal is not a code ref" unless ref $params{fatal} eq "CODE";
    }
    $self->{_fatalsub} = $params{fatal} ? $params{fatal} : sub { croak @_ };

    $self->{_debug} = $params{debug} ? 1 : 0;
    $self->{_sleep_seconds} = +$params{sleep} || DEFAULT_SLEEP_TIME;

    return $self;
}

=head2 note(@args)

Sends its arguments to the note callback.

=cut

sub note {
  my($self, @args) = @_;
  my $callback = $self->{_notesub};
  $callback->(@args);
}

=head2 fatal

Sends its argumetns to the fatal callback.

=cut

sub fatal {
  my($self, @args) = @_;
  my $callback = $self->{_fatalsub};
  $callback->(@args);
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

Getter for the sleep interval.

=cut

sub sleep {
  my($self) = @_;
  return $self->{_sleep_seconds};
}

=head3 debug

Getter for the debug flag.

=cut

sub debug {
  my($self) = @_;
  return $self->{_debug};
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
  my $start    = time();
  my $missed   = 0;

  # if in the locked file cache, return the contents
  if ( my $owner = $self->locked_files($pathname) ) {
    $self->note("$pathname already locked");
    return (1, $owner);
  }

  if ( !-w $lockname ) {
    $self->fatal("can't write to lockfile $lockname");
  }

  # Keep trying to get the lock until we give up.
  while (1) {
    last if mkdir( $lockname, 0777 );

    # If we've run out of tries, die. (Caller is expecting this.)
    $self->fatal("can't get $lockname: $!")
      if $missed++ > $self->{_tries}
      && !-d $lockname;

    # If debugging, show us who has the lock now.
  DEBUG:
    if ( $self->debug ) {

      # If we can't open the "who owns this" file, don't try the
      # rest of this block.
      my $lockee = _read_lock_info($whos_got);
      last DEBUG if not defined $lockee;
      $self->note(
        sprintf(
          "%s $0\[$$]: lock on %s held by %s\n",
          scalar( localtime() ),
          $pathname, $lockee
        )
      );
    }

    # Wait a bit to see if we can get it. If we've used up our
    # time, fetch the current lock info and return it.
    CORE::sleep $self->sleep;
    if ( $naptime && time > $start + $naptime ) {
      my $lockee = _read_lock_info($whos_got);
      return ( undef, $lockee );
    }
  }

  # We were able to create the lock directory, so we have possession
  # of the lock. Write the locker info out and return success.
  sysopen( my $owner, $whos_got, O_WRONLY | O_CREAT | O_EXCL )
    or $self->fatal("can't create $whos_got $!");
  my $locktime = scalar( localtime() );
  chomp $locktime;
  my $line = sprintf( "%s from %s since %s\n", $locker, $lockhost, $locktime );
  print $owner $line;
  close($owner)
    or $self->fatal("close failed for $whos_got $!");
  $self->locked_files( $pathname, $line );
  return ( 1, undef );
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
  $self->note("releasing lock on $lockname") if $self->debug;
  $self->delete_lock_for($pathname);
  delete $Locked_Files{$pathname};
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
  my $lockname  = _name2lock($pathname);
  my $whos_got  = "$lockname/owner";
  my $is_locked = $self->_locked_files($pathname);
  return ( undef, $Locked_Files{$pathname} ) if $is_locked;

  return ( 1, undef ) if !-d $lockname;

  my $lockee = _read_lock_info($whos_got);
  return ( undef, $lockee );
}

# helper functions
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
  open( my $owner, "<", $whos_got ) || last;    # exit "if"!
  my $lockee = <$owner>;
  close $owner;
  chomp($lockee);
  return $lockee;
}
1;

