use strict;
use warnings;
use Test::More tests => 1;
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

# Assemble the data and a collection of patterns:
my $arr_len = 20;
my $data = [1 .. $arr_len];
my $fail_pat = Scrooge::Test::Fail->new(name => 'fail');
my $should_croak_pat = Scrooge::Test::ShouldCroak->new(name => 'should_croak');
my $croak_pat = Scrooge::Test::Croak->new(name => 'croak');
my $all_pat = Scrooge::Test::All->new(name => 'all');
my $even_pat = Scrooge::Test::Even->new(name => 'even');
my $exact_pat = Scrooge::Test::Exactly->new(name => 'exact');
my $range_pat = Scrooge::Test::Range->new(name => 'range');
my $offset_pat = Scrooge::Test::Exactly::Offset->new(name => 'offset');


########################
# Constructor tests: 6 #
########################

subtest 'Constructor tests' => sub {
	my $pattern = re_and('test pattern', $all_pat, $even_pat);
	isa_ok($pattern, 'Scrooge::And');
	is($pattern->{name}, 'test pattern', 're_and correctly sets up name');
	
	my %match_info = $pattern->match($data);
	is($match_info{length}, 20, 'length');
	is($match_info{left}, 0, 'offset');
};

__END__


#####################
# Croaking pattern: 6 #
#####################

$pattern = eval{re_and($should_croak_pat)};
is($@, '', 'Constructor without name does not croak');
isa_ok($pattern, 'Scrooge::And');
eval{$pattern->match($data)};
isnt($@, '', 're_and croaks when one of the patterns consumes too much');
eval{re_and($croak_pat, $fail_pat)->match($data)};
isnt($@, '', 're_and croaks when one of its constituents croaks');
eval{re_and($all_pat, $croak_pat)->match($data)};
isnt($@, '', 're_and only short-circuits on failure');
eval{re_and($fail_pat, $croak_pat, $all_pat)->match($data)};
is($@, '', 're_and short-circuits at the first failed constituent');


#####################
# Wrapping pattern: 6 #
#####################

for $pattern ($fail_pat, $all_pat, $even_pat, $exact_pat, $range_pat, $offset_pat) {
	my (@results) = re_and($pattern)->match($data);
	my (@expected) = $pattern->match($data);
	is_deeply(\@results, \@expected, 'Wrapping re_and does not alter behavior of ' . $pattern->{name} . ' pattern');
}


##############
# Failing: 2 #
##############

if(re_and($fail_pat, $all_pat)->match($data)) {
	fail('re_and pattern should fail when first constituent fails');
}
else {
	pass('re_and pattern correctly fails when first constituent fails');
}
if(re_and($all_pat, $fail_pat)->match($data)) {
	fail('re_and pattern should fail when last constituent fails');
}
else {
	pass('re_and pattern correctly fails when last constituent fails');
}

#######################
# Complex patterns: 11 #
#######################

$exact_pat->set_N(14);
my @results = re_and($all_pat, $exact_pat, $even_pat)->match($data);
is_deeply(\@results, [14, 0], 'First complex pattern matches');
my $expected = {left => 0, right => 13};
is_deeply($all_pat->get_details, $expected, '    All pattern has correct offsets');
is_deeply($exact_pat->get_details, $expected, '    Exact pattern has correct offsets');
is_deeply($even_pat->get_details, $expected, '    Even pattern has correct offset');

$offset_pat->set_N(4);
$offset_pat->set_offset(4);
$range_pat->min_size(1);
$range_pat->max_size(10);
@results = re_and($offset_pat, $all_pat, $range_pat)->match($data);
is_deeply(\@results, [4, 4], 'Second complex pattern matches');
$expected = {left => 4, right => 7};
is_deeply($all_pat->get_details, $expected, '    All pattern has correct offsets');
is_deeply($range_pat->get_details, $expected, '    Range pattern has correct offsets');
is_deeply($offset_pat->get_details, $expected, '    Offset pattern has correct offsets');

# This one should fail:
$exact_pat->set_N(5);
@results = re_and($exact_pat, $even_pat)->match($data);
is_deeply(\@results, [], 'Third complex pattern should fail');
# These return nothing when they did not match; compare by capturing in an
# anonymous array and comparing with an empty array:
is_deeply([$exact_pat->get_details], [], '    Exact pattern does not have any offsets');
is_deeply([$even_pat->get_details], [], '    Even pattern does not have any offsets');

