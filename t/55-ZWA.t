use strict;
use warnings;
use Test::More tests => 37;
use Scrooge;

# Get an anonymous array with our data for testing
my $data = [1..20];
my $empty = [];

###########################
# parse_location tests: 7 #
###########################

my $pl = \&Scrooge::ZWA::parse_location;
is($pl->($data, 0), 0, 'parse_location: 0 => 0');
is($pl->($data, '100%'), 20, 'parse_location: 100% => N');
is($pl->($data, '-1'), 19, 'parse_location: -1 => N-1');
is($pl->($data, '1-4'), -3, 'parse_location: 1-4 => -3');
is($pl->($data, '1.2'), 1, 'parse_location: 1.2 => 1');
is($pl->($data, '12% + 3.4'), 6, 'parse_location: 12% + 3.4 => 5.8 => 6');
is($pl->($data, '14% + 3.4'), 6, 'parse_location: 14% + 3.4 => 6.2 => 6');

########################
# Constructor tests: 6 #
########################

my $begin = eval{re_anchor_begin('begin anchor')};
is($@, '', 'Begin anchor constructor does not croak');
isa_ok($begin, 'Scrooge::ZWA::Begin');
is($begin->{name}, 'begin anchor', 'Constructor correctly interprets name');

my $end = eval{re_anchor_end('end anchor')};
is($@, '', 'End anchor constructor does not croak');
isa_ok($end, 'Scrooge::ZWA::End');
is($end->{name}, 'end anchor', 'Constructor correctly interprets name');

########################
# Basic Match tests: 6 #
########################

my ($length, $offset) = eval{$begin->apply($data)};
is($@, '', 'Basic begin anchor does not croak');
is($length, 0, '    Matched length is correct');
is($offset, 0, '    Matched offset is correct');

($length, $offset) = eval{$end->apply($data)};
is($@, '', 'Basic end anchor does not croak');
is($length, 0, '    Matched length is correct');
is($offset, 20, '    Matched offset is correct');

##########################
# Wrapped match tests: 6 #
##########################

for my $anchor_re ($begin, $end) {
	# Build the expectation hash
	($length, $offset) = $anchor_re->apply($data);
	my $expected = { length => $length, offset => $offset };
	
	# Run the regex in each container:
	for my $wrapper_re_func (\&re_and, \&re_or, \&re_seq) {
		my $wrapper_re = $wrapper_re_func->($anchor_re);
		($length, $offset) = $wrapper_re->apply($data);
		my $got = { length => $length, offset => $offset };
		is_deeply($got, $expected, 'Anchor ' . ref($anchor_re) . ' is correctly'.
			' wrapped by container ' . ref($wrapper_re));
	}
}

###########################
# Complex Match tests: 12 #
###########################

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


my $complex = re_seq($begin, $begin);
($length, $offset) = eval{$complex->apply($data)};
is($@, '', 'Double begin anchor does not croak');
is($length, 0, '    Matched length is correct');
is($offset, 0, '    Matched offset is correct');

$complex = re_seq($end, $end);
($length, $offset) = eval{$complex->apply($data)};
is($@, '', 'Double end anchor does not croak');
is($length, 0, '    Matched length is correct');
is($offset, 20, '    Matched offset is correct');

$complex = re_seq($begin, re_any([3, 3]));
($length, $offset) = eval{$complex->apply($data)};
is($@, '', 'Complex begin anchor does not croak');
is($length, 3, '    Matched length is correct');
is($offset, 0, '    Matched offset is correct');

$complex = re_seq(re_any([3, 3]), $end);
($length, $offset) = eval{$complex->apply($data)};
is($@, '', 'Complex end anchor does not croak');
is($length, 3, '    Matched length is correct');
is($offset, 17, '    Matched offset is correct');
