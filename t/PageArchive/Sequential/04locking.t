use strict;
use warnings;
use Test2::V0;

use File::Temp qw(tempdir);

use PageArchive::Sequential;

sub mk_archive {
  my $dir = tempdir(CLEANUP => 1);
  ($dir, PageArchive::Sequential->new($dir));
}

my ($dir, $archive) = mk_archive();
my $contents = {dummy => "contents"};
my $name = "SamplePage";

# Add two versions of the page.
ok $archive->put($name, $contents), "put call succeeded";
ok $archive->put($name, $contents, 2), "explicit version succeeds";

# Version 1 should not be locked.
my($is_locked, $owner) = $archive->is_unlocked($name, 1);
ok !$is_locked, "version 1 unlocked";

# Lock version 1. Verify version 2 is also locked.
ok $archive->lock($name, 1, "TestUser"), "lock version 1 only";
($is_locked, $owner) = $archive->is_unlocked($name, 2);
ok $is_locked, "version 2 locked too";

# Verify version 1 is locked and by the right person.
($is_locked, $owner) = $archive->is_unlocked($name, 1);
ok $is_locked, "version 1 locked";
like $owner, qr/TestUser/, "right locker";

# Unlock version 1 and verify that worked.
ok $archive->unlock($name, 1), "unlock works for version 1";
($is_locked, $owner) = $archive->is_unlocked($name, 1);
ok !$is_locked, "version 1 now unlocked again";

# Verify that version 2 remains unlocked.
($is_locked, $owner) = $archive->is_unlocked($name, 2);
ok !$is_locked, "version 2 now unlocked";

done_testing;
