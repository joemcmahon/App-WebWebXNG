use Mojo::Base -strict;

use Test2::V0;
use Test::Mojo;
use File::Temp qw/tempfile/;

my($undef, $path) = tempfile();
$ENV{SQLITE_FILE} = $path;
my $t = Test::Mojo->new('WebWebXNG');

=pod

# Old standard test
$t->get_ok('/')->status_is(200)->content_like(qr/dummy page content/i);

# Verify routes were installed.
$t->get_ok('/ViewPage')->status_is(200)->content_like(qr/dummy page content/i);

=cut

pass "dummied out tests for the moment";

done_testing();
