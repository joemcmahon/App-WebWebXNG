use strict;
use Test2::V0;

use File::LockDir;

my $locker;
my @l;
my @f;

ok(lives { $locker = File::LockDir->new(
  logger => sub { push @l, join " ", @_ },
  fatal => sub { push @f, (join " ", @_); die "failed with '$f[-1]'"  },
  )},
  "set up custom logger and fatal");

is($locker->locked_files, {}, 'starts with empty locked file list');

$locker->locked_files( { foo => '/path/to/foo' } );
is($locker->locked_files, {foo => '/path/to/foo'}, 'set custom file list');

is $locker->locked_files('foo'), '/path/to/foo', 'getter works';

$locker->locked_files('bar', '/path/to/bar');
is $locker->locked_files, {foo => '/path/to/foo', bar => '/path/to/bar'}, 'setter changed hash';
is $locker->locked_files('bar'), '/path/to/bar', 'confirm we can get new entry';

$locker->locked_files('foo' => '/path/to/baz');
is $locker->locked_files('foo'), '/path/to/baz', 'update wotks';

done_testing;
