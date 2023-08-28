use Mojo::Base -strict;

use Test2::V0;
use Test::Mojo;

my $app = Test::Mojo->new('WebWebXNG')->app;
my $config = $app->plugin('NotYAMLConfig');
is $config->{front_page}, 'FrontPage', "loaded defaults";

done_testing();
