package WebWebXNG::Model;
use 5.38;

use Mojo::Base -base, -signatures;
use Mojo::SQLite;

use Carp ();

helper sqlite => sub {
  state $sql = Mojo::SQLite->new(
    $ENV{SQLITE_DB_PATH} || die "SQLITE_DB_PATH not set in environment")
};

