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
    blank => {
      fails => 1,
      message => qr/\AFirst name, last name, password, password confirmation, email, and email confirmation\z/,
      fields => {},
    },
    correct => {
      fails => 0,
      fields => {
        email  => 'example@example.com',
        verify => 'example@example.com',
        password => 'dummy',
        confirm_pwd => 'dummy',
        first_name => 'Test',
        last_name => 'User',
      },
    },
    "missing first name" => {
      fails => 1,
      fields => {
        email  => 'example@example.com',
        verify => 'example@example.com',
        password => 'dummy',
        confirm_pwd => 'dummy',
        last_name => 'User',
      },
      message => qr/\AFirst name\z/,
    },
    "missing last name" => {
      fails => 1,
      fields => {
        email  => 'example@example.com',
        verify => 'example@example.com',
        password => 'dummy',
        confirm_pwd => 'dummy',
        first_name => 'Test',
      },
      message => qr/\ALast name\z/,
    },
    "missing password confirmation" => {
      fails => 1,
      fields => {
        email  => 'example@example.com',
        verify => 'example@example.com',
        password => 'dummy',
        first_name => 'Test',
        last_name => 'User',
      },
      message => qr/\APassword confirmation\z/,
    },
    "missing password" => {
      fails => 1,
      fields => {
        email  => 'example@example.com',
        verify => 'example@example.com',
        confirm_pwd => 'dummy',
        first_name => 'Test',
        last_name => 'User',
      },
      message => qr/\APassword\z/,
    },
    "missing verify" => {
      fails => 1,
      fields => {
        email  => 'example@example.com',
        password => 'dummy',
        confirm_pwd => 'dummy',
        first_name => 'Test',
        last_name => 'User',
      },
      message => qr/Email confirmation\z/,
    },
    "missing email" => {
      fails => 1,
      fields => {
        verify => 'example@example.com',
        password => 'dummy',
        confirm_pwd => 'dummy',
        first_name => 'Test',
        last_name => 'User',
      },
      message => qr/\AEmail\z/,
    },
    "two missing" => {
      fails => 1,
      fields => {
        verify => 'example@example.com',
        password => 'dummy',
        confirm_pwd => 'dummy',
        last_name => 'User',
      },
      message => qr/\AFirst name and email\z/,

    }
);

for my $test (keys %tests) {
  my ($message) =
    WebWebXNG::Controller::RegistrationController::fields_are_missing(
      %{$tests{$test}->{fields}}
    );
  if ($tests{$test}->{fails}) {
    like $message, $tests{$test}->{message}, "message matches for $test"
      or diag $message;
  } else {
    ok !$message, "no message as expected for $test"
      or diag $message if $message;
  }

}

done_testing();
