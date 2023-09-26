use Mojo::Base -strict;

use Test2::V0;
use Test::Mojo;
use WebWebXNG;
use WebWebXNG::Model::Settings;

use File::Temp qw(tempfile);

my $app;

my(undef, $filename) = tempfile();
$ENV{SQLITE_FILE} = $filename unless $ENV{SQLITE_FILE};
ok lives { $app = WebWebXNG->new },
  "lives if database path is there";

ok $app->sqlite->db, "database is initialized";

my $path = $app->home->child('schema', 'db.schema');
ok $path, "found path to schema";
$app->sqlite->auto_migrate(1)->migrations->name('users')->from_file($path);
$app->sqlite->auto_migrate(1)->migrations->name('settings')->from_file($path);

my $user_model = WebWebXNG::Model::User->new(sqlite => $app->sqlite);
ok $user_model, "got user model";

# 2. Adding a user works, and the added user exists.
my $result = $user_model->add("TestUserOne", "Test", "User", "test\@example.com", "thiswillnotflylater88%Q");
ok $result, "user was added successfully";
ok defined $user_model->exists("TestUserOne"), "exists confirms";

# 7. Password hashing works.
ok !$user_model->validate_login('TestUserOne', 'wrong'), "bad password fails";
ok !$user_model->validate_login('TestUserOne', 'thiswillnotflylater88%Q'), "good password fails for unverified user";
$user_model->set_verified('TestUserOne');
ok $user_model->validate_login('TestUserOne', 'thiswillnotflylater88%Q'), "good password works for verified user";

done_testing();
