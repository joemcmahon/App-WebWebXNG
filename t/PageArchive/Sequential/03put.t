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

done_testing;
