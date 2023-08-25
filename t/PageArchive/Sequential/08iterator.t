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

my %insertions = (
  "alpha" => [1, 2, 3, 4],
  "beta" => [12, 42, 84, 99],
  "delta" => [6],
  "epsilon" => [17, 22, 33, 99],
    );

for my $page (keys %insertions) {
  for my $version (@{$insertions{$page}}) {
    ok $archive->put($page, $contents, $version), "add $page $version";
    is $archive->get_error, "", "no error message";
  }
}

my @currentest = $archive->iterator();
is scalar @currentest, 4, "right number of pages in iterator";
is [sort @currentest], ["alpha,4", "beta,99", "delta,6", "epsilon,99"], "right page names";

done_testing;
