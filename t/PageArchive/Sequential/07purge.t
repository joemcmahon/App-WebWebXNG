use strict;
use warnings;
use Test2::V0;

use File::Temp qw(tempdir);

use PageArchive::Sequential;

my @msgs;

sub stack_it {
  push @msgs, join " ", @_;
}

sub mk_archive {
  my $dir = tempdir(CLEANUP => 1);
  ($dir, PageArchive::Sequential->new($dir, logger => \&stack_it));
}

my ($dir, $archive) = mk_archive();
my $contents = {dummy => "contents"};
my $name = "SamplePage";

ok $archive->purge("blort"), "purging what doesn't exist succeeds";

ok $archive->put($name, $contents), "put call succeeded";
is $archive->get_error, "", "no error message";
ok $archive->page_exists($name,1), "version 1 there";

$contents = {dummy => "new contents"};
ok $archive->put($name, $contents, 2), "save updated version succeeds";
is $archive->get_error, "", "no error message";
ok $archive->page_exists($name,2), "version 2 there";
ok $archive->put($name, $contents, 4), "put an even larger version out there";
my @pages = $archive->page_exists($name);
is scalar @pages, 3, "right number of remaining pages";
is [sort { $a <=> $b } map  { /^.*,(.*)$/; $1 } @pages], [1,2,4], "right pages in archive";
ok $archive->purge($name), "purge worked";
@pages = $archive->page_exists($name);
is scalar @pages, 0, "right number of remaining pages";


done_testing;
