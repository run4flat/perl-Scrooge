# Tests the functionality of Scrooge::Array::Sub.
use strict;
use warnings;
use Test::More tests => 2;
use Scrooge::Array;

###################
# Non-array input #
###################

my $match_all_subref = sub {
	my ($match_info) = @_;
	# Match all values:
	return $match_info->{length};
};

subtest 'Array vs Non-array input, full constructor' => sub {
	my $pattern = Scrooge::Array::Sub->new(
		subref => $match_all_subref,
		quantifiers => [1, '100%'],
	);
	my $data = { a => 1, b => 2, c => 3};
	ok(!$pattern->match($data), "Silently fails on hash input");
	ok(!$pattern->match('data'), "Silently fails on string input");
	$data = [ 1, 2, 3];
	is(scalar($pattern->match($data)), 3, "Correctly works on array input");
};

subtest 'Array vs Non-array input, short-name constructor' => sub {
	my $pattern = scr::arr::sub $match_all_subref;
	my $data = { a => 1, b => 2, c => 3};
	ok(!$pattern->match($data), "Silently fails on hash input");
	ok(!$pattern->match('data'), "Silently fails on string input");
	$data = [ 1, 2, 3];
	# Remember: default quantifier is [1, 1]
	is(scalar($pattern->match($data)), 1, "Correctly works on array input");
};

# All other functionality is inherited from Scrooge::Sub, and so is
# covered in test 22.
