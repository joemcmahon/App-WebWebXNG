package PageArchive;

###############################################################################
# Provide database-like access (with versioning) via files in a 
# directory. This is admittedly a hack to work around the problem
# that some installations don't have a Perl-accessible DBM package
# that can handle entries bigger than 1K.
###############################################################################

use Carp;
use Storable;
use File::LockDir;
use Data::Dumper;

###############################################################################
# Class variables
###############################################################################

# $gensym - Used to generate unique filehandle names. Should be autoincremented
#           on each reference to guarantee that a new symbol is always 
#           generated.
my $gensym = "FH0000";	

###############################################################################
# Class methods
###############################################################################

###############################################################################
# new - create a new PageArchive object.
#       Verifies that the directory can be opened. 
#       Saves a filehandle usable with readdir() and the name of the directory
#       for building file names.
###############################################################################

sub new {
    my ($class, $dirname, %params) = @_;
    my $self = {};
    bless $self,$class;

    $self->logger($params{Logger} || sub { print STDERR @_ });
    $self->fatal($params{Fatal}   || sub { croak @_ });

    $self->setError();

    # Verify that dir name is OK; try to create it if we must;
    # return undef if we can't.
    unless (-d $dirname) {	# Not a dir or doesn't exist
        unless (-e $dirname) {  # Doesn't exist
            # Make the directory, including parent dirs.
            # Return undef if we fail along the way.
            my @path = split ('/',$dirname);
            my $accumulated_path = "";
            foreach (@path) {
                $accumulated_path .= "/$_";
                next if -e $accumulated_path and -d _;
                unless (mkdir $acumulated_path,0700) {
                    $self->fatal->("Can't create $accumulated_path: $!");
                }
            }
        }
        else { # Exists, but is not a directory
            $self->fatal->("$dirname exists, but is not a directory");
        }
    }
    else { # is a directory (and exists)
        $self->{DirName} = $dirname;
        $self->{Handle} = $gensym++;
        $self->{LockLimit} = 30;
    }

    # (re)initialize File::LockDir.
    File::LockDir::init(%params);

    # See if we can read the directory; return undef if not.
    unless(opendir($self->{Handle},$dirname)) {
        $self->fatal->("Cannot open $dirname: $!");
    }
    return $self;
}

###############################################################################
# Instance methods.
###############################################################################

###############################################################################
# defined ($name,$version) - determine whether or not an entry exists.
#
# Returns undef if no versions exist, or a list of versions if multiple
# versions exist.
###############################################################################

sub defined {
    my($self, $name, $version) = @_;
    $version = "" unless defined $version;

     # Search directory for filenames matching.
    $self->dh_reset;
    return grep(/^$name,$version/,readdir $self->{Handle});
    $dir->{Rewound} = 0;
}

###############################################################################
# lock($name) - lock the entry (all versions). 
#
# Returns undef if the entry can't be locked, true otherwise.
###############################################################################

sub lock {
    my ($self, $name, $who, $host) = @_;
    my ($which,$locked_by)  = 
        nflock("$self->{DirName}/$name", $self->lock_limit(), $who, $host); 
    return ($which, $locked_by);
}
    
##############################################################################
# unlock($name) - unlock the entry (all versions).
#
# Returns undef if the entry wasn't locked, true otherwise.
###############################################################################

sub unlock {
    my ($self, $name) = @_;
    nunflock("$self->{DirName}/$name");
}

###############################################################################
# is_unlocked($name) - see if an entry is locked
#
# Returns: (1, undef) if the entry is unlocked
#          (undef, "<locker> at <host> since <date and time>") if locked
###############################################################################

sub is_unlocked {
    my ($self,$name) = @_;
    return nlock_state("$self->{DirName}/$name");
}
###############################################################################

###############################################################################
# max_version($name) - determine the maximum version # of a given entry.
#
# Returns the version number of the newest version.
###############################################################################

sub max_version {
    my($self, $name) = @_;
    $self->dh_reset;

   # We use defined() to get a list of versions defined for this name, use
   # map() to strip off just the versions, sort these numerically in reverse,
   # and then pull off the first (highest) one and return it.
   my @indexes = (sort {$b <=> $a} 
                     (map /^.*,(.*)$/, 
                         $self->defined($name)));
   return shift @indexes;

}

###############################################################################
# get($name,$version) - fetch a specified version of the entry. 
#
# Finds the file, reads it, and uses Storable::inflate to restore it.
###############################################################################

sub get {
    my($self, $name, $version) = @_;
    $version = $self->max_version($name) unless $version;

    $self->logger->("Getting $name,$version");
    $self->setError();

    unless ($self->defined($name,$version)) {
        $self->setError("$self->{DirName}/$name,$version does not exist");
        return;
    }

    my $handle = $gensym++;

    # This shouldn't happen, unless someone's been fiddling with the database.
    unless(open($handle, $self->{DirName} . "/" . $name . "," . $version)) {
        $self->setError("Unreadable file $self->{DirName}/$name,$version: $!");
        return;
    }

    # Read the file and uncollapse the data into a hash again.
    my %oldhash;
    my @flat = <$handle>;
    $self->logger->("Read the raw file");
    close($handle);
    my $flat = join("",@flat);
    my %fluffy = %{Storable->inflate(\$flat)};
    return %fluffy;
}
    
###############################################################################
# put ($name, $contentsref, $version) - store an entry.
###############################################################################

sub put {
    my ($self, $name, $contents, $version) = @_;

    # Fix up the version.
    if ($version eq "") {
        $version = 1;
    }
    else {
        $version += 0;		# Force to numeric
    }

    $self->setError();
    my $handle = $gensym++;

    # Open the file, if we can.
    my $target = "$self->{DirName}/$name,$version";
    unless(open($handle, ">$target")) {
        $self->setError("Cannot write to $target: $!");
        return undef;
    }

    # Flatten and store.
    my $flat = Storable->flatten($contents);
    my $oldfh = select($handle);
    print $handle $flat; 
    select $oldfh;
    close $handle;

    # ensure it is group-writeable (insert-mail support).
    chmod 0664,$target;

    return 1;
}

###############################################################################
# delete ($title) - remove an entry; use most recent version if none supplied
###############################################################################

sub delete {
    my($self,$name,$version) = @_;

    # Fix up the version.
    if ($version eq undef) { 
        $version = $self->max_version($name);
    }
    else {
        $version += 0 if $version ne "";	# Force to numeric if needed
    }

    # Report an error if the version doesn't exist.
    unless ($self->defined($name,$version)) {
        $self->setError("$self->{DirName}/$name,$version does not exist");
        return undef;
    }

    # Do it.
    $self->setError();
    my $file = "$self->{DirName}/$name,$version";
    unlink $file if (-e $file);
}

###############################################################################
# purge($title) - remove all versions of an entry
###############################################################################

sub purge {
    my($self,$name) = @_;

    # Rewind so we see all the files.
    $self->setError();
    $self->dh_reset or return 0;

    # Note fancy implied loop done by map. readdir() is evaluated in list
    # context, so it returns all names in the directory.
    map unlink($self->{DirName} . "/" . $_), # remove files ...
               grep(/^$name,/,		      # ... matching this ...
                    readdir $self->{Handle});     # ... in list of files in dir
    $self->{Rewound} = 0;
    return 1;
}

###############################################################################
# iterator() - return a list of all highest-version keys.
###############################################################################

sub iterator {
    my($self) = shift;

    # Get list of all names.
    $self->setError();
    $self->dh_reset or return;    # undefined value

    my (@names) = readdir $self->{Handle};
    $self->{Rewound} = 0;

    # Scan through names, returning highest-numbered version for each.
    my %highest = ();
    foreach (@names) {
        $^W=0;
        my($name,$version) = /^(.*),(.*)/;
        if ($highest{$name} < $version) {
            $highest{$name} = $version;
        }
        $^W=1;
    }

    #  Build iterator as "name,version" entries.
    @names = ();
    foreach (keys %highest) {
        push @names,"$_,$highest{$_}";
    }
    return @names;
}

###############################################################################
# logger(REF) - set calback for message handling
###############################################################################
sub logger {
   my $self = shift;
   $self->{Logger} = shift if int @_;
   $self->{Logger};
}

###############################################################################
# fatal(REF) - set calback for message handling
###############################################################################
sub fatal {
   my $self = shift;
   $self->{Fatal} = shift if int @_;
   $self->{Fatal};
}

###############################################################################
# setError($msg, $msg, $msg ...) - logical "$!" for this instance
###############################################################################

sub setError {
    my ($self) = shift;
    $self->{ErrorMsg} = join(" ",@_);
    $self->logger->($self->{ErrorMsg}) if int @_;
    return 1;
}

###############################################################################
# getError() - fetch last error that occurred.
###############################################################################

sub getError {
    return $self->{ErrorMsg};
}

##############################################################################
# lock_limit() - set/get the number of seconds to wait for a lock
##############################################################################

sub lock_limit {
    my ($self,$limit) = @_;
    $self->{LockLimit} = $limit if defined $limit;
    $self->{LockLimit};
}

###############################################################################
# dh_reset - "rewind" the directory handle as appropriate.
#            Required for proper operation under Win32 Perl.
#
# Returns true if success or false if failure.
###############################################################################
sub dh_reset {
    my $self = shift;
    my $success = 1;

    if ($^O eq 'MSWin32') {
	closedir($self->{Handle});
	opendir($self->{Handle},$self->{DirName}) or
	  $success = 0;
    }
    else {
	rewinddir $self->{Handle};
    }
    $success;
}

##############################################################################
# DESTROY - clean up and shut down
##############################################################################
sub DESTROY {
    my $self = shift;
    closedir $self->{Handle} if defined $self->{Handle};
}

1;








