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

ok $archive->lock($name, 2), "lock second version";
my %check = $archive->get($name, 2);
is \%check, \%new, "can still read locked file";

my %not_there = $archive->get($name, 18);
is \%not_there, {},"Nothing there for a non-existent version";
my $err = $archive->get_error();
like $err, qr/version 18 of SamplePage does not exist/, "right error message";

my %recent = $archive->get($name);
is \%recent, \%new, "no version gets most recent";

done_testing;
