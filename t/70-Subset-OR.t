use strict;
use warnings;
use Test::More tests => 0;
use PDL;
use Scrooge;

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

# Assemble mutiple sets of data and a collection of regexes.
my $data_1 = sequence(20);
my $data_2 = sin(sequence(10));
my $data_3 = pdl(5,4,3,2,1,0,1,2,3,4,5);
my $local_min = eval{re_local_min};
my $local_max = eval{re_local_max};

########################
# Constructor Tests: 0 #
########################
my $regex = eval{ re_named_or(x, $local_min)};
