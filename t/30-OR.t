use strict;
use warnings;
use Test::More tests => 1;
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

# Assemble the data and a collection of patterns:
my $arr_len = 20;
my $data = [1 .. $arr_len];
my $fail = Scrooge::Test::Fail->new(name => 'fail');
my $should_croak = Scrooge::Test::ShouldCroak->new(name => 'should_croak');
my $croak = Scrooge::Test::Croak->new(name => 'croak');
my $all = Scrooge::Test::All->new(name => 'all');
my $even = Scrooge::Test::Even->new(name => 'even');
my $exact = Scrooge::Test::Exactly->new(name => 'exact');
my $range = Scrooge::Test::Range->new(name => 'range');
my $offset = Scrooge::Test::Exactly::Offset->new(name => 'offset');

########################
# Constructor tests: 7 #
########################

subtest 'Basic constructor test' => sub {
	my $pattern = eval{re_or('test pattern', $all, $fail)};
	is($@, '', 're_or does not croak for proper usage');
	isa_ok($pattern, 'Scrooge::Or');
	is($pattern->{name}, 'test pattern', 'correctly sets up name');
	
	my %match_info = eval{$pattern->match($data)};
	is($@, '', 'match does not croak');
	is($match_info{length}, $arr_len, 'matches on first successful pattern');
	is($match_info{left}, 0, 'correct offset');
	
	my $length = re_or($fail, $all)->match($data);
	is($length, $arr_len, 'matches on second pattern if first fails');
}

__END__
#####################
# Croaking pattern: 6 #
#####################

$pattern = eval{re_or($should_croak)};
is($@, '', 'Constructor without name does not croak');
isa_ok($pattern, 'Scrooge::Or');
eval{$pattern->apply($data)};
isnt($@, '', 're_or croaks when one of the patternes consumes too much');
eval{re_or($croak, $all)->apply($data)};
isnt($@, '', 're_or croaks when one of its constituents croaks even if a later one would pass');
eval{re_or($all, $croak)->apply($data)};
is($@, '', 're_or short-circuits on the first success');
eval{re_or($fail, $croak)->apply($data)};
isnt($@, '', 're_or does not short-circuit unless it actually encounters success');

###################
# Simple pattern: 6 #
###################

for $pattern ($fail, $all, $even, $exact, $range, $match_info{left}) {
	my (@results) = re_or($pattern)->apply($data);
	my (@expected) = $pattern->apply($data);
	is_deeply(\@results, \@expected, 'Wrapping re_or does not alter behavior of ' . $pattern->{name} . ' pattern');
}

####################
# Failing pattern: 4 #
####################

$exact->set_N(25);
$match_info{left}->set_offset(30);
if (re_or($fail, $exact, $match_info{left})->apply($data)) {
	fail('Failing pattern passed when it should have failed');
}
else {
	pass('Failing pattern failed as expected');
}
is_deeply([$fail->get_details], [], '    Fail pattern does not have match info');
is_deeply([$exact->get_details], [], '    Exact pattern does not have match info')
	or do{ require Data::Dumper; print Data::Dumper::Dumper($exact->get_details)};
is_deeply([$match_info{left}->get_details], [], '    Offset pattern does not have match info');

#######################
# Complex patternen: 24 #
#######################

$match_info{left}->set_offset(4);
$match_info{left}->set_N(8);
my @results = re_or($fail, $exact, $match_info{left})->apply($data);
is_deeply(\@results, [8, 4], 'First complex pattern should match against the offset pattern');
is_deeply([$fail->get_details], [], '    Fail does not match');
is_deeply([$exact->get_details], [], '    Exact does not have any match');
is_deeply($match_info{left}->get_details, {left => 4, right => 11}, '    Offset does have match info');

$exact->set_N(15);
@results = re_or($fail, $exact, $even, $range)->apply($data);
is_deeply(\@results, [15, 0], 'Second complex pattern should match against the exact pattern');
my $first_result_ref = $exact->get_details;
my %first_result_hash = %$first_result_ref;
my ($left, $right) = @first_result_hash{'left', 'right'};
isnt($left, undef, '    Exact has match info');
is($left, 0, '    Exact has proper left offset');
is($right, 14, '    Exact has proper right offset');
is_deeply([$fail->get_details], [], '    Fail does not have match info');
is_deeply([$even->get_details], [], '    Even does not have match info');
is_deeply([$range->get_details], [], '    Range does not have match info');

@results = re_or($even, $exact, $range)->apply($data);
is_deeply(\@results, [20, 0], 'Third complex pattern should match against the even pattern');
my %even_results_hash = %{ $even->get_details };
($left, $right) = @even_results_hash{'left', 'right'};
isnt($left, undef, '    Even has match info');
is($left, 0, '    Even has proper left offset');
is($right, 19, '    Even has proper right offset');
is_deeply([$exact->get_details], [], '    Exact does not have match info');
is_deeply([$range->get_details], [], '    Range does not have match info');

$range->min_size(10);
$range->max_size(18);
@results = re_or($fail, $range, $even, $exact)->apply($data);
is_deeply(\@results, [18, 0], 'Fourth complex pattern should match against the range pattern');
my %range_results_hash = %{ $range->get_details };
($left, $right) = @range_results_hash{'left', 'right'};
isnt($left, undef, '    Range has match info');
is($left, 0, '    Range has proper left offset');
is($right, 17, '    Range has proper right offset');
is_deeply([$fail->get_details], [], '    Fail does not have match info');
is_deeply([$even->get_details], [], '    Even does not have match info');
is_deeply([$exact->get_details], [], '    Exact does not have match info');

