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

# Add unversioned page.
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
ok ! $archive->page_exists($name,44), "nonexistent version not there";

my %old = $archive->get($name, 1);
is \%old, {dummy => "contents"}, "got expected data";
my %new = $archive->get($name, 2);
is \%new, {dummy => "new contents"}, "got expected (new) data";

ok !$archive->delete($name, 9), "can't delete nonexistent version";
like $archive->get_error, qr/does not exist/, "right error";

ok $archive->delete($name), "delete with no version works";
ok !$archive->page_exists($name, 2), "deleted newest";
ok $archive->page_exists($name, 1), "left the other one alone";

ok $archive->put($name, $contents, 2), "put it back again";
ok $archive->put($name, $contents, 4), "put an even larger version out there";
ok $archive->delete($name, 2), "delete with explicit version works";
my @pages = $archive->page_exists($name);
is scalar @pages, 2, "right number of remaining pages";
is [sort { $a <=> $b } map  { /^.*,(.*)$/; $1 } @pages], [1,4], "right pages left in archive";

done_testing;
