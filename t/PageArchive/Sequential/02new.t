use strict;
use warnings;
use Test2::V0;

use File::Temp qw(tempdir);
use File::Spec;

use PageArchive::Sequential;

my $archive;

# Verify exception if no page repo dir
like dies{ $archive = PageArchive::Sequential->new() }, qr/No page storage directory supplied/, "dies with no directory provided";

# Base test. Lives if we have a page repo.
my $dir = tempdir(CLEANUP => 1);
$archive = PageArchive::Sequential->new($dir);
ok $archive, "got an object";
ok defined $archive->{_logger}, "default logger installed";
ok defined $archive->{_fatal},  "defailt fatal installed";

ok !$archive->get_error, 'no error when started up';
ok $archive->_archive_handle, 'we got an archive handle';

# Fails if the supplied item doesn't exist or isn't a directory.
$dir = tempdir(CLEANUP => 1);
chmod 0000, $dir;
like dies { $archive = PageArchive::Sequential->new($dir) }, qr/Cannot open/, "dies if supplied item isn't readable";
chmod 0777, $dir;
my $file = File::Spec->catfile($dir,"justafile");
open my $fh, ">", $file;
close $fh;
like dies { $archive = PageArchive::Sequential->new($file) }, qr/exists, but is not a directory/, "dies if target isn't a directory";

done_testing;
