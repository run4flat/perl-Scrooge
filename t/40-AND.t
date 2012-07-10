use strict;
use warnings;
use Test::More tests => 31;
use PDL;
use Regex::Engine;

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

# Assemble the data and a collection of regexes:
my $data = sequence(20);
my $fail_re = Regex::Engine::Test::Fail->new(name => 'fail');
my $should_croak_re = Regex::Engine::Test::ShouldCroak->new(name => 'should_croak');
my $croak_re = Regex::Engine::Test::Croak->new(name => 'croak');
my $all_re = Regex::Engine::Test::All->new(name => 'all');
my $even_re = Regex::Engine::Test::Even->new(name => 'even');
my $exact_re = Regex::Engine::Test::Exactly->new(name => 'exact');
my $range_re = Regex::Engine::Test::Range->new(name => 'range');
my $offset_re = Regex::Engine::Test::Exactly::Offset->new(name => 'offset');


########################
# Constructor tests: 6 #
########################

my $regex = eval{re_and('test regex', $all_re, $even_re)};
is($@, '', 'Basic constructor does not croak');
isa_ok($regex, 'Regex::Engine::And');
is($regex->{name}, 'test regex', 'Constructor correctly interprets name');

my ($length, $offset) = eval{$regex->apply($data)};
is($@, '', 'Basic usage does not croak');
is($length, 20, '    Matched length is correct');
is($offset, 0, '    Matched offset is correct');


#####################
# Croaking regex: 6 #
#####################

$regex = eval{re_and($should_croak_re)};
is($@, '', 'Constructor without name does not croak');
isa_ok($regex, 'Regex::Engine::And');
eval{$regex->apply($data)};
isnt($@, '', 're_and croaks when one of the regexes consumes too much');
eval{re_and($croak_re, $fail_re)->apply($data)};
isnt($@, '', 're_and croaks when one of its constituents croaks');
eval{re_and($all_re, $croak_re)->apply($data)};
isnt($@, '', 're_and only short-circuits on failure');
eval{re_and($fail_re, $croak_re, $all_re)->apply($data)};
is($@, '', 're_and short-circuits at the first failed constituent');


#####################
# Wrapping regex: 6 #
#####################

for $regex ($fail_re, $all_re, $even_re, $exact_re, $range_re, $offset_re) {
	my (@results) = re_and($regex)->apply($data);
	my (@expected) = $regex->apply($data);
	is_deeply(\@results, \@expected, 'Wrapping re_and does not alter behavior of ' . $regex->{name} . ' regex');
}


##############
# Failing: 2 #
##############

if(re_and($fail_re, $all_re)->apply($data)) {
	fail('re_and regex should fail when first constituent fails');
}
else {
	pass('re_and regex correctly fails when first constituent fails');
}
if(re_and($all_re, $fail_re)->apply($data)) {
	fail('re_and regex should fail when last constituent fails');
}
else {
	pass('re_and regex correctly fails when last constituent fails');
}

#######################
# Complex Regexes: 11 #
#######################

$exact_re->set_N(14);
my @results = re_and($all_re, $exact_re, $even_re)->apply($data);
is_deeply(\@results, [14, 0], 'First complex regex matches');
my $expected = {left => 0, right => 13};
is_deeply($all_re->get_details, $expected, '    All regex has correct offsets');
is_deeply($exact_re->get_details, $expected, '    Exact regex has correct offsets');
is_deeply($even_re->get_details, $expected, '    Even regex has correct offset');

$offset_re->set_N(4);
$offset_re->set_offset(4);
$range_re->min_size(1);
$range_re->max_size(10);
@results = re_and($offset_re, $all_re, $range_re)->apply($data);
is_deeply(\@results, [4, 4], 'Second complex regex matches');
$expected = {left => 4, right => 7};
is_deeply($all_re->get_details, $expected, '    All regex has correct offsets');
is_deeply($range_re->get_details, $expected, '    Range regex has correct offsets');
is_deeply($offset_re->get_details, $expected, '    Offset regex has correct offsets');

# This one should fail:
$exact_re->set_N(5);
@results = re_and($exact_re, $even_re)->apply($data);
is_deeply(\@results, [], 'Third complex regex should fail');
# These return nothing when they did not match; compare by capturing in an
# anonymous array and comparing with an empty array:
is_deeply([$exact_re->get_details], [], '    Exact regex does not have any offsets');
is_deeply([$even_re->get_details], [], '    Even regex does not have any offsets');

