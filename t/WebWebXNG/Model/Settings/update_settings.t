use Mojo::Base -strict;

use Test2::V0;
use Test::Mojo;
use WebWebXNG;
use WebWebXNG::Model::Settings;

use File::Temp qw(tempfile);

my $app;

my(undef, $filename) = tempfile();

# Use a temporary DB unless overridden. Should
# only override if you are developing and need to
# save the DB contents.
$ENV{SQLITE_FILE} = $filename unless $ENV{SQLITE_FILE};

ok lives { $app = WebWebXNG->new },
  "lives if database path is there";

ok $app->sqlite->db, "database is initialized";

my $path = $app->home->child('schema', 'db.schema');
ok $path, "found path to schema";
$app->sqlite->auto_migrate(1)->migrations->name('users')->from_file($path);
$app->sqlite->auto_migrate(1)->migrations->name('settings')->from_file($path);

my $settings_model = WebWebXNG::Model::Settings->new(sqlite => $app->sqlite);
ok $settings_model, "got model";

my $initial = $settings_model->load();

my $overrides;
my $elsewhere = "/just/for/testing" . rand();
$overrides->{front_page} = "AlteredLocation";
$settings_model->save($overrides);
$overrides->{data_dir} = $elsewhere;
$settings_model->save($overrides);

my $combined = $settings_model->load();
is $combined->{front_page}, "AlteredLocation", "successfully saved changed item";
is $combined->{data_dir}, $elsewhere, "saved new item";
is $combined->{aggressive_locking}, 1, "got expected old locking default in updated settings";

done_testing();
