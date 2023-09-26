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

# Adding a user works, and the added user exists.
my $result = $user_model->add("TestUserOne", "Test", "User", "test\@example.com", "thiswillnotflylater77Z!");
ok $result, "user was added successfully";
ok defined $user_model->exists("TestUserOne"), "exists confirms";

# Can add another user with the same email.
$result = $user_model->add("TestUserAdmin", "Test", "User", "test\@example.com", "thiswillnotflylater77Z!");
ok $result, "user was added successfully";
ok defined $user_model->exists("TestUserAdmin"), "exists confirms";

done_testing();
