use strict;
use warnings;
use Test::More;
use Test::Exception;

use File::Temp qw(tempdir);

use PageArchive::RCS;

my $archive;

dies_ok { $archive = PageArchive::RCS->new() } "dies with no directory provided";

done_testing;
