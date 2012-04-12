# This tests the naming/capturing of regexes

use strict;
use warnings;
use Test::More tests => 8;
use PDL::Regex;
use PDL;

#############
# PDL::Regex::Test #
#############

# A simple base class for testing that always matches $N_to_match with
# offset $offset

package PDL::Regex::Test;
our @ISA = qw(PDL::Regex);
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
# Test the basic operation of PDL::Regex::Test, 3 #
############################################

my $test_regex = PDL::Regex::Test->new;
my $data = sequence(15);

my ($matched, $offset) = $test_regex->apply($data);
is($matched, $N_to_match, 'PDL::Regex::Test gives correct match');
is($offset, $test_offset, 'PDL::Regex::Test gives correct offset');
$test_offset++;
$matched = $test_regex->apply($data);
is($matched, undef, 'L = 10, Off = 6 fails for N = 15');

#########################
# Test a named regex, 5 #
#########################

my $regex = PDL::Regex::Test->new(name => 'test');
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
eval{$regex->get_offsets_for('foobar')};
isnt($@, '', 'Requesting an offset for a nonexistent name croaks');
