package File::LockDir;
# module to provide very basic filename-level
# locks.  No fancy systems calls.  In theory,
# directory info is sync'd over NFS.  Not
# stress tested.

use strict;

use Exporter;
use vars qw(@ISA @EXPORT);
@ISA      = qw(Exporter);
@EXPORT   = qw(nflock nunflock nlock_state);


use vars qw($Debug $Check);
$Debug  ||= 1;  # may be predefined
$Check  ||= 5;  # may be predefined

use Cwd;
use Fcntl;
use Sys::Hostname;
use File::Basename;
#use File::stat;
use Carp;

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

# usage: nflock(FILE; NAPTILL; LOCKER)
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

    my $lockee;
    while (1) {
        last if mkdir($lockname, 0777);
        fatal("can't get $lockname: $!") if $missed++ > 10
                        && !-d $lockname;
        if ($Debug) {
            open(OWNER, "< $whosegot") || last; # exit "if"!
            $lockee = <OWNER>;
	    close OWNER;
            chomp($lockee);
            note(sprintf "%s $0\[$$]: lock on %s held by %s\n",
                scalar(localtime()), $pathname, $lockee);
        }
        sleep $Check;
        if ($naptime && time > $start+$naptime) {
            open(OWNER, "< $whosegot") || last; # exit "if"!
            $lockee = <OWNER>;
	    close OWNER;
            chomp($lockee);
            return (undef, $lockee);
        }
    }
    sysopen(OWNER, $whosegot, O_WRONLY|O_CREAT|O_EXCL)
                            or fatal("can't create $whosegot: $!");
    my $locktime = scalar(localtime());
    my $line = sprintf("%s from %s since %s\n", $locker, $lockhost, $locktime);
    print OWNER $line;
    close(OWNER)
      or fatal("close failed for $whosegot: $!");
    $Locked_Files{$pathname} = $line;
    return (1, undef);
}

# free the locked file
sub nunflock($) {
    my $pathname = shift;
    my $lockname = name2lock($pathname);
    my $whosegot = "$lockname/owner";
    unlink($whosegot);
    note("releasing lock on $lockname") if $Debug;
    delete $Locked_Files{$pathname};
    return rmdir($lockname);
}

# check the state of the lock, bu don't try to get it
sub nlock_state($) {
    my $pathname = shift;
    my $lockname = name2lock($pathname);
    my $whosegot = "$lockname/owner";
    return (undef, $Locked_Files{$pathname}) if $Locked_Files{$pathname};

    return (1, undef) if ! -d $lockname;

    open(OWNER, "< $whosegot") || return (1, undef);
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

