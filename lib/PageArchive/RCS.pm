package PageArchive::RCS;

=head1 NAME

PageArchive::RCS - implements the WebWebXNG PageArchive protocol for RCS-based
page archives.

=head1 SYNOPSIS

    my $archive = PageArchive::RCS->new($dirname, %File_LockDir_params);

=head1 DESCRIPTION

Provide database-like access (with versioning) to files in a
directory. The files contain frozen Storable objects and are cached
in a DBM-backed hash. This particular implementation has code to work around the problem
that some Perl installations didn't have a Perl-accessible DBM package
that could handle entries bigger than 1K.

=cut

use Carp;
use Storable;
use File::LockDir;
use Data::Dumper;

=head1 CLASS METHODS

=head2 new

Create a new PageArchive object:

=over

=item * Verifies that the directory can be opened.

=item * Saves a filehandle usable with readdir() and the name of the directory for building file names.

=back

=cut

sub new {
    my ($class, $dirname, %params) = @_;
    my $self = {};
    bless $self,$class;

    # Set up the File::LockDir callbacks.
    $self->logger($params{Logger} || sub { print STDERR @_ });
    $self->fatal($params{Fatal}   || sub { croak @_ });

    $self->setError();

    # Verify that dir name is OK; try to create it if we must;
    # return undef if we can't.
    unless (-d $dirname) {	# Not a dir or doesn't exist
        unless (-e $dirname) {  # Doesn't exist
            # Make the directory, including parent dirs.
            # Return undef if we fail along the way.
            # XXX: use File::Path!
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

=head2 DESTROY

Clean up and shut down

=cut

sub DESTROY {
    my $self = shift;
    closedir $self->{Handle} if defined $self->{Handle};
}

=head1 INSTANCE METHODS

=head1 defined($name, $version)

Determine whether or not an entry exists.

Returns undef if no versions exist, or a list of versions if multiple
versions exist.

=cut

sub defined {
    my($self, $name, $version) = @_;
    $version = "" unless defined $version;

     # Search directory for filenames matching.
    $self->dh_reset;
    return grep(/^$name,$version/,readdir $self->{Handle});
    $dir->{Rewound} = 0;
}

=head2 lock($name)

Lock the entry (all versions).

Returns undef if the entry can't be locked, true otherwise.

=cut

sub lock {
    my ($self, $name, $who, $host) = @_;
    my ($which,$locked_by)  =
        nflock("$self->{DirName}/$name", $self->lock_limit(), $who, $host);
    return ($which, $locked_by);
}

=head2 unlock($name)

Unlock the entry (all versions).

Returns undef if the entry wasn't locked, true otherwise.

=cut

sub unlock {
    my ($self, $name) = @_;
    nunflock("$self->{DirName}/$name");
}

=head2 is_unlocked($name)

See if an entry is locked.

Returns: (1, undef) if the entry is unlocked
         (undef, "<locker> at <host> since <date and time>") if locked

=cut

sub is_unlocked {
    my ($self,$name) = @_;
    return nlock_state("$self->{DirName}/$name");
}

=head2 max_version($name)

Determine the maximum version # of a given entry.

Returns the version number of the newest version.

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

=head2 get($name,$version)

Fetch a specified version of the entry.

Finds the file, reads it, and uses Storable::inflate to restore it.

=cut

sub get {
    my($self, $name, $version) = @_;
    $version = $self->max_version($name) unless $version;

    $self->logger->("Getting $name,$version");
    $self->setError();

    unless ($self->defined($name,$version)) {
        $self->setError("$self->{DirName}/$name,$version does not exist");
        return;
    }

    # This shouldn't happen, unless someone's been fiddling with the database.
    unless(open(my $handle, $self->{DirName} . "/" . $name . "," . $version)) {
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

=head2 put ($name, $contentsref, $version)

Store an entry.

=cut

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

    # Open the file, if we can.
    my $target = "$self->{DirName}/$name,$version";
    unless(open(my $handle, ">$target")) {
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

=head2 delete ($title)

Remove an entry; use most recent version if none supplied

=cut

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

=head2 purge($title) - remove all versions of an entry

=cut

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

=head2 iterator()

Return a list of all highest-version keys.

=cut

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

=head2 logger(REF)

Set calback for message handling

=cut

sub logger {
   my $self = shift;
   $self->{Logger} = shift if int @_;
   $self->{Logger};
}

=head2 fatal(REF)

Set calback for message handling

=cut

sub fatal {
   my $self = shift;
   $self->{Fatal} = shift if int @_;
   $self->{Fatal};
}

=head2 setError($msg, $msg, $msg ...)

Global error message capture for this instance

=cut

sub setError {
    my ($self) = shift;
    $self->{ErrorMsg} = join(" ",@_);
    $self->logger->($self->{ErrorMsg}) if int @_;
    return 1;
}

=head2  getError()

Fetch last error that occurred.

=cut

sub getError {
    return $self->{ErrorMsg};
}

=head2 lock_limit()

Set/get the number of seconds to wait for a lock

=cut

sub lock_limit {
    my ($self,$limit) = @_;
    $self->{LockLimit} = $limit if defined $limit;
    $self->{LockLimit};
}

=head2 dh_reset

"Rewind" the directory handle as appropriate. Required for proper
operation under Win32 Perl.

Returns true if success or false if failure.

=cut

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

1;

