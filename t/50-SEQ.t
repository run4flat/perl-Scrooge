use strict;
use warnings;
use Test::More tests => 28;
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

# Assemble the data and a collection of regexes:
my $data = sequence(20);
my $fail_re = Scrooge::Test::Fail->new(name => 'fail');
my $should_croak_re = Scrooge::Test::ShouldCroak->new(name => 'should_croak');
my $croak_re = Scrooge::Test::Croak->new(name => 'croak');
my $all_re = Scrooge::Test::All->new(name => 'all');
my $even_re = Scrooge::Test::Even->new(name => 'even');
my $exact_re = Scrooge::Test::Exactly->new(name => 'exact');
my $range_re = Scrooge::Test::Range->new(name => 'range');
my $offset_re = Scrooge::Test::Exactly::Offset->new(name => 'offset');

########################
# Constructor tests: 6 #
########################

my $regex = eval{re_seq('test regex', $all_re, $even_re)};
is($@, '', 'Basic constructor does not croak');
isa_ok($regex, 'Scrooge::Sequence');
is($regex->{name}, 'test regex', 'Constructor correctly interprets name');

my ($length, $offset) = eval{$regex->apply($data)};
is($@, '', 'Basic usage does not croak');
is($length, 20, '    Matched length is correct');
is($offset, 0, '    Matched offset is correct');


#####################
# Croaking regex: 7 #
#####################

$regex = eval{re_seq($should_croak_re)};
is($@, '', 'Constructor without name does not croak');
isa_ok($regex, 'Scrooge::Sequence');
eval{$regex->apply($data)};
isnt($@, '', 're_seq croaks when the last regex consumes too much');
eval{re_seq($should_croak_re, $all_re)->apply($data)};
isnt($@, '', 're_seq croaks when one of the not-last regexes consumes too much');
eval{re_seq($croak_re, $fail_re)->apply($data)};
isnt($@, '', 're_seq croaks when one of its constituents croaks');
eval{re_seq($all_re, $croak_re)->apply($data)};
isnt($@, '', 're_seq only short-circuits on failure');
eval{re_seq($fail_re, $croak_re, $all_re)->apply($data)};
is($@, '', 're_seq short-circuits at the first failed constituent');


#####################
# Wrapping regex: 6 #
#####################

for $regex ($fail_re, $all_re, $even_re, $exact_re, $range_re, $offset_re) {
	my (@results) = re_seq($regex)->apply($data);
	my (@expected) = $regex->apply($data);
	is_deeply(\@results, \@expected, 'Wrapping re_seq does not alter behavior of ' . $regex->{name} . ' regex');
}


######################
# Complex Regexes: 9 #
######################

# Create two zero-width assertion regexes:
$offset_re->set_N('0 but true');
$offset_re->set_offset(4);
# XXX cannot set N => '0 but true'. Why?
my $at_ten = Scrooge::Test::Exactly::Offset->new(N => 1, offset => 10);
($length, $offset) = re_seq($offset_re, $all_re, $at_ten)->apply($data);
ok($length, 'First complex regex matches');
is($length, 7, '    Length was correctly determined to be 6');
is($offset, 4, '    Offset was correctly determined to be 4');
my $expected = {left => 4, right => 9};
is_deeply($all_re->get_details, $expected, '    All has correct offset information');
$expected = {left => 4, right => 3};
is_deeply($offset_re->get_details, $expected, '    Offset has correct offset information');

# Perform a match at three different segments with the same regex and make
# sure it stores all three:
($length, $offset) = re_seq($all_re, $offset_re, $all_re, $at_ten, $all_re)->apply($data);
ok($length, 'Second complex regex matches');
is($length, 20, '    Length was correctly determined to be 20');
is($offset, 0, '    Offset was correctly determined to be 0');
$expected = [
	{left => 0, right => 3},
	{left => 4, right => 9},
	{left => 11, right => 19},
];
my @results = $all_re->get_details;
is_deeply(\@results, $expected, '    Single regex stores multiple matches correctly');

