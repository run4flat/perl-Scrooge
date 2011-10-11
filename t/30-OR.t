use strict;
use warnings;
use Test::More tests => 47;
use PDL;
use PDL::Regex;

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
my $fail_re = PDL::Regex::Test::Fail->new(name => 'fail');
my $should_croak_re = PDL::Regex::Test::ShouldCroak->new(name => 'should_croak');
my $croak_re = PDL::Regex::Test::Croak->new(name => 'croak');
my $all_re = PDL::Regex::Test::All->new(name => 'all');
my $even_re = PDL::Regex::Test::Even->new(name => 'even');
my $exact_re = PDL::Regex::Test::Exactly->new(name => 'exact');
my $range_re = PDL::Regex::Test::Range->new(name => 'range');
my $offset_re = PDL::Regex::Test::Exactly::Offset->new(name => 'offset');

########################
# Constructor tests: 7 #
########################

my $regex = eval{OR('test regex', $all_re, $fail_re)};
is($@, '', 'Basic constructor does not croak');
isa_ok($regex, 'PDL::Regex::Or');
is($regex->{name}, 'test regex', 'Constructor correctly interprets name');

my ($length, $offset) = eval{$regex->apply($data)};
is($@, '', 'Basic usage does not croak');
is($length, $data->nelem, 'Or matches on first successful regex, i.e. All');
is($offset, 0, 'Offset of All match is zero');

($length, $offset) = OR($fail_re, $all_re)->apply($data);
is($length, $data->nelem, 'Or matches on first *successful* regex');

#####################
# Croaking regex: 6 #
#####################

$regex = eval{OR($should_croak_re)};
is($@, '', 'Constructor without name does not croak');
isa_ok($regex, 'PDL::Regex::Or');
eval{$regex->apply($data)};
isnt($@, '', 'OR croaks when one of the regexes consumes too much');
eval{OR($croak_re, $all_re)->apply($data)};
isnt($@, '', 'OR croaks when one of its constituents croaks even if a later one would pass');
eval{OR($all_re, $croak_re)->apply($data)};
is($@, '', 'OR short-circuits on the first success');
eval{OR($fail_re, $croak_re)->apply($data)};
isnt($@, '', 'OR does not short-circuit unless it actually encounters success');

###################
# Simple regex: 6 #
###################

for $regex ($fail_re, $all_re, $even_re, $exact_re, $range_re, $offset_re) {
	my (@results) = OR($regex)->apply($data);
	my (@expected) = $regex->apply($data);
	is_deeply(\@results, \@expected, 'Wrapping OR does not alter behavior of ' . $regex->{name} . ' regex');
}

####################
# Failing regex: 4 #
####################

$exact_re->set_N(25);
$offset_re->set_offset(30);
if (OR($fail_re, $exact_re, $offset_re)->apply($data)) {
	fail('Failing regex passed when it should have failed');
}
else {
	pass('Failing regex failed as expected');
}
is_deeply([$fail_re->get_offsets], [], '    Fail regex does not have match info');
is_deeply([$exact_re->get_offsets], [], '    Exact regex does not have match info');
is_deeply([$offset_re->get_offsets], [], '    Offset regex does not have match info');

#######################
# Complex Regexen: 24 #
#######################

$offset_re->set_offset(4);
$offset_re->set_N(8);
my @results = OR($fail_re, $exact_re, $offset_re)->apply($data);
is_deeply(\@results, [8, 4], 'First complex regex should match against the offset regex');
is_deeply([$fail_re->get_offsets], [], '    Fail does not match');
is_deeply([$exact_re->get_offsets], [], '    Exact does not have any match');
is_deeply([$offset_re->get_offsets], [pdl(4), pdl(11)], '    Offset does have match info');

$exact_re->set_N(15);
@results = OR($fail_re, $exact_re, $even_re, $range_re)->apply($data);
is_deeply(\@results, [15, 0], 'Second complex regex should match against the exact regex');
my ($left, $right) = $exact_re->get_offsets;
isnt($left, undef, '    Exact has match info');
is($left->at(0), 0, '    Exact has proper left offset');
is($right->at(0), 14, '    Exact has proper right offset');
is_deeply([$fail_re->get_offsets], [], '    Fail does not have match info');
is_deeply([$even_re->get_offsets], [], '    Even does not have match info');
is_deeply([$range_re->get_offsets], [], '    Range does not have match info');

@results = OR($even_re, $exact_re, $range_re)->apply($data);
is_deeply(\@results, [20, 0], 'Third complex regex should match against the even regex');
($left, $right) = $even_re->get_offsets;
isnt($left, undef, '    Even has match info');
is($left->at(0), 0, '    Even has proper left offset');
is($right->at(0), 19, '    Even has proper right offset');
is_deeply([$exact_re->get_offsets], [], '    Exact does not have match info');
is_deeply([$range_re->get_offsets], [], '    Range does not have match info');

$range_re->min_size(10);
$range_re->max_size(18);
@results = OR($fail_re, $range_re, $even_re, $exact_re)->apply($data);
is_deeply(\@results, [18, 0], 'Fourth complex regex should match against the range regex');
($left, $right) = $range_re->get_offsets;
isnt($left, undef, '    Range has match info');
is($left->at(0), 0, '    Range has proper left offset');
is($right->at(0), 17, '    Range has proper right offset');
is_deeply([$fail_re->get_offsets], [], '    Fail does not have match info');
is_deeply([$even_re->get_offsets], [], '    Even does not have match info');
is_deeply([$exact_re->get_offsets], [], '    Exact does not have match info');

