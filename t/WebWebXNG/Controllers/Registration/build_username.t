use Mojo::Base -strict;

use Test2::V0;
use Test::Mojo;
use WebWebXNG;
use WebWebXNG::Controller::RegistrationController;

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

my %tests = (
    "specified name" => {
      args => {
        first_name => 'Test',
        last_name  => 'User',
        username   => "UsingThisOne",
      },
      result => qr/Using chosen username 'UsingThisOne'/,
    },
    "made from names" => {
      args => {
        first_name => 'Test',
        last_name  => 'User',
        username   => "Bad1",
      },
      result => qr/Using username 'TestUser'/,
    },
    'recapitalized' =>{
      args => {
        first_name => 'DJ',
        last_name  => 'blerk',
        username   => "",
      },
      result => qr/Using username 'DjBlerk'/,
    },
    'ASCIfied 1' =>{
      args => {
        first_name => 'hervé',
        last_name  => 'ørdström',
        username   => "",
      },
      result => qr/Using username 'HerveOrdstrom'/,
    },
    'ASCIIfied 2' =>{
      args => {
        first_name => ' 欣妍',
        last_name  => '张',
        username   => "",
      },
      result => qr/\AUnfortunately.*Using username 'XinyanZhang'/,
    },
);

for my $test (keys %tests) {
  my $username =
    WebWebXNG::Controller::RegistrationController::build_username(
      %{$tests{$test}->{args}}
    );
  like $username, $tests{$test}->{result},
    "right generated username for $test";
}

done_testing();
