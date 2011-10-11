# Make sure that SUB works as advertised.
use strict;
use warnings;
use Test::More tests => 8;
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

my $match_positive = SUB(sub {
	# Supplied args are the piddle, the left slice offset,
	# and the right slice offset:
	my ($piddle, $left, $right) = @_;
	
	# Ensure that the first element is positive:
	return 0 unless all $piddle->slice($left) > 0;
	
	my $sub_piddle = $piddle->slice("$left:$right");
	# See if there are any negative values at all:
	if (any $sub_piddle <= 0) {
		# Get the list of the first coordinates of the switches:
		my ($switches) = whichND($sub_piddle < 0);
		# Find the first zero crossing:
		my $switch_offset = $switches->min;
		# The offset of the first zero crossing
		# corresponds with the number of matched values
		return $switch_offset;
	}
	
	# If no negative values, then the whole thing matches:
	return $right - $left + 1;
});


# ---( Explicit Constructor: 4 )---

# Check that the explicit constructor works:
$@ = '';
my $explicit = eval {PDL::Regex::Sub->new(quantifiers => [1,1], subref => $match_all_subref)};
is ($@, '', 'PDL::Regex::Sub::->new does not croak');
isa_ok($explicit, 'PDL::Regex::Sub');
my ($matched, $offset) = $explicit->apply($data);
is($matched, 1, 'Properly interprets single-element quantifier and runs subref');
is($offset, 0, 'Correctly identified first element as matching');

# ---( Simple Constructor, No Quantifiers: 4 )---

# Make sure the simple constructor works and uses quantifiers [1,1]
$@ = '';
my $simple = eval {SUB($match_all_subref)};
is($@, '', 'SUB does not croak');
isa_ok($simple, 'PDL::Regex::Sub');
($matched, $offset) = $simple->apply($data);
is($matched, 1, 'Simple constructor defaults to a single-element match');
is($offset, 0, 'Simple constructor correctly identified first element as matching');

# ---( Simple Constructor, quantifiers: N )---

# working here

# ---( Simple Constructor, named: N )---

# working here

# ---( Simple Constructor, named and quantified: N )---

# working here

# ---( Positivity Match: N )---

# working here
