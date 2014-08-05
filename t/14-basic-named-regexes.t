# This tests the naming/capturing of patterns

use strict;
use warnings;

# Load the basics module:
my $module_name = 'Basics.pm';
if (-f $module_name) {
	require $module_name;
}
elsif (-f "t/$module_name") {
	require "t/$module_name";
}
elsif (-f "t\\$module_name") {
	require "t\\$module_name";
}

use Test::More tests => 2;
use Scrooge;

#########################
# Test a named pattern, 5 #
#########################

my ($test_offset, $N_to_match) = (2, 10);	
my $pattern = Scrooge::Test::Exactly::Offset->new(
	name => 'test_name', offset => $test_offset, N => $N_to_match);
my $data = [1 .. 15];

subtest 'Named pattern' => sub {
	if (my %match_results = $pattern->match($data)) {
		pass('pattern matched as expected');
		ok(exists($match_results{test_name}),
			'pattern name is a key in the match results');
		is($match_results{test_name}{left}, $test_offset, 'correct left offset');
		is($match_results{test_name}{right}, $match_results{left} + $N_to_match - 1
			, 'correct right offset');
	}
	else {
		fail('pattern did not match where it should have!');
	}
};

############################################
# Test failed application for memory leaks #
############################################

use Scalar::Util qw(weaken);

my $match_info;
{
	no warnings 'once';
	*Scrooge::Test::Exactly::Offset::prep = sub {
		my ($self, $info) = @_;
		$self->Scrooge::Test::Exactly::prep($info);
		$match_info = $info;
		weaken($match_info);
	};
}

# Set the offset to a large value so that the match will fail. $data contains
# 15 elements and we want to match exactly 10 of them, starting at the 12th
# element.
$pattern->{offset} = 12;
if ($pattern->match($data)) {
	fail('pattern was not supposed to match here');
}
else {
	is($match_info, undef, 'no memory leaks');
}
