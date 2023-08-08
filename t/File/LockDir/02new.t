use strict;
use Test2::V0;

use File::LockDir;

my $locker;
like(dies{ $locker = File::LockDir->new(logger => 'foo') },
  qr/logger is not a code ref/, "non-coderef logger param dies");

like(dies { $locker = File::LockDir->new(fatal => 'foo') },
  qr/fatal is not a code ref/, "non-coderef fatal param dies");

ok(lives { $locker = File::LockDir->new() }, "basic call lives");
ok defined $locker, "Got a locker object";
is $locker->debug, 0, "default is no debugging";
is $locker->sleep, File::LockDir::DEFAULT_SLEEP_TIME, "defaulted sleep interval";
is(warnings { $locker->note("this warns") }, ["this warns\n"], "default warn callback works");
like(dies { $locker->fatal("woops") }, qr/woops/, "default fatal callback works");

my @l;
ok(lives { $locker = File::LockDir->new(logger => sub { push @l, join " ", @_ })},
  "can add a custom logger");
$locker->note("test", "the", "method");
is(["test the method"], \@l, "custom logger works");

my @f;
ok(lives { $locker = File::LockDir->new(fatal => sub { push @f, (join " ", @_); die "failed with '$f[-1]'" }) },
  "can add a custom fatal");
like(dies { $locker-> fatal("this", "dies") },
  qr/failed with 'this dies'/, "got the right failure");
is(["this dies"], \@f, "side effect works too");

done_testing;
