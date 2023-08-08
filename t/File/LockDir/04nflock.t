use strict;
use Test2::V0;
use Test2::AsyncSubtest;

use File::LockDir;
use File::Temp qw(tempdir);
use File::Spec;
use Carp qw(croak);

my $locker;
my @l;
my @f;


sub new_locker {
  return File::LockDir->new(
    logger => sub { push @l, join " ", @_ },
    fatal  => sub { my $z = join(" ", @_)||"missing error message"; push @f, $z; croak($z) },
    @_,
  );
}

my $path;

# 0. Dies if no directory is given.
@l = ();
@f = ();
$locker = new_locker();
like(dies{ $locker->nflock() },
  qr/no pathname supplied/, "dies if we don't have a target dir");

# 1. If file is already locked, return 1 and the cached owner.
$locker = new_locker();
my $dir = tempdir(CLEANUP => 1);
$path = File::Spec->catfile($dir, 'foo');
@l = ();
@f = ();
$locker->locked_files( { $path => 'dummy owner'} );
my($status, $owner) = $locker->nflock($path);
is($status, 1, "file is locked (already)");
is($owner, "dummy owner", "verifying we get the cached value");
is(\@l, ["$path already locked"], "correct message logged");

# 2. If we can't write to the directory, die.
$dir = undef;  # trigger cleanup
$dir = tempdir(CLEANUP => 1);
$path = File::Spec->catfile($dir, 'foo');
@l = ();
@f = ();
chmod 000, $dir;
# Limit the number of tries, because we know we can't
# succeed. Set the wait to the minimum.
$locker = new_locker(tries => 1, sleep => 1);
like( dies { ($status, $owner) = $locker->nflock($path) },
      qr/can't obtain lock/,
      "fails when we can't make the lock"
    );
chmod 777, $dir; # Put perms back so cleanup works

# 3. Happy path: lock doesn't exist, create it, return 1.
$dir = undef;  # trigger cleanup
$dir = tempdir(CLEANUP => 1);
$path = File::Spec->catfile($dir, 'foo');
@l = ();
@f = ();
$locker = new_locker(tries => 1, sleep => 1);
($status, $owner) = $locker->nflock($path, 0, "TestUser");
is($status, 1, "file is now locked");
like($owner, qr/TestUser from .*? since /, "locked by TestUser");

# 4. Unhappy path: lock exists, still there after tries elapse. Return 0.
### Keep the old directory with the lock in it.
### Use the same path.
#$dir = undef;  # trigger cleanup
#$dir = tempdir(CLEANUP => 1);
#$path = File::Spec->catfile($dir, 'foo');
@l = ();
@f = ();
$locker = new_locker(tries => 1, sleep => 1);
($status, $owner) = $locker->nflock($path, 0, "RealUser");
is($status, 0, "file couldn't be locked");
like($owner, qr/TestUser/, "already locked by TestUser");

# 5. Happy-ish path: lock exists, but goes away before tries elapse. Lock and return 1.
$dir = undef;  # trigger cleanup
$dir = tempdir(CLEANUP => 1);
$path = File::Spec->catfile($dir, 'foo');
@l = ();
@f = ();
$locker = new_locker(tries => 10, sleep => 1);

# Fork: the child immediately unlocks the file and exits;
#       the parent spins waiting for the lock, gets it,
#       and waits for the child to exit.
my $ast = Test2::AsyncSubtest->new(name => 'unlocker');
$ast->run_fork(
  sub {
  # Child: unlock the path and exit.
  my $locker2 = new_locker();
  $locker2->nfunlock($path);
  pass "Async unlock succeeded";
});
# Parent: try to lock.
($status, $owner) = $locker->nflock($path, 0, "RealUser");

is($status, 1, "lock successfully switched");
like($owner, qr/RealUser/, "now locked by RealUser");

$ast->finish;

# 6. Verify debug works. Currently locked by RealUser, so
#    try to lock with a different user with debug on. Should
#    get debug lines while the lock is held, and no debug
#    whe it is not.
$dir = undef;  # trigger cleanup
$dir = tempdir(CLEANUP => 1);
$path = File::Spec->catfile($dir, 'foo');
@l = ();
@f = ();
$locker = new_locker(tries => 20, sleep => 1, debug => 1);

# Fork: the child immediately unlocks the file and exits;
#       the parent spins waiting for the lock, gets it,
#       and waits for the child to exit.
$ast = Test2::AsyncSubtest->new(name => 'unlocker with pause');
$ast->run_fork(
  sub {
  # Child: unlock the path and exit.
  sleep 1;
  my $locker2 = new_locker();
  $locker2->nfunlock($path);
  pass "Async unlock succeeded";
});
# Parent: try to lock.
($status, $owner) = $locker->nflock($path, 0, "RealUser");

is($status, 1, "lock successfully switched");
like($owner, qr/RealUser/, "now locked by RealUser");

$ast->finish;

like $l[0], qr/attempt to obtain lock/, "debug: tries start";
like $l[-1], qr/successful/, "debug: success recorded";

done_testing;
