use Mojo::Base -strict;

use Test2::V0;
use Test::Mojo;

my $t = Test::Mojo->new('WebWebXNG');
# Old standard test
$t->get_ok('/')->status_is(200)->content_like(qr/Mojolicious/i);

# Verify routes were installed.
$t->get_ok('/ViewPage')->status_is(200)->content_like(qr/Mojolicious/i);

done_testing();
