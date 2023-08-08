use strict;
use warnings;
use Test::More;
use Test::Exception;

use File::LockDir;

my $locker;
throws_ok { $locker = File::LockDir->new(logger => 'foo') }
  qr/logger is not a code ref/, "non-coderef logger param dies";

throws_ok { $locker = File::LockDir->new(fatal => 'foo') }
  qr/fatal is not a code ref/, "non-coderef fatal param dies";

lives_ok { $locker = File::LockDir->new() } "basic call lives";
ok defined $locker, "Got a locker object";
is $locker->debug, 0, "default is no debugging";
is $locker->sleep, File::LockDir::DEFAULT_SLEEP_TIME, "defaulted sleep interval";

my @l;
lives_ok { $locker = File::LockDir->new(logger => sub { push @l, join " ", @_ })}
  "can add a custom logger";
$locker->note("test", "the", "method");
is_deeply ["test the method"], \@l, "custom logger works";

my @f;
lives_ok { $locker = File::LockDir->new(fatal => sub { push @f, (join " ", @_); die "failed with '$f[-1]'" }) }
  "can add a custom fatal";
throws_ok { $locker-> fatal("this", "dies") }
  qr/failed with 'this dies'/, "got the right failure";
is_deeply ["this dies"], \@f, "side effect works too";

done_testing;
