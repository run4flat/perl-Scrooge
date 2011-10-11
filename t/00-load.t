# A simple test to ensure that the module loads:

use strict;
use warnings;
use Test::More tests => 2;

use_ok('PDL::Regex');

# make sure that new croaks if called with a bad number of arguments
$@ = '';
eval {PDL::Regex->new('only one argument')};
ok($@, 'Croaks on bad invocation of new');
