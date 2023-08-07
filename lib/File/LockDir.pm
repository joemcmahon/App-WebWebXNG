use strict;
use warnings;

package File::LockDir;

=head1 NAME

File::LockDir - file-level locking

=head1 SYNOPSIS

    # at startup
    use File::LockDir;
    File::LockDir::init(logger => \&logging_function,
                        fatal  => \&fatal_function);
    nflock(

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

use Exporter;
use vars qw(@ISA @EXPORT);
@ISA      = qw(Exporter);
@EXPORT   = qw(nflock nunflock nlock_state);

# Awkward global configuration. This should be moved to a new().
use vars qw($Debug $Check $Tries);

# May be 1 to add debugging or 0 to skip it.
$Debug  ||= 1;

# Number of seconds to sleep between lock attempts.
$Check  ||= 5;

# Number of tries before we give up on getting a lock.
$Tries ||= 10;



use Cwd;
use Fcntl;
use Sys::Hostname;
use File::Basename;
use Carp;

# This should be stored in an object, not in the module's namespace.
my %Locked_Files = ();

sub init {
    %Locked_Files = ();
    my (%params) = @_;

    # Because there's no object associated with this class, we have nowhere
    # to store the callbacks. So we cheat and use the symbol table to hold
    # them by assigning them to a glob in our symbol table.

    # If a log function was supplied, import it. Otherwise, print
    # log/debug messages to STDERR.
    *File::LockDir::note  = $params{Logger} || sub{ print STDERR @_ };

    # If a fatal function was supplied, import it. Else, use croak instead.
    *File::LockDir::fatal = $params{Fatal}  || sub{ croak @_ };
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
that the requestor owns the lock if the file is already locked.

Locking is done by creating a "lockdir" and writing a status file into it.
The lockdir was used because creating it is an atomic transaction on NFS.

Returns 1 if the file is locked.

Dies if the file cannot be locked.

=cut

# usage: nflock(FILE; NAPTILL; LOCKER; LOCKHOST)
sub nflock($;$;$;$) {
    my $pathname = shift;
    my $naptime  = shift || 0;
    my $locker   = shift || "anonymous";
    my $lockhost = shift || hostname();
    my $lockname = name2lock($pathname);
    my $whosegot = "$lockname/owner";
    my $start    = time();
    my $missed   = 0;
    local *OWNER;

    # if locking what I've already locked, return
    if ($Locked_Files{$pathname}) {
        note("$pathname already locked");
        return 1;
    }

    if (!-w dirname($pathname)) {
        fatal("can't write to directory of $pathname");
    }

# XXX: the number of retries should be settable too.
#      #nomoremagicnumbers
    my $lockee;

    # Keep trying to get the lock until we give up.
    while (1) {
        last if mkdir($lockname, 0777);
        # If we've run out of tries, die. (Caller is expecting this.)
        fatal("can't get $lockname: $!") if $missed++ > $Tries
                        && !-d $lockname;
      # If debugging, show us who has the lock now.
    DEBUG:
        if ($Debug) {
            # If we can't open the "who owns this" file, don't try the
            # rest of this block.
            open(OWNER, "<", $whosegot) || last DEBUG;
            $lockee = <OWNER>;
	          close OWNER;
            chomp($lockee);
            note(sprintf("%s $0\[$$]: lock on %s held by %s\n",
                scalar(localtime()), $pathname, $lockee));
        }

        # Wait a bit to see if we can get it. If we've used up our
        # time, fetch the current lock info and return it.
        sleep $Check;
        if ($naptime && time > $start+$naptime) {
            open(OWNER, "<", $whosegot) || last; # exit "if"!
            $lockee = <OWNER>;
	          close OWNER;
            chomp($lockee);
            return (undef, $lockee);
        }
    }

    # We were able to create the lock directory, so we have possession
    # of the lock. Write the locker info out and return success.
    sysopen(OWNER, ">", $whosegot, O_WRONLY|O_CREAT|O_EXCL)
                            or fatal("can't create $whosegot: $!");
    my $locktime = scalar(localtime());
    my $line = sprintf("%s from %s since %s\n", $locker, $lockhost, $locktime);
    print OWNER $line;
    close(OWNER)
      or fatal("close failed for $whosegot: $!");
    $Locked_Files{$pathname} = $line;
    return (1, undef);
}

=head2 nfunlock($pathnane)

Unlocks the supplied path by removing the lock data file and then
removing the lock directory (again, an atomic operation on NFS).

=over

=item $pathname - full pathname of the file to be unlocked.

=back

=cut

sub nunflock($) {
    my $pathname = shift;
    my $lockname = name2lock($pathname);
    my $whosegot = "$lockname/owner";
    unlink($whosegot);
    note("releasing lock on $lockname") if $Debug;
    delete $Locked_Files{$pathname};
    return rmdir($lockname);
}

=head2 nlock_state($pathname)

Checks lock state for the given path.

=cut

# check the state of the lock, bu don't try to get it
sub nlock_state($) {
    my $pathname = shift;
    my $lockname = name2lock($pathname);
    my $whosegot = "$lockname/owner";
    return (undef, $Locked_Files{$pathname}) if $Locked_Files{$pathname};

    return (1, undef) if ! -d $lockname;

    open(OWNER, "<", $whosegot) || return (1, undef);
    my $lockee = <OWNER>;
    close(OWNER);
    chomp($lockee);
    return (undef, $lockee);
}

# helper function
sub name2lock($) {
    my $pathname = shift;
    my $dir  = dirname($pathname);
    my $file = basename($pathname);
    $dir = getcwd() if $dir eq '.';
    my $lockname = "$dir/$file.LOCKDIR";
    return $lockname;
}

1;

