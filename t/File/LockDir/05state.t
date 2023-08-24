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
my $dir = tempdir(CLEANUP => 1);
$path = File::Spec->catfile($dir, 'foo');
@l = ();
@f = ();
$locker = new_locker(tries => 1, sleep => 1);
my ($status, $owner) = $locker->nflock($path, 0, "TestUser");
is($status, 1, "file is now locked");
like($owner, qr/TestUser from .*? since /, "locked by TestUser");

my ($state, $locking_user) = $locker->nlock_state($path);
is $state, 1, "it's locked";
like $locking_user, qr/^TestUser/, "right person";

$locker->nfunlock($path);

($state, $locking_user) = $locker->nlock_state($path);
is $state, undef, "it's unlocked";
is $locking_user, undef, "held by no one";


done_testing;
