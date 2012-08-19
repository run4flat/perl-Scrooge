use strict;
use warnings;
use Test::More tests => 21;
use PDL;
use Scrooge::PDL;

########################
# Constructor tests: 9 #
########################

my $pattern = eval{re_local_extremum};
is($@,'', 're_local_extremum does not croak');
isa_ok($pattern, 'Scrooge::PDL::Local_Extremum');
is($pattern->{type}, 'both', 'Returns correct type');

$pattern = eval{re_local_min};
is($@,'', 're_local_min does not croak');
isa_ok($pattern, 'Scrooge::PDL::Local_Extremum');
is($pattern->{type},'min', 'Returns correct type');

$pattern = eval{re_local_max};
is($@,'', 're_local_max does not croak');
isa_ok($pattern, 'Scrooge::PDL::Local_Extremum');
is($pattern->{type},'max', 'Returns correct type');

######################
# local_min Tests: 4 #
######################

my $data = pdl(1,1,1,0,1,1,1);
$pattern = re_local_min;
my ($match, $off) = $pattern->apply($data);
is($match, 1, 'pattern matched data');
is($off, 3, 'Correctly locates local min');

$data = sin(sequence(7));
($match, $off) = $pattern->apply($data);
is($match, 1, 'pattern matched data');
is($off, 5, 'correctly locates local min');

######################
# local_max Tests: 4 #
######################

$data = pdl(0,0,0,1,0,0,0);
$pattern = re_local_max;
($match, $off) = $pattern->apply($data);
is($match, 1, 'pattern matched data');
is($off, 3, 'correctly locates local max');

$data = sin(sequence(7));
($match, $off) = $pattern->apply($data);
is($match, 1, 'pattern matched data');
is($off, 2, 'correctly locates local max');

###########################
# local_extremum Tests: 4 #
###########################

$data = pdl(1,1,0,1,1,2,1,1);
$pattern = re_local_extremum;
($match, $off) = $pattern->apply($data);
is($match, 1, 'pattern matched data');
is($off, 2, 'correctly locates local min');

$data = pdl(1,1,2,1,1,0,1,1);
($match, $off) = $pattern->apply($data);
is($match, 1, 'pattern matched data');
is($off, 2, 'correctly locates local max');
