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

# passwords must be:
#  - at least 10 chars
#  - have one digit, one upper, one lower, and one special.

# Note we don't have any checks for 'easy' passwords, like
# 'qwertyuiop999!Z'. We probably should add something like that later.
# No doubt there's a module.
my @bad = (
 'z',
 'test1',
 'abc123',
 'FelaKuti476532',
 'morbo!morbo!evenemorbo!',
);

my @accepted = (
 '1234567890Aa.',
 'M0rphology#',
 'nbdu8348ndjKI8#'
);

for my $bad (@bad) {
  ok !$user_model->_password_is_reasonable($bad), "$bad is definitely bad";
}
for my $good (@accepted) {
  ok $user_model->_password_is_reasonable($good), "$good is accepted";
}
done_testing();
