# A collection of tests to ensure that return values from _apply are
# correctly handled by apply. Note that similar tests should also be run for
# all the grouping regexes: OR, AND, SEQUENCE, etc, although their 
# short-circuiting should also be taken into account.

use strict;
use warnings;
use Test::More tests => 23;
use PDL::Regex;
use PDL;

#############
# NRE::Test #
#############
# A simple, lexically tweakable regex class that tracks the number of times
# _apply is called.
package NRE::Test;
our @ISA = qw(NRE);
my ($apply_returns, $data, $min_size, $max_size);
my @got;
sub _prep {
	@got = ();
	return $_[0]->SUPER::_prep($_[1]);
}
sub _apply {
	my $self = shift;
	push @got, [@_];
	return $apply_returns;
}
sub _min_size { $min_size }
sub _max_size { $max_size }

package main;

##################
# build_expected #
##################

# Create the data structure that we expect:
sub build_expected {
	my @to_return;
	for (my $i = 0; $i <= $data->nelem - $min_size; $i++) {
		my $max_j = $i + $max_size - 1;
		$max_j = $data->nelem - 1 if $data->nelem - 1 < $max_j;
		for (my $j = $max_j; $j >= $i + $min_size - 1; $j += $apply_returns) {
			push @to_return, [$i, $j];
		}
	}
	return \@to_return;
}

my $regex = NRE::Test->_new();

######################################
# Check that build_expected works: 3 #
######################################

# First a test that I can calculate by hand:
($min_size, $max_size, $apply_returns, my $N_elem) = (1, 10, -1, 10);
$data = sequence($N_elem);
$regex->apply($data);
ok(@got == 55, 'Known example works with regex')
	or diag('@got contains ' . scalar(@got) . ' elements');
my $to_compare = build_expected();
ok(@$to_compare == 55, 'Known example works with build_expected')
	or diag('$to_compare contains ' . scalar(@$to_compare) . ' elements, not 55');

is_deeply(\@got, $to_compare, 'Regex and expected lists agree');

##############################################################
# Check output of build_expected against the regex structure #
##############################################################
# Try 20 random combinations of values:
for (1..20) {
	# Choose a max size between 0 and 20:
	$max_size = int rand 20;
	# Choose a min size between 0 and $max_size:
	$min_size = int rand $max_size;
	# Choose an apply_returns between -1 and -$max_size:
	$apply_returns = -1 - int rand ($max_size - 1);
	# Generate a dataset of length between 2 and 40:
	$N_elem = 2 + int rand 38;
	$data = sequence($N_elem);
	# Run the regex
	$regex->apply($data);
	# Compare to what we expect:
	is_deeply(\@got, build_expected(), "Correct for [$min_size:$max_size], $N_elem elements, _apply returning $apply_returns");
}
