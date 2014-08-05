# Tests on_key handling

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

use Test::More;
use Scrooge;

####################
# Select by on_key #
####################

my ($test_offset, $N_to_match) = (2, 10);	
my $pattern = Scrooge::Test::Exactly::Offset->new(on_key => 'bar',
	offset => $test_offset, N => $N_to_match);
my $foo_data = [1 .. 5];
my $bar_data = [1 .. 15];

if (my %match_results = $pattern->match(foo => $foo_data, bar => $bar_data)) {
	is($match_results{left}, $test_offset, 'correct left offset');
	is($match_results{right}, $match_results{left} + $N_to_match - 1
		, 'correct right offset');
}
else {
	fail('did not match where it should have');
}

done_testing;
