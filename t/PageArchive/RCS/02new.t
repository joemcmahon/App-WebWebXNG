use strict;
use warnings;
use Test::More;
use Test::Exception;

use File::Temp qw(tempdir);

use PageArchive::RCS;

my $archive;

# Verify exception if no page repo dir
dies_ok { $archive = PageArchive::RCS->new() } "dies with no directory provided";

# Base test. Lives if we have a page repo.
my $dir = tempdir(CLEANUP => 1);
lives_ok { $archive = PageArchive::RCS->new($dir) } "lives with directory provided";
ok $archive, "got an object";
ok defined $archive->{_logger}, "default logger installed";
ok defined $archive->{_fatal},  "defailt fatal installed";

ok !$archive->get_error, 'no error when started up';
ok $archive->_archive_handle, 'we got an archive handle';

done_testing;
