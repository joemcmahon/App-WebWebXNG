use Mojo::Base -strict;

use Test2::V0;
use WebWebXNG::LinkSyntax qw(is_valid_linkname);

my %checks = (
  'test' => 0,
  'Test' => 0,
  'TestPage' => 1,
  '7' => 0,
  'SevenSeven7' => 0,
  'SevenSevenSeven' => 1,
  'MajorTom?' => 0,
  'McMahon' => 1,
  'MCHammer' => 0,
);

for my $check (keys %checks) {
  is is_valid_linkname($check), $checks{$check},
    $check . ($checks{$check} ? " is " : " isn't ") . "valid";
}
done_testing();
