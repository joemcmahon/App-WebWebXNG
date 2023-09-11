use Mojo::Base -strict;

use Test2::V0;
use Test::Mojo;
use WebWebXNG;
use File::Temp qw(tempfile);

my $app;

# Should die if the SQLite file isn't configured.
like dies { $app = WebWebXNG->new },
  qr/Config failed: No database path supplied/,
  "dies if SQLite path isn't set";

my(undef, $filename) = tempfile;

$ENV{SQLITE_FILE} = $filename;
ok lives { $app = WebWebXNG->new },
  "lives if database path is there";

ok $app->sqlite->db, "database is initialized";

done_testing();
