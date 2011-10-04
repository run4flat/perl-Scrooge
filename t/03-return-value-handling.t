# A collection of tests to ensure that return values from _apply are
# correctly handled by apply. Note that similar tests must also be run for
# all the grouping regexes: OR, AND, SEQUENCE, etc.

# working here - make it clear what each test is testing

use strict;
use warnings;
use Test::More tests => 4;
use PDL::Regex;
use PDL;

#############
# NRE::Test #
#############
# A simple, lexically tweakable regex class that tracks the number of times
# _apply is called.
package NRE::Test;
our @ISA = qw(NRE);
my $apply_returns = -1;
my $apply_counts;
my ($min_size, $max_size) = (1, 10);
sub _prep {
	$apply_counts = 0;
	return $_[0]->SUPER::_prep($_[1]);
}
sub _apply { $apply_counts++; $apply_returns }
sub _min_size { $min_size }
sub _max_size { $max_size }

package main;

# ---( Build it: 1 )---

my $regex = NRE::Test->_new();
isa_ok($regex, 'NRE::Test');

# ---( Various sizes )---
my $data = sequence(3);
# For $data->nelem < $max_size, min_size = 1, and apply_returns = -1, we
# should have
#  apply_counts = N ( N + 1) / 2:
$regex->apply($data);
is($apply_counts, 6, 'Correctly ran sequential applications with right step -1');

$data = sequence(9);
$regex->apply($data);
is($apply_counts, 45, 'Ran sequential applications with right step of -1');

# Now try a step size of -2:
$apply_returns = -2;
# This should run (0,9) (0,7) (0,5) (0,3) (0,1) (1,9) (1,7)
# ... (1,3) (2,9) (2,7) ... (2,3) ...
# which comes to 5 + 2 * 4 + 2 * 3 + 2 * 2 + 2 * 1 = 25
$regex->apply($data);
is($apply_counts, 25, 'Ran sequential applications with right step of -2');

# Try a max size of 4.
$max_size = 4;
# In that case, we should have pairs (0,3), (0,1), (1,4), (1,2), ..., (6,9),
# (6,7), (7,9), (7,7), (8,9), and (9,9)
# which should come to 17 tests:
$regex->apply($data);
is($apply_counts, 17, 'Ran sequential applications with right step of -2');
