use strict;
use warnings;
use Test2::V0;

use File::Temp qw(tempdir);

use PageArchive::Sequential;

sub mk_archive {
  my $dir = tempdir(CLEANUP => 1);
  ($dir, PageArchive::Sequential->new($dir));
}

# Add unversioned page (version 1).
my ($dir, $archive) = mk_archive();
my $contents = {dummy => "contents"};
my $name = "SamplePage";

ok $archive->put($name, $contents), "put call succeeded";
is $archive->get_error, "", "no error message";
ok $archive->page_exists($name,1), "version 1 there";

$contents = {dummy => "new contents"};
ok $archive->put($name, $contents, 2), "save updated version succeeds";
is $archive->get_error, "", "no error message";
ok $archive->page_exists($name,2), "version 2 there";

# Add a two-digit version with a high leading number.
ok $archive->put($name, $contents, 95), "save updated version succeeds";
is $archive->get_error, "", "no error message";
ok $archive->page_exists($name, 95), "version 95 there";

# Add a three-digit version with a leading number less than the two-digit
# high leading number. This ensures that we are actually doing a numeric
# sort, not a string one.
ok $archive->put($name, $contents, 437), "save updated version succeeds";
is $archive->get_error, "", "no error message";
ok $archive->page_exists($name, 437), "version 437 there";

my $v = $archive->max_version($name);
is $v, 437, "verify true max version is found";

done_testing;
