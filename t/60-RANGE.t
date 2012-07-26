use strict;
use warnings;
use Test::More tests => 37;
use PDL;
use Scrooge::PDL;

#################################
# Range string parsing tests: 8 #
#################################

# Make a local function alias for parse_range_strings
*prs = \&Scrooge::Range::parse_range_strings;

my $data = sequence(11);
# three tests here:
for my $test_string ( qw(5  -5  5.5) ) {
	is(prs($data, $test_string), $test_string,
		"parse_range_strings correctly interprets literal number $test_string");
}

# These could stand to be expanded.
my ($avg, $stdev) = $data->stats;
is(prs($data, 'avg + 5'), $avg + 5, 'parse_range_strings correctly interprets avg + 5');
is(prs($data, '3@ - 2'), 3*$stdev - 2, 'parse_range_strings correctly interprets 3@ - 2');
is(prs($data, '20% + 1'), 3, 'parse_range_strings correctly interprets 20% + 1');
is(prs($data, 'min + 3'), 3, 'parse_range_strings correctly interprets min + 3');
is(prs($data, 'max - 2'), 8, 'parse_range_strings correctly interprets max - 2');

########################
# Constructor tests: 3 #
########################

my $two_to_five = eval{re_intersect(name => 'test regex', above => '2', below => '5')};
is($@, '', 'Basic constructor does not croak');
isa_ok($two_to_five, 'Scrooge::Intersect');
is($two_to_five->{name}, 'test regex', 'Constructor correctly interprets name');

#########################
# Basic Match Tests: 20 #
#########################
$data = pdl(-3, 4, 5, 9);
my ($matched, $offset) = $two_to_five->apply($data);
isnt($matched, undef, 'two_to_five matched against (-3, 4, 5, 9)');
is($matched, 1, 'default quantifier is a single match');
is($offset, 1, 'identifies the first matching element');

$data = pdl(7, 8, 9);
($matched, $offset) = $two_to_five->apply($data);
is($matched, undef, 'two_to_five could not match piddle (7, 8, 9)');

$data = sin(sequence(100)/10);
$data->slice('37') .= 100;

$two_to_five = eval{re_intersect(name=>'test regex',above => 2, below => 1000)};
($matched, $offset) = $two_to_five->apply($data);
isnt($matched, undef, 'two_to_five matched against piddle');
is($matched, 1, 'default quantifier is a single match');
is($offset, 37, 'identifies the first matching element');


$two_to_five = eval{re_intersect(name => 'test regex', above => 'avg + 2@', below => 1000)};
($matched, $offset) = $two_to_five->apply($data);
isnt($matched, undef, 'two_to_five matched piddle');
is($matched, 1, 'default quantifier is a single match');
is($offset, 37, 'identifies first matching element');

$two_to_five = eval{re_intersect(name => 'test regex', above => 2, below => 'avg + 10@')};
($matched, $offset) = $two_to_five->apply($data);
isnt($matched, undef, 'two_to_fve matched piddle');
is($matched, 1, 'default quantifier is a single match');
is($offset, 37, 'identifies first matching element');

$two_to_five = eval{re_intersect(name => 'test regex', above => 'avg - 3@', below => 'avg - 2@')};
($matched, $offset) = $two_to_five->apply($data);
is($matched, undef, 'two_to_five could not match piddle');

$two_to_five = eval{re_intersect(name => 'test regex', above => -1, below => 200)};
($matched, $offset) = $two_to_five->apply($data);
isnt($matched, undef, 'two_to_five matched piddle');
is($matched, 1, 'default quantifier is a single match');
is($offset, 0, 'identifies first matching element');

$data->slice('9') .= -10;

$two_to_five = eval{re_intersect(name => 'test regex', above => 'avg - 10@', below => 'avg - 1@')};
($matched, $offset) = $two_to_five->apply($data);
isnt($matched, undef, 'two_to_five matched piddle');
is($matched, 1, 'default quantifier is a single match');
is($offset, 9, 'identifies first matching element');

#############################
# Quantified Match Tests: 6 #
#############################

$data->slice('10') .= -11;
$data->slice('11') .= -12;

$two_to_five = eval{re_intersect(name => 'test regex', above => 'avg - 15@', below => 'avg - 1@', quantifiers => [1,3])};
($matched, $offset) = $two_to_five->apply($data);
isnt($matched, undef, 'two_to_five matched piddle');
is($matched, 3, 'matched a segment of lentgth 3');
is($offset, 9, 'identifies first matching value');


$data = sin(sequence(100)/10);
$two_to_five = re_intersect(name => 'test regex', above => -1, below => 1, quantifiers => [1,100]);
($matched, $offset) = $two_to_five->apply($data);
isnt($matched, undef, 'two_to_five matched piddle');
is($matched, 100, 'whole segment matched');
is($offset, 0, 'identifies first matching element');
