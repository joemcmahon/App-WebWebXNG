use strict;
use warnings;

package PageArchive::Sequential;
use File::Path qw(make_path);
use Try::Tiny;
use Carp;
use Storable;
use File::LockDir;
use Data::Dumper;

use constant DEFAULT_LOCK_LIMIT => 30;

=head1 NAME

PageArchive::Sequential - implements the WebWebXNG PageArchive protocol for a crude
RCS-like page archive.

=head1 SYNOPSIS

    my $archive = PageArchive::Sequential->new($dirname, %File_LockDir_params);
    my %page = $archive->get($name, $version);
    $archive->put(\%page, $name, $version);


=head1 DESCRIPTION

Provide database-like access (with versioning) to files in a
directory. The files contain frozen Storable objects and are cached
in a DBM-backed hash. This particular implementation has code to work around the problem
that some Perl installations didn't have a Perl-accessible DBM package
that could handle entries bigger than 1K.

=head2 DETAILS

PageArchive uses a naming scheme similar to RCS, in that it creates a "PageName,n"
file for each revision stored, but it does not actually use RCS; it simply writes
another copy of the file with the appended revision. This uses a lot more disk
space, but is very simpleminded and easy to debug.

It's obvious that this is not going to work for really large wikis, but we'll
burn that bridge when we come to it.

There is no working file, just X,1; X,2; X.3; and so on.

We lock I<all> versions of a file when we grab the lock; this prevents someone
from mucking up the history behind our backs while we're attempting an operation.
Obviously something that actually checks out the file in a non-shared area
would be much better. It's done this way in this module because we didn't want
to require anyone deploying the wiki to be beholden to having a particular
SCM installed. (Also because this was the original implementation, and we were
more interested in getting a minimum viable product out.)

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
  $self->logger( $params{Logger} || sub { print STDERR @_,"\n" } );
  $self->fatal( $params{Fatal}   || sub { croak @_ } );

  $self->set_error();

  # Verify that dir name is OK; try to create it if we must;
  # return undef if we can't.
  unless ( -d $dirname ) {    # Not a dir or doesn't exist
    unless ( -e $dirname ) {    # Doesn't exist
      try { make_path($dirname) }
      catch { ($self->fatal->("Can't build path $dirname: $_")) }
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

=head2 page_exists($name, $version)

Determine whether or not an entry exists.

Returns undef if no versions exist, or a list of versions if multiple
versions exist.

=cut

sub page_exists {
  my ( $self, $name, $version ) = @_;
  $version = "" unless defined $version;

  # Search directory for filenames matching.
  $self->_rewind;
  $self->_rewound(0);
  return grep( /^$name,$version/, readdir $self->_archive_handle );
}

=head2 lock($name)

Lock the entry (all versions).

Returns undef if the entry can't be locked, true otherwise.

=cut

sub lock {
  my ( $self, $name, $who, $host ) = @_;
  my ( $which, $locked_by ) =
    $self->_locker->nflock(
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
  $self->_locker->nfunlock($self->_page_in_archive($name));
}

=head2 is_unlocked($name)

See if an entry is locked.

Returns: (1, undef) if the entry is unlocked
         (undef, "<locker> at <host> since <date and time>") if locked

=cut

sub is_unlocked {
  my ( $self, $name ) = @_;
  return $self->_locker->nlock_state($self->_page_in_archive($name));
}

=head2 max_version($name)

Determine the maximum version # of a given entry.

Returns the version number of the newest version.

=cut

sub max_version {
    my($self, $name) = @_;
    $self->_rewind;

   # We use page_exists() to get a list of versions defined for this name,
   # and do a Schwartzian transform to sort the versions descending, then
   # extract the matching filename. Needed because the filenames don't have
   # leading zeroes in the versions, and therefore can't be sorted correctly
   # with 'cmp'.
   my @indexes = map  { $_->[1] }
                 sort { $b->[1] <=> $a->[1] }
                 map  { /^.*,(.*)$/; [$_, $1] }
                 $self->page_exists($name);
   return shift @indexes;

}

=head2 get($name,$version)

Fetch a specified version of the entry.

Finds the file, reads it, and uses Storable::retrieve to restore it.

Returns a hash (I<not> a hash reference!).

=cut

sub get {
  my ( $self, $name, $version ) = @_;
  $version = $self->max_version($name) unless $version;

  $self->logger->("Getting $name,$version") if $self->debug;
  $self->set_error();

  unless ( $self->page_exists( $name, $version ) ) {
    $self->set_error($self->_page_in_archive . ",$version does not exist");
    return;
  }

  # This shouldn't happen, unless someone's been fiddling with the database.
  my $handle;
  my $pagefile = $self->_page_in_archive($name, $version);

  # Read the file and uncollapse the data into a hash again.
  %{retrieve($pagefile)};
}

=head2 put ($name, $contentsref, $version)

Store an entry. Note that we assume version 1 unless we are given a version.
(This may be erroneous; we'll test it.)

=cut

sub put {
  my ( $self, $name, $contents, $version ) = @_;

  # Fix up the version.
  if ( !defined $version or $version eq "" ) {
    $version = 1;
  } else {
    $version += 0;    # Force to numeric
  }

  $self->set_error();

  my $success = 1;
  my $target = $self->_page_in_archive($name, $version);
  eval {
    store $contents, $target;
  };
  if ($@) {
    $self->set_error($@);
    $success = 0;
  }

  return $success;
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
  unless ( $self->page_exists( $name, $version ) ) {
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
  $self->_rewind or return 0;

  # Note fancy implied loop done by map. readdir() is evaluated in list
  # context, so it returns all names in the directory.
  map unlink( $self->_dirname . "/" . $_ ),    # remove files ...
    grep( /^$name,/,                            # ... matching this ...
    readdir $self->_archive_handle );           # ... in list of files in dir
  $self->_rewound(0);
  return 1;
}

=head2 iterator()

Return a list of all highest-version keys.

=cut

sub iterator {
  my ($self) = shift;

  # Get list of all names.
  $self->set_error();
  $self->_rewind or return;    # undefined value

  my (@names) = readdir $self->_archive_handle;
  $self->_rewound(0);

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

=head2 set_error($msg, $msg, $msg ...)

Global error message capture for this instance

=cut

sub set_error {
  my ($self, @args) = @_;
  if (@args) {
    @args = map { defined $_ ? $_ : "" } @args;
    $self->{_error_message} = join( " ",  @args );
    $self->logger->( $self->{_error_message} );
  } else {
    $self->{_error_message} = "";
  }
  return 1;
}

=head2  get_error()

Fetch last error that occurred.

=cut

sub get_error {
  my ($self) = @_;
  return $self->{_error_message};
}

=head2 lock_limit()

Set/get the number of seconds to wait for a lock

=cut

sub lock_limit {
  my ( $self, $limit ) = @_;
  $self->{LockLimit} = $limit if defined $limit;
  $self->{LockLimit};
}

=head2 debug

Setter/getter for debugging flag.

=cut

sub debug {
  my($self, $state) = @_;
  $self->{_debug} = $state if defined $state;
  $self->{_debug};
}

=head1 PRIVATE METHODS

These methods are documented so that anyone working on this module has
a reference for the methods and what they do; they are not a critical
part of the interface. Any new interface implementing the same protocol
will only need to implement the public methods.

=head2 _archive_handle

Dirhandle pointing to the page archive. This method is
private because callers should not be trying to directly
access the archive, and because access to the directory
handle is only needed for this module.

=cut

sub _archive_handle {
  my ($self, $handle) = @_;
  $self->{Handle} = $handle if defined $handle;
  $self->{Handle};
}

=head2 _rewind

"Rewind" the directory handle as appropriate. Required to ensure
that we access all of the files in the directory for operations
that read the directory in toto.

Note that Win32 doesn't implement rewinddir; for proper operation
under Win32 Perl, we have to close and reopen the handle to ensure
that we read the whole thing.

Returns true if success or false if failure.

=cut

sub _rewind {
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

=head2 _page_in_archive

Creates the proper path to a page by name and revision.

=cut

sub _page_in_archive {
  my ($self, $page_name, $version) = @_;
  $version = $self->max_version($page_name) unless $version;
  my $f = File::Spec->catdir($self->_dirname, $page_name);
  "$f,$version";
}

=head2 _dirname

Stores the archive directory name. Needed in particular for Win32 to be
able to reopen the directory for a simulated rewinddir().

=cut

sub _dirname {
  my($self, $name) = @_;
  $self->{_dirname} = $name if defined $name;
  $self->{_dirname};
}

=head2 _rewound

Maintains rewind state so that we can minimize the number of
rewind operations. (It looks like we almost always unconditionally
rewind anyway right now, so this code may be removed.)

=cut

sub _rewound {
  my ($self, $state) = @_;
  $self->{_rewound} = $state if defined $state;
  $self->{_rewound};
}

=head2 _locker

Holds the File::LockDir object for this page archive. Not
needed if there's some other mechanism for locking pages
or otherwise controlling access.

=cut

sub _locker {
  my ( $self, $locker_object ) = @_;
  $self->{_locker} = $locker_object if defined $locker_object;
  $self->{_locker};
}

1;

