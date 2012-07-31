use strict;
use warnings;
use Test::More tests => 10;
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
# local_min Tests: 0 #
######################

my $data = pdl(1,1,1,0,1,1,1);
$regex = eval{re_local_min};
my $match = $regex->apply($data);
isnt($match, undef, 'regex matched data');

