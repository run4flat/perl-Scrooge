use strict;
use warnings;
use Test::More tests => 21;
use PDL;
use Scrooge::PDL;


########################
# Constructor tests: 9 #
########################

my $regex = eval{re_local_extremum};
is($@,'', 'Didnt croak');
isa_ok($regex, 'Scrooge::PDL::Local_Extremum');
is($regex->{type}, 'both', 'Returns correct type');

$regex = eval{re_local_min};
is($@,'', 'Didnt croak');
isa_ok($regex, 'Scrooge::PDL::Local_Extremum');
is($regex->{type},'min', 'Returns correct type');

$regex = eval{re_local_max};
is($@,'', 'didnt croak');
isa_ok($regex, 'Scrooge::PDL::Local_Extremum');
is($regex->{type},'max', 'Returns correct type');

######################
# local_min Tests: 4 #
######################

my $data = pdl(1,1,1,0,1,1,1);
$regex = eval{re_local_min};
my ($match, $off) = $regex->apply($data);
is($match, 1, 'regex matched data');
is($off, 3, 'Correctly locates local min');

$data = sin(sequence(7));
($match, $off) = $regex->apply($data);
is($match, 1, 'regex matched data');
is($off, 5, 'correctly locates local min');

######################
# local_max Tests: 4 #
######################

$data = pdl(0,0,0,1,0,0,0);
$regex = eval{re_local_max};
($match, $off) = $regex->apply($data);
is($match, 1, 'regex matched data');
is($off, 3, 'correctly locates local max');

$data = sin(sequence(7));
($match, $off) = $regex->apply($data);
is($match, 1, 'regex matched data');
is($off, 2, 'correctly locates local max');

###########################
# local_extremum Tests: 4 #
###########################

$data = pdl(1,1,0,1,1,2,1,1);
$regex = eval{re_local_extremum};
($match, $off) = $regex->apply($data);
is($match, 1, 'regex matched data');
is($off, 2, 'correctly locates local min');

$data = pdl(1,1,2,1,1,0,1,1);
($match, $off) = $regex->apply($data);
is($match, 1, 'regex matched data');
is($off, 2, 'correctly locates local max');
