use strict;
use warnings;
use Test::More tests => 4;
use PDL;
use Scrooge;
use Scrooge::PDL;

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
my $local_min = eval{ re_local_min };
my $local_max = eval{ re_local_max };

########################
# Constructor Tests: 2 #
########################
my $regex = eval{ re_named_or(x => $local_min, x => $local_max)};
is($@, '', 'Basic constructor does not croak.');
isa_ok($regex, 'Scrooge::Subdata::Or');


##################
# Match Tests: 2 #
##################

$regex = eval{ re_named_or(x => $local_min, x => $local_max)};
my $re_or = eval{ re_or($local_min, $local_max)};
my ($test_match, $test_offset) = eval{ $re_or->apply($data_3)};
my ($matched, $offset) = eval{$regex->apply({x => $data_3})};
isnt($matched, undef, 'Pattern found match.');
is($offset, $test_offset, 'Matched same value as re_or');

$regex = eval{re_named_or(x = $local_min, x => $local_max, y => $local_min, y => $local_max)};
($matched, $offset) = eval{$regex->apply({x => $data_2, y => $data_3})};