use strict;
use warnings;
use Test2::V0;

use File::Temp qw(tempdir);

use PageArchive::RCS;

my $archive;

# Verify exception if no page repo dir
like dies{ $archive = PageArchive::RCS->new() }, qr/No page storage directory supplied/, "dies with no directory provided";

# Base test. Lives if we have a page repo.
my $dir = tempdir(CLEANUP => 1);
$archive = PageArchive::RCS->new($dir);
ok $archive, "got an object";
ok defined $archive->{_logger}, "default logger installed";
ok defined $archive->{_fatal},  "defailt fatal installed";

ok !$archive->get_error, 'no error when started up';
ok $archive->_archive_handle, 'we got an archive handle';

done_testing;
