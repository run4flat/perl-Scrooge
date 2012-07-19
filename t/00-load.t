# A simple test to ensure that the module loads:

use strict;
use warnings;
use Test::More tests => 3;

use_ok('Regex::Engine');
use_ok('Regex::Engine::Range');

# make sure that new croaks if called with a bad number of arguments
$@ = '';
eval {Regex::Engine->new('only one argument')};
ok($@, 'Croaks on bad invocation of new');
