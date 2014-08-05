# A collection of tests to ensure that return values from _apply are
# correctly handled by apply. Note that similar tests should also be run for
# all the grouping patterns: re_or, re_and, re_seq, etc, although their 
# short-circuiting should also be taken into account.

use strict;
use warnings;
use Test::More tests => 2;
use Scrooge;
use PDL;

##############################
    package Scrooge::Test;
##############################

# A simple, lexically tweakable pattern that tracks the number of times
# apply is called. This is simpler yet more useful than Tracker for this
# problem. It does not record the call stack, but it does record the left
# and right search offsets (which would not be reocrded by Tracker).

our @ISA = qw(Scrooge);
my ($apply_returns, $data, $min_size, $max_size);
my @got;
sub prep {
	my ($self, $match_info) = @_;
	return 0 unless $self->SUPER::prep($match_info);
	$match_info->{min_size} = $min_size;
	$match_info->{max_size} = $max_size;
	@got = ();
	return 1;
}
sub apply {
	my ($self, $match_info) = @_;
	push @got, [$match_info->{left}, $match_info->{right}];
	return $apply_returns;
}
my $pattern = Scrooge::Test->new();

package main;


##################
# build_expected #
##################

# Create the data structure that we expect:
sub build_expected {
	my @to_return;
	for (my $i = 0; $i <= @$data - $min_size; $i++) {
		my $max_j = $i + $max_size - 1;
		$max_j = @$data - 1 if @$data - 1 < $max_j;
		for (my $j = $max_j; $j >= $i + $min_size - 1; $j += $apply_returns) {
			push @to_return, [$i, $j];
		}
	}
	return \@to_return;
}


######################################
# Check that build_expected works: 3 #
######################################

subtest 'Test build_expected with known example' => sub {
	plan tests => 3;

	# First a test that I can calculate by hand:
	($min_size, $max_size, $apply_returns, my $N_elem) = (1, 10, -1, 10);
	$data = [1 .. $N_elem];
	$pattern->match($data);
	is(scalar(@got), 55, 'Known example works with pattern');
	my $to_compare = build_expected();
	is(scalar(@$to_compare), 55, 'Known example works with build_expected');

	is_deeply(\@got, $to_compare, 'pattern and expected lists agree');
};

################################################################
# Check output of build_expected against the pattern structure #
################################################################
# Try 20 random combinations of values:
subtest 'Randomized trials' => sub {
	plan tests => 40;
	
	for (1..20) {
		# Choose a max size between 0 and 20:
		$max_size = int rand 20;
		# Choose a min size between 0 and $max_size:
		$min_size = int rand $max_size;
		# Choose an apply_returns between -1 and -$max_size:
		$apply_returns = -1 - int rand ($max_size - 1);
		# Generate a dataset of length between 2 and 40:
		my $N_elem = 2 + int rand 38;
		$data = [1 .. $N_elem];
		# Run the pattern
		my $length = $pattern->match($data);
		is($length, undef, 'fails to match when negative value given that exceeds available length');
		# Compare to what we expect:
		is_deeply(\@got, build_expected(), "Correct for size range [$min_size:$max_size], $N_elem elements, apply returning $apply_returns");
	}
};
