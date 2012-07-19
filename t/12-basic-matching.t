# A collection of tests to ensure that matching works as advertised:

use strict;
use warnings;
use Test::More tests => 39;
use Regex::Engine;
use PDL;

#######################
# Regex::Engine::Test #
#######################

# A simple base class for testing purposes. This makes it easy to adjust
# the number of elements to match by simply changing the lexical variable
# $N_to_match. It doesn't play well with the stash management, but I won't
# be exercising that in this set of tests.

package Regex::Engine::Test;
our @ISA = qw(Regex::Engine);
my $N_to_match = 1;
sub min_size { $N_to_match }
sub max_size { $N_to_match }

#############################################################
#      Guaranteed single- and multi-valued matches - 13     #
#############################################################

package Regex::Engine::Test::SingleMatch;
our @ISA = qw(Regex::Engine::Test);
sub _apply { $N_to_match }     # Always match specified number of elements

package main;

# ---( N = 1 )---

my $single_value_regex = eval {Regex::Engine::Test::SingleMatch->new};
# Make sure the object was properly blessed:
isa_ok($single_value_regex, 'Regex::Engine::Test::SingleMatch');
# Generate some data and run the regex:
my $data = sequence(10);
my ($matched, $offset) = $single_value_regex->apply($data);
# See how it went:
is($matched, $N_to_match, 'Properly matches simple regex with fixed length');
is($offset, 0, 'Computes proper offset for super-simple regex');

# Single-piddle matching
($matched, $offset) = $single_value_regex->apply(pdl(5));
is($matched, $N_to_match, 'Properly matches simple regex with fixed length on single-element piddle');
is($offset, 0, 'Computes proper offset for super-simple regex on single-element-piddle');


# ---( N = 15 )---

$N_to_match = 15;

# This should fail because the data is only 10 elements long but the
# regex wants to match 15 elements:
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

# Check that the proper offset is returned. This test class returns a
# failing value unless the position is far enough to the right. The
# exact position at which success should begin is this value:
my $first_good_offset = 1;
# I will also track the number of times that this regex is called:
my $N_offset_tries = 0;
# Finally, note that, as with the previous class, the number of elements
# to match is set by the lexical variable $N_to_match.

package Regex::Engine::Test::Offset;
our @ISA = qw(Regex::Engine::Test);
# This is the function that does all the work; see above notes:
sub _apply {
	$N_offset_tries++;
	# Return failed match until we are at the correct offset
	return 0 if $_[1] < $first_good_offset;
	return $N_to_match;
}

package main;
my $offset_regex = eval {Regex::Engine::Test::Offset->new};
isa_ok($offset_regex, 'Regex::Engine::Test::Offset');

# ---( N_to_match = 1 )---

$N_to_match = 1;
($matched, $offset) = $offset_regex->apply($data);
is($matched, $N_to_match, 'Match should match the specified number');
is($offset, $first_good_offset, 'Offset should agree with the number of failures');
is($N_offset_tries, $first_good_offset + 1, 'Should succeed on N + 1th attempt');

# ---( N_to_match = 10, first_good_offset = 4 )---

$N_offset_tries = 0;
$N_to_match = 10;
$first_good_offset = 4;
($matched, $offset) = $offset_regex->apply($data);
is($matched, $N_to_match, 'Match should match the specified number');
is($offset, $first_good_offset, 'Offset should agree with the number of failures');
is($N_offset_tries, $first_good_offset + 1, 'Should succeed on N + 1th attempt');


#############################################################
#                     Croaking match - 5                    #
#############################################################

# The regex engine is supposed to croak if the regex returns a match whose
# length exceeds the number of elements given to it to match. Let's test
# that behavior here:

package Regex::Engine::Test::Croak;
our @ISA = qw(Regex::Engine::Test);
my $croak_apply_returns = $N_to_match;
sub _apply { $croak_apply_returns };

package main;
# Create the new regex and make sure it's what we think it is:
my $croak_regex = eval {Regex::Engine::Test::Croak->new};
isa_ok($croak_regex, 'Regex::Engine::Test::Croak');

# ---( croak_apply_returns = N_to_match )---

# These tests may seem redundant, but they basically assure that the croak
# regex behaves normally under good conditions. That way, we can *trust*
# the results of the next test.

$@ = '';
($matched, $offset) = eval { $croak_regex->apply($data) };
is($@, '', 'Croak regex does not croak when _apply returns value within bounds');
is($matched, $N_to_match, 'Croak regex properly matched number of elements for good _apply');
is($offset, 0, 'Croak regex returned a zero offset for good _apply');

# ---( croak_apply_returns = N_to_match + 1 )---

$croak_apply_returns = $N_to_match + 1;
$@ = '';
eval { $croak_regex->apply($data) };
ok($@, 'Regex should croak when _apply returns too many elements');


############################################################
#               Context-dependent Returns - 7              #
############################################################

# A failing regex:
package Regex::Engine::Test::Fail;
my $ran_failed = 0;
our @ISA = qw(Regex::Engine);
sub min_size { 1 }
sub max_size { 1 }
sub _apply { $ran_failed++; 0 }

package main;
my $failing_regex = eval {Regex::Engine::Test::Fail->new};
isa_ok($failing_regex, 'Regex::Engine::Test::Fail');

# We have a failing regex, set $single_value_regex to succeed:
$N_to_match = 3;

# ---( No assignment conditional: 2 )---

if ($failing_regex->apply($data)) {
	fail('Failing regex in conditional should fail');
}
else {
	pass('Failing regex in conditional fails');
}
if ($single_value_regex->apply($data)) {
	pass('Succeeding regex in conditional succeeds');
}
else {
	fail('Succeeding regex in conditional should succeed');
}

# ---( Scalar assignment conditional: 2 )---
if ($matched = $failing_regex->apply($data)) {
	fail('Failing regex in scalar-assigning conditional should fail');
}
else {
	pass('Failing regex in scalar-assigning conditional fails');
}
if ($matched = $single_value_regex->apply($data)) {
	pass('Succeeding regex in scalar-assigning conditional succeeds');
}
else {
	fail('Succeeding regex in scalar-assigning conditional should succeed');
}

# ---( List assignment conditional: 2 )---
if (($matched, $offset) = $failing_regex->apply($data)) {
	fail('Failing regex in scalar-assigning conditional should fail');
}
else {
	pass('Failing regex in scalar-assigning conditional fails');
}
if (($matched, $offset) = $single_value_regex->apply($data)) {
	pass('Succeeding regex in scalar-assigning conditional succeeds');
}
else {
	fail('Succeeding regex in scalar-assigning conditional should succeed');
}

############################################################
#                 Zero-width Assertions - 6                #
############################################################

# This makes sure that zero-but-true returns true:
package Regex::Engine::Test::ZWA;
our @ISA = qw(Regex::Engine);
sub min_size { 0 }
sub max_size { 0 }
sub _apply { '0 but true' }

package main;
my $zwa_regex = eval {Regex::Engine::Test::ZWA->new};
isa_ok($zwa_regex, 'Regex::Engine::Test::ZWA');

my $success = $zwa_regex->apply($data) ? 1 : 0;
ok($success, 'Zero-width matches return boolean true in scalar context');

$success = ($zwa_regex->apply($data)) ? 1 : 0;
ok($success, 'Zero-width matches return boolean true in list context');

# The next if/else block is a single test:
if (($matched, $offset) = $zwa_regex->apply($data)) {
	pass('Successful zero-width matches with assignment return boolean true');
}
else {
	fail('Successful zero-width matches with assignment are supposed to return boolean true');
}
is($matched, 0, 'Zero-width assertion matched zero elements');
is($offset, 0, 'Zero-width assertion matched at zero offset');

###########################################################
#                 Unknown data lengths - 1                #
###########################################################

$N_to_match = 1;
my $matched = eval{ $single_value_regex->apply(5) };
isnt($@, '', "Can't apply regex to simple scalars");
