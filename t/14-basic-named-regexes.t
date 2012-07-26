# This tests the naming/capturing of regexes

use strict;
use warnings;
use Test::More tests => 10;
use Scrooge;
use PDL;

#############
# Scrooge::Test #
#############

# A simple base class for testing that always matches $N_to_match with
# offset $offset

package Scrooge::Test;
our @ISA = qw(Scrooge);
my ($N_to_match, $test_offset) = (10, 5);
sub min_size { $N_to_match }
sub max_size { $N_to_match }
sub _apply {
	my (undef, $left, $right) = @_;
	return 0 if $left < $test_offset;
	return $N_to_match if $right - $left + 1 == $N_to_match;
	return 0;
}

package main;

############################################
# Test the basic operation of Scrooge::Test, 3 #
############################################

my $test_regex = Scrooge::Test->new;
my $data = sequence(15);

my ($matched, $offset) = $test_regex->apply($data);
is($matched, $N_to_match, 'Scrooge::Test gives correct match');
is($offset, $test_offset, 'Scrooge::Test gives correct offset');
$test_offset++;
$matched = $test_regex->apply($data);
is($matched, undef, 'L = 10, Off = 6 fails for N = 15');

#########################
# Test a named regex, 5 #
#########################

my $regex = Scrooge::Test->new(name => 'test');
$test_offset = 2;
if ($regex->apply($data)) {
	pass('regex matched where it should have matched');
	if (my $details = $regex->get_details_for('test')) {
		pass('Retrieval of details for successfully matched named regex returns true in boolean context');
		is($details->{left}, $test_offset, 'Left should match offset');
		is($details->{right}, $details->{left} + $N_to_match - 1
			, 'Right should agree with left and N_to_match');
	}
	else {
		fail('Did not get the details for the named regex');
		fail('Cannot test left offset for accuracy');
		fail('Cannot test right offset for accuracy');
	}
}
else {
	fail('Regex did not match where it should have!');
	fail('Cannot test retrieval of named values');
	fail('Cannot test offset');
	fail('Cannot test match length');
}

# Make sure non-existent names fail:
$@ = '';
eval{$regex->get_details_for('foobar')};
isnt($@, '', 'Requesting an offset for a nonexistent name croaks');

#############################################################
# Test failed application after a successful application, 2 #
#############################################################

# Set the offset to a large value so that the match will fail. $data contains
# 15 elements and we want to match exactly 10 of them, starting at the 12th
# element:
$test_offset = 12;
if ($regex->apply($data)) {
	fail('Regex was not supposed to match here');
	fail('Cannot test retrieval after pass-then-fail if it does not fail');
}
else {
	pass('Regex failed where it was *supposed* to fail');
	my $details = $regex->get_details_for('test');
	is ($details, undef, 'Failed regex returns undef, even after a previous apply that passed');
}
