use strict;
use warnings;

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

use constant DEFAULT_LOCK_LIMIT => 30;

=head1 CLASS METHODS

=head2 new

Create a new PageArchive object:

=over

=item * Verifies that the directory can be opened.

=item * Saves a filehandle usable with readdir() and the name of the directory for building file names.

=back

=cut

sub new {
  my ( $class, $dirname, %params ) = @_;
  die "No page storage directory supplied" unless $dirname;

  my $self = {};
  bless $self, $class;

  # Set up the File::LockDir callbacks.
  $self->logger( $params{Logger} || sub { print STDERR @_ } );
  $self->fatal( $params{Fatal}   || sub { croak @_ } );

  $self->set_error();

  # Verify that dir name is OK; try to create it if we must;
  # return undef if we can't.
  unless ( -d $dirname ) {    # Not a dir or doesn't exist
    unless ( -e $dirname ) {    # Doesn't exist
                                # Make the directory, including parent dirs.
                                # Return undef if we fail along the way.
                                # XXX: use File::Path!
      my @path             = split( '/', $dirname );
      my $accumulated_path = "";
      foreach (@path) {
        $accumulated_path .= "/$_";
        next if -e $accumulated_path and -d _;
        unless ( mkdir $accumulated_path, 0700 ) {
          $self->fatal->("Can't create $accumulated_path: $!");
        }
      }
    } else {    # Exists, but is not a directory
      $self->fatal->("$dirname exists, but is not a directory");
    }
  } else {    # is a directory (and exists)
    $self->_dirname($dirname);
    $self->lock_limit(DEFAULT_LOCK_LIMIT);

    # See if we can read the directory; die if not.
      my $h;
      if (not opendir( $h, $dirname ) ) {
        $self->fatal->("Cannot open $dirname: $!");
      } else {
        $self->_archive_handle($h);
      }
 }

  # Initialize File::LockDir.
  $self->_locker(
    File::LockDir->new(
      fatal  => $self->fatal,
      logger => $self->logger,
    )
  );

  return $self;
}

=head2 DESTROY

Clean up and shut down

=cut

sub DESTROY {
  my $self = shift;
  closedir $self->_archive_handle if defined $self->_archive_handle;
}

=head1 INSTANCE METHODS

=head2 defined($name, $version)

Determine whether or not an entry exists.

Returns undef if no versions exist, or a list of versions if multiple
versions exist.

=cut

sub defined {
  my ( $self, $name, $version ) = @_;
  $version = "" unless defined $version;

  # Search directory for filenames matching.
  $self->dh_reset;
  $self->{Rewound} = 0;
  return grep( /^$name,$version/, readdir $self->_archive_handle );
}

=head2 lock($name)

Lock the entry (all versions).

Returns undef if the entry can't be locked, true otherwise.

=cut

sub lock {
  my ( $self, $name, $who, $host ) = @_;
  my ( $which, $locked_by ) =
    $self->locker->nflock(
      $self->_page_in_archive($name),
      $self->lock_limit(),
      $who,
      $host );
  return ( $which, $locked_by );
}

=head2 unlock($name)

Unlock the entry (all versions).

Returns undef if the entry wasn't locked, true otherwise.

=cut

sub unlock {
  my ( $self, $name ) = @_;
  $self->locker->nfunlock($self->_page_in_archive($name));
}

=head2 is_unlocked($name)

See if an entry is locked.

Returns: (1, undef) if the entry is unlocked
         (undef, "<locker> at <host> since <date and time>") if locked

=cut

sub is_unlocked {
  my ( $self, $name ) = @_;
  return $self->locker->nlock_state($self->_page_in_archive($name));
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
  my ( $self, $name, $version ) = @_;
  $version = $self->max_version($name) unless $version;

  $self->logger->("Getting $name,$version");
  $self->set_error();

  unless ( $self->defined( $name, $version ) ) {
    $self->set_error($self->_page_in_archive . ",$version does not exist");
    return;
  }

  # This shouldn't happen, unless someone's been fiddling with the database.
  my $handle;
  my $pagefile = $self->_page_in_archive($name, $version);
  unless ( open($handle, "<", $pagefile) ) {
    $self->set_error("Unreadable file $pagefile: $!");
    return;
  }

  # Read the file and uncollapse the data into a hash again.
  my %oldhash;
  my @flat = <$handle>;
  $self->logger->("Read the raw file");
  close($handle);
  my $flat   = join( "", @flat );
  my %fluffy = %{ Storable->inflate( \$flat ) };
  return %fluffy;
}

=head2 put ($name, $contentsref, $version)

Store an entry.

=cut

sub put {
  my ( $self, $name, $contents, $version ) = @_;

  # Fix up the version.
  if ( $version eq "" ) {
    $version = 1;
  } else {
    $version += 0;    # Force to numeric
  }

  $self->set_error();

  # Open the file, if we can.
  my $target = $self->_page_in_archive($name, $version);
  my $handle;
  unless ( open( $handle, ">", "$target" ) ) {
    $self->set_error("Cannot write to $target: $!");
    return;
  }

  # Flatten and store.
  my $flat  = Storable->flatten($contents);
  my $oldfh = select($handle);
  print $handle $flat;
  select $oldfh;
  close $handle;

  # ensure it is group-writeable (insert-mail support).
  chmod 0664, $target;

  return 1;
}

=head2 delete ($title)

Remove an entry; use most recent version if none supplied

=cut

sub delete {
  my ( $self, $name, $version ) = @_;

  # Fix up the version.
  if ( $version eq undef ) {
    $version = $self->max_version($name);
  } else {
    $version += 0 if $version ne "";    # Force to numeric if needed
  }

  # Report an error if the version doesn't exist.
  unless ( $self->defined( $name, $version ) ) {
    my $pagefile = $self->_page_in_archive($name, $version);
    $self->set_error("$pagefile does not exist");
    return;
  }

  # Do it.
  $self->set_error();
  my $pagefile = $self->_page_in_archive($name, $version);
  unlink $pagefile if ( -e $pagefile );
}

=head2 purge($title) - remove all versions of an entry

=cut

sub purge {
  my ( $self, $name ) = @_;

  # Rewind so we see all the files.
  $self->set_error();
  $self->dh_reset or return 0;

  # Note fancy implied loop done by map. readdir() is evaluated in list
  # context, so it returns all names in the directory.
  map unlink( $self->_dirname . "/" . $_ ),    # remove files ...
    grep( /^$name,/,                            # ... matching this ...
    readdir $self->_archive_handle );           # ... in list of files in dir
  $self->{Rewound} = 0;
  return 1;
}

=head2 iterator()

Return a list of all highest-version keys.

=cut

sub iterator {
  my ($self) = shift;

  # Get list of all names.
  $self->set_error();
  $self->dh_reset or return;    # undefined value

  my (@names) = readdir $self->_archive_handle;
  $self->{Rewound} = 0;

  # Scan through names, returning highest-numbered version for each.
  my %highest = ();
  foreach (@names) {
    $^W = 0;
    my ( $name, $version ) = /^(.*),(.*)/;
    if ( $highest{$name} < $version ) {
      $highest{$name} = $version;
    }
    $^W = 1;
  }

  #  Build iterator as "name,version" entries.
  @names = ();
  foreach ( keys %highest ) {
    push @names, "$_,$highest{$_}";
  }
  return @names;
}

=head2 logger(REF)

Set calback for message handling

=cut

sub logger {
  my $self = shift;
  $self->{_logger} = shift if int @_;
  $self->{_logger};
}

=head2 fatal(REF)

Set calback for message handling

=cut

sub fatal {
  my $self = shift;
  $self->{_fatal} = shift if int @_;
  $self->{_fatal};
}

=head2 _archive_handle

Dirhandle pointing to the page archive. This method is
privaet because callers should not be trying to directly
access the archive.

=cut

sub _archive_handle {
  my ($self, $handle) = @_;
  $self->{Handle} = $handle if defined $handle;
  $self->{Handle};
}

=head2 set_error($msg, $msg, $msg ...)

Global error message capture for this instance

=cut

sub set_error {
  my ($self) = shift;
  $self->{ErrorMsg} = join( " ", @_ );
  $self->logger->( $self->{ErrorMsg} ) if int @_;
  return 1;
}

=head2  get_error()

Fetch last error that occurred.

=cut

sub get_error {
  my ($self) = @_;
  return $self->{ErrorMsg};
}

=head2 lock_limit()

Set/get the number of seconds to wait for a lock

=cut

sub lock_limit {
  my ( $self, $limit ) = @_;
  $self->{LockLimit} = $limit if defined $limit;
  $self->{LockLimit};
}

=head2 dh_reset

"Rewind" the directory handle as appropriate. Required for proper
operation under Win32 Perl.

Returns true if success or false if failure.

=cut

sub dh_reset {
  my $self    = shift;
  my $success = 1;

  if ( $^O eq 'MSWin32' ) {
    closedir( $self->_archive_handle );
    opendir( $self->_archive_handle, $self->_dirname )
      or $success = 0;
  } else {
    rewinddir $self->_archive_handle;
  }
  $success;
}

sub _page_in_archive {
  my ($self, $page_name, $version) = @_;
  my $f = File::Spec->catdir($self->dirname, $page_name);
  $f = "$f,$version" if defined $version;
  return $f;
}

sub _dirname {
  my($self, $name) = @_;
  $self->{_dirname} = $name if defined $name;
  $self->{_dirname};
}

sub _locker {
  my ( $self, $locker_object ) = @_;
  $self->{_locker} = $locker_object if defined $locker_object;
  $self->{_locker};
}

1;

