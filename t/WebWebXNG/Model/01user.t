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

# 1. Fetching a non-existent user returns undef and does not change the DB.
my $user = $user_model->exists("blorg");
ok  !defined($user), "nonexistent user detected correctly";

# 2. Adding a user works, and the added user exists.
my $result = $user_model->add("TestUserOne", "Test", "User", "test\@example.com", "thiswillnotflylater");
ok $result, "user was added successfully";
ok defined $user_model->exists("TestUserOne"), "exists confirms";

# 2.1 Adding a user with the same username fails.
# 2.2 Adding a user with the same email address fails.
# 3. Newly-added users are not verified.
ok !$user_model->is_verified("TestUserOne"), "initially not verified";
# 4. Password hashing works.
# 5. Marking a user as verified works.

done_testing();
