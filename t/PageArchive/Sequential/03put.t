use strict;
use warnings;
use Test2::V0;

use File::Temp qw(tempdir);

use PageArchive::Sequential;

sub mk_archive {
  my $dir = tempdir(CLEANUP => 1);
  ($dir, PageArchive::Sequential->new($dir));
}

# Add unversioned page.
my ($dir, $archive) = mk_archive();
my $contents = {dummy => "contents"};
my $name = "SamplePage";

ok $archive->put($name, $contents), "put call succeeded";
is $archive->get_error, "", "no error message";
my $fname = $archive->_page_in_archive($name, 1);
ok -e $fname, "versioned file exists";

chmod 0000, $fname;
ok !$archive->put($name, $contents), "put call failed";
like $archive->get_error, qr/can't create .*SamplePage,1: Permission denied/, "right error";

ok $archive->put($name, $contents, 2), "explicit version succeeds";
is $archive->get_error, "", "no error message";
$fname = $archive->_page_in_archive($name, 2);
ok -e $fname, "versioned file exists";
ok $archive->page_exists($name), "at least one version exists";
ok $archive->page_exists($name,1), "version 1 still there";
ok $archive->page_exists($name,2), "version 2 still there";
ok ! $archive->page_exists($name,44), "nonexistent version not there";

done_testing;
