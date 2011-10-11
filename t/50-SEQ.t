use strict;
use warnings;
use Test::More tests => 29;
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
# Constructor tests: 6 #
########################

my $regex = eval{SEQ('test regex', $all_re, $even_re)};
is($@, '', 'Basic constructor does not croak');
isa_ok($regex, 'PDL::Regex::Sequence');
is($regex->{name}, 'test regex', 'Constructor correctly interprets name');

my ($length, $offset) = eval{$regex->apply($data)};
is($@, '', 'Basic usage does not croak');
is($length, 20, '    Matched length is correct');
is($offset, 0, '    Matched offset is correct');


#####################
# Croaking regex: 7 #
#####################

$regex = eval{SEQ($should_croak_re)};
is($@, '', 'Constructor without name does not croak');
isa_ok($regex, 'PDL::Regex::Sequence');
eval{$regex->apply($data)};
isnt($@, '', 'SEQ croaks when the last regex consumes too much');
eval{SEQ($should_croak_re, $all_re)->apply($data)};
isnt($@, '', 'SEQ croaks when one of the not-last regexes consumes too much');
eval{SEQ($croak_re, $fail_re)->apply($data)};
isnt($@, '', 'SEQ croaks when one of its constituents croaks');
eval{SEQ($all_re, $croak_re)->apply($data)};
isnt($@, '', 'SEQ only short-circuits on failure');
eval{SEQ($fail_re, $croak_re, $all_re)->apply($data)};
is($@, '', 'SEQ short-circuits at the first failed constituent');


#####################
# Wrapping regex: 6 #
#####################

for $regex ($fail_re, $all_re, $even_re, $exact_re, $range_re, $offset_re) {
	my (@results) = SEQ($regex)->apply($data);
	my (@expected) = $regex->apply($data);
	is_deeply(\@results, \@expected, 'Wrapping SEQ does not alter behavior of ' . $regex->{name} . ' regex');
}


#######################
# Complex Regexes: 10 #
#######################

# Create two zero-width assertion regexes:
$offset_re->set_N('0 but true');
$offset_re->set_offset(4);
my $at_ten = PDL::Regex::Test::Exactly::Offset->new(N => '0 but true', offset => 10);
($length, $offset) = SEQ($offset_re, $all_re, $at_ten)->apply($data);
ok($length, 'First complex regex matches');
is($length, 6, '    Length was correctly determined to be 6');
is($offset, 4, '    Offset was correctly determined to be 4');
is_deeply([$all_re->get_offsets], [pdl(4), pdl(9)], '    All has correct offset information');
my @offsets = $offset_re->get_offsets;
is_deeply([$offset_re->get_offsets], [pdl(4), pdl(3)], '    Offset has correct offset information');

# Perform a match at three different segments with the same regex and make
# sure it stores all three:
($length, $offset) = SEQ($all_re, $offset_re, $all_re, $at_ten, $all_re)->apply($data);
ok($length, 'Second complex regex matches');
is($length, 20, '    Length was correctly determined to be 20');
is($offset, 0, '    Offset was correctly determined to be 0');
my ($left, $right) = $all_re->get_offsets;
ok(all ($left == pdl(0, 4, 10)), '    All regex correctly stored is left offsets');
ok(all ($right == pdl(3, 9, 19)), '    All regex correctly stored its right offsets');

