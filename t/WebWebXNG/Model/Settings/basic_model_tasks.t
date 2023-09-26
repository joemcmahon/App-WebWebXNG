use Mojo::Base -strict;

use Test2::V0;
use Test::Mojo;
use WebWebXNG;
use WebWebXNG::Model::Settings;

use File::Temp qw(tempfile);

my $app;

my(undef, $filename) = tempfile();
$ENV{SQLITE_FILE} = $filename;
ok lives { $app = WebWebXNG->new },
  "lives if database path is there";

ok $app->sqlite->db, "database is initialized";

my $path = $app->home->child('schema', 'db.schema');
ok $path, "found path to schema";
$app->sqlite->auto_migrate(1)->migrations->name('users')->from_file($path);
$app->sqlite->auto_migrate(1)->migrations->name('settings')->from_file($path);

my $settings_model = WebWebXNG::Model::Settings->new(sqlite => $app->sqlite);
ok $settings_model, "got model";

my $elsewhere = "/just/for/testing";
my $settings = $settings_model->load();
is $settings->{front_page}, "FrontPage", "got expected front page default from initial load";
is $settings->{aggressive_locking}, 1, "got expected locking default from initial load";
is $settings->{data_dir}, "", "got expected data directory default from initial load";

done_testing();
