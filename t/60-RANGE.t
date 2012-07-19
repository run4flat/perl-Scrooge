use strict;
use warnings;
use Test::More tests => 15;
use PDL;
use Regex::Engine::Range;

#################################
# Range string parsing tests: 8 #
#################################

# Make a local function alias for parse_range_strings
*prs = \&Regex::Engine::Range::parse_range_strings;

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
isa_ok($two_to_five, 'Regex::Engine::Intersect');
is($two_to_five->{name}, 'test regex', 'Constructor correctly interprets name');

########################
# Basic Match Tests: 4 #
########################
$data = pdl(-3, 4, 5, 9);
my ($matched, $offset) = $two_to_five->apply($data);
isnt($matched, undef, 'two_to_five matched against (-3, 4, 5, 9)');
is($matched, 1, 'default quantifier is a single match');
is($offset, 1, 'identifies the first matching element');

$data = pdl(7, 8, 9);
($matched, $offset) = $two_to_five->apply($data);
is($matched, undef, 'two_to_five could not match piddle (7, 8, 9)');

__END__
$data = sin(sequence(100)/10);
$data->slice('37') .= 100;

$regex = Regex::Engine::Intersect::re_intersect(above => 2, below => 1000);
($matched, $offset) = $regex->apply($data);
print "not " if not defined $offset or $offset != 37;
print "ok - offset finds crazy value\n";

$regex = Regex::Engine::Intersect::re_intersect(above => 'avg + 2@', below => 1000);
($matched, $offset) = $regex->apply($data);
print "not " if not defined $offset or $offset != 37;
print "ok - offset finds crazy value\n";