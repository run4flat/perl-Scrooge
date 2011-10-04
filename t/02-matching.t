# A collection of tests to ensure that matching works as advertised:

use strict;
use warnings;
use Test::More tests => 18;
use PDL::Regex;
use PDL;

#############################################################
#      Guaranteed single- and multi-valued matches - 11     #
#############################################################

package NRE::Test::SingleMatch;
our @ISA = qw(NRE);
my $N_to_match = 1;
sub _apply { $N_to_match }     # Always match specified number of elements
sub _min_size { $N_to_match }  # Say we match exactly the specified
sub _max_size { $N_to_match }  #     number of elements

package main;

# ---( N = 1 )---

my $single_value_regex = eval {NRE::Test::SingleMatch->_new};
# Make sure the object was properly blessed:
isa_ok($single_value_regex, 'NRE::Test::SingleMatch');
# Generate some data and run the regex:
my $data = sequence(10);
my ($matched, $offset) = $single_value_regex->apply($data);
# See how it went:
is($matched, $N_to_match, 'Properly matches simple regex with fixed length');
is($offset, 0, 'Computes proper offset for super-simple regex');

# ---( N = 15 )---

$N_to_match = 15;

# This should fail because the data is only 10 elements long:
($matched, $offset) = $single_value_regex->apply($data);
is($matched, undef, 'Match should fail, data is too short');
is($offset, undef, 'No offset, data is too short');

# Make some longer data that should pass:
$data = sequence(20);
($matched, $offset) = $single_value_regex->apply($data);
is($matched, 15, 'Match should identify first 15 elements');
is($offset, 0, 'Offset should be zero');

# corner case: exactly 15 elements should still work
$data = sequence(15);
($matched, $offset) = $single_value_regex->apply($data);
is($matched, 15, 'Match should identify first 15 elements');
is($offset, 0, 'Offset should be zero');

# corner case: exactly 14 elements should fail
$data = sequence(14);
($matched, $offset) = $single_value_regex->apply($data);
is($matched, undef, 'Match should fail on 14 elements');
is($offset, undef, 'Offset should be undefined on failed match');

#############################################################
#                      Offset match - 7                     #
#############################################################

package NRE::Test::Offset;
our @ISA = qw(NRE);
# Track the number of times _apply is called
my $N_offset_tries = 0;
# Match a fixed length, but don't match at the first N_to_fail positions:
my $N_to_fail = 1;
sub _apply {
	$N_offset_tries++;
	# Return failed match when $left = 0
	return 0 if $_[1] < $N_to_fail;
	return $N_to_match;
}
sub _min_size { $N_to_match }  # Say we match exactly
sub _max_size { $N_to_match }  # N_to_match elements

package main;
my $offset_regex = eval {NRE::Test::Offset->_new};
isa_ok($offset_regex, 'NRE::Test::Offset');

# ---( N_to_match = 1 )---

$N_to_match = 1;
($matched, $offset) = $offset_regex->apply($data);
is($matched, $N_to_match, 'Match should match the specified number');
is($offset, $N_to_fail, 'Offset should agree with the number of failures');
is($N_offset_tries, $N_to_fail + 1, 'Should succeed on N + 1th attempt');

# ---( N_to_match = 10, N_to_fail = 4 )---

$N_offset_tries = 0;
$N_to_match = 10;
$N_to_fail = 4;
($matched, $offset) = $offset_regex->apply($data);
is($matched, $N_to_match, 'Match should match the specified number');
is($offset, $N_to_fail, 'Offset should agree with the number of failures');
is($N_offset_tries, $N_to_fail + 1, 'Should succeed on N + 1th attempt');



__END__

working here - put these in their own tests:

##############################################################
#                        NRE::ANY - 6                        #
##############################################################
# Build a regex that is nearly as simple as can be:
diag('== Testing NRE::ANY ==');
my $basic_any_re = eval {NRE::Any->_new(quantifiers => [1,1])};
isa_ok($basic_any_re, 'NRE::Any');
($matched, $offset) = $basic_any_re->apply($data);
is($matched, $expected_match, 'Properly interprets single-element quantifier');
is($offset, $expected_offset, 'Correctly identified first element as matching');

# Make sure the simple constructor works the same way:
my $any_re = eval {NRE::ANY()};
isa_ok($any_re, 'NRE::Any');
($matched, $offset) = $any_re->apply($data);
is($matched, $expected_match, 'Simple constructor defaults to a single-element match');
is($offset, $expected_offset, 'Simple constructor correctly identified first element as matching');

##############################################################
#                        NRE::AND - 2                        #
##############################################################
# Build an AND regex that includes two ANY regexes. They are identical, so
# they should always match.
diag('== Testing NRE::AND ==');
my $and_re = NRE::AND( NRE::ANY, NRE::ANY );
($matched, $offset) = $any_re->apply($data);
is($matched, 1, 'Properly identified that two ANY matches agree at their default lengths');
is($offset, 0, 'Correctly identified first element as matching');

##############################################################
#                        NRE::SUB - 4                        #
##############################################################
# Build a very simple regex:
my $positive_re = NRE::SUB(sub {
	# Supplied args are the piddle, the left slice offset,
	# and the right slice offset:
	my ($piddle, $left, $right) = @_;
	
	# A simple check for positivity. Notice that
	# I return the difference of the offsets PLUS 1,
	# because that's the number of elements this regex
	# consumes.
	return ($right - $left + 1)
		if all $piddle->slice("$left:$right") > 0;
});

$data = ones(10);
($matched, $offset) = $positive_re->apply($data);

diag('== Testing NRE::SUB with a regex that matches positive values ==');
is($matched, 1, 'NRE::SUB defaults to single-element match');
is($offset, 0, 'NRE::SUB Correctly identified first element as matching');

$data = sequence(10);
($matched, $offset) = $positive_re->apply($data);
is($offset, 1, 'Correctly identifies second element as first match');
is($matched, 1, 'Returns single element even when first match is not zero');
