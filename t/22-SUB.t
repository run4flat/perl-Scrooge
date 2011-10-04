# Make sure that SUB works as advertised.
use strict;
use warnings;
use Test::More tests => 6;
use PDL::Regex;
use PDL;

my $data = sequence(20);

##################################
# Basic subroutines for matching #
##################################

my $match_all_subref = sub {
	my (undef, $left, $right) = @_;
	# Match all values:
	return $right - $left + 1;
};
my $match_positive = sub {
	my ($piddle, $left, $right) = @_;
	
	# A simple check for positivity.
	return ($right - $left + 1)
		if all $piddle->slice("$left:$right") > 0;
};


# ---( Explicit Constructor: 3 )---

# Check that the explicit constructor works:
my $explicit = eval {NRE::SUB->_new(quantifiers => [1,1], subref => $match_all_subref)};
isa_ok($explicit, 'NRE::Sub');
($matched, $offset) = $explicit->apply($data);
is($matched, $expected_match, 'Properly interprets single-element quantifier');
is($offset, $expected_offset, 'Correctly identified first element as matching');

# ---( Simple Constructor, No Quantifiers: 3 )---

# Make sure the simple constructor works and uses quantifiers [1,1]
my $simple = eval {NRE::SUB($match_all_subref)};
isa_ok($simple, 'NRE::Sub');
($matched, $offset) = $simple->apply($data);
is($matched, $expected_match, 'Simple constructor defaults to a single-element match');
is($offset, $expected_offset, 'Simple constructor correctly identified first element as matching');

# ---( Simple Constructor, quantifiers: N )---

# working here

# ---( Simple Constructor, named: N )---

# working here

# ---( Simple Constructor, named and quantified: N )---

# working here

# ---( Positivity Match: N )---

# working here
