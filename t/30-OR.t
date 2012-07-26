use strict;
use warnings;
use Test::More tests => 47;
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
# Constructor tests: 7 #
########################

my $regex = eval{re_or('test regex', $all_re, $fail_re)};
is($@, '', 'Basic constructor does not croak');
isa_ok($regex, 'Scrooge::Or');
is($regex->{name}, 'test regex', 'Constructor correctly interprets name');

my ($length, $offset) = eval{$regex->apply($data)};
is($@, '', 'Basic usage does not croak');
is($length, $data->nelem, 'Or matches on first successful regex, i.e. All');
is($offset, 0, 'Offset of All match is zero');

($length, $offset) = re_or($fail_re, $all_re)->apply($data);
is($length, $data->nelem, 'Or matches on first *successful* regex');

#####################
# Croaking regex: 6 #
#####################

$regex = eval{re_or($should_croak_re)};
is($@, '', 'Constructor without name does not croak');
isa_ok($regex, 'Scrooge::Or');
eval{$regex->apply($data)};
isnt($@, '', 're_or croaks when one of the regexes consumes too much');
eval{re_or($croak_re, $all_re)->apply($data)};
isnt($@, '', 're_or croaks when one of its constituents croaks even if a later one would pass');
eval{re_or($all_re, $croak_re)->apply($data)};
is($@, '', 're_or short-circuits on the first success');
eval{re_or($fail_re, $croak_re)->apply($data)};
isnt($@, '', 're_or does not short-circuit unless it actually encounters success');

###################
# Simple regex: 6 #
###################

for $regex ($fail_re, $all_re, $even_re, $exact_re, $range_re, $offset_re) {
	my (@results) = re_or($regex)->apply($data);
	my (@expected) = $regex->apply($data);
	is_deeply(\@results, \@expected, 'Wrapping re_or does not alter behavior of ' . $regex->{name} . ' regex');
}

####################
# Failing regex: 4 #
####################

$exact_re->set_N(25);
$offset_re->set_offset(30);
if (re_or($fail_re, $exact_re, $offset_re)->apply($data)) {
	fail('Failing regex passed when it should have failed');
}
else {
	pass('Failing regex failed as expected');
}
is_deeply([$fail_re->get_details], [], '    Fail regex does not have match info');
is_deeply([$exact_re->get_details], [], '    Exact regex does not have match info')
	or do{ require Data::Dumper; print Data::Dumper::Dumper($exact_re->get_details)};
is_deeply([$offset_re->get_details], [], '    Offset regex does not have match info');

#######################
# Complex Regexen: 24 #
#######################

$offset_re->set_offset(4);
$offset_re->set_N(8);
my @results = re_or($fail_re, $exact_re, $offset_re)->apply($data);
is_deeply(\@results, [8, 4], 'First complex regex should match against the offset regex');
is_deeply([$fail_re->get_details], [], '    Fail does not match');
is_deeply([$exact_re->get_details], [], '    Exact does not have any match');
is_deeply($offset_re->get_details, {left => 4, right => 11}, '    Offset does have match info');

$exact_re->set_N(15);
@results = re_or($fail_re, $exact_re, $even_re, $range_re)->apply($data);
is_deeply(\@results, [15, 0], 'Second complex regex should match against the exact regex');
my $first_result_ref = $exact_re->get_details;
my %first_result_hash = %$first_result_ref;
my ($left, $right) = @first_result_hash{'left', 'right'};
isnt($left, undef, '    Exact has match info');
is($left, 0, '    Exact has proper left offset');
is($right, 14, '    Exact has proper right offset');
is_deeply([$fail_re->get_details], [], '    Fail does not have match info');
is_deeply([$even_re->get_details], [], '    Even does not have match info');
is_deeply([$range_re->get_details], [], '    Range does not have match info');

@results = re_or($even_re, $exact_re, $range_re)->apply($data);
is_deeply(\@results, [20, 0], 'Third complex regex should match against the even regex');
my %even_results_hash = %{ $even_re->get_details };
($left, $right) = @even_results_hash{'left', 'right'};
isnt($left, undef, '    Even has match info');
is($left, 0, '    Even has proper left offset');
is($right, 19, '    Even has proper right offset');
is_deeply([$exact_re->get_details], [], '    Exact does not have match info');
is_deeply([$range_re->get_details], [], '    Range does not have match info');

$range_re->min_size(10);
$range_re->max_size(18);
@results = re_or($fail_re, $range_re, $even_re, $exact_re)->apply($data);
is_deeply(\@results, [18, 0], 'Fourth complex regex should match against the range regex');
my %range_results_hash = %{ $range_re->get_details };
($left, $right) = @range_results_hash{'left', 'right'};
isnt($left, undef, '    Range has match info');
is($left, 0, '    Range has proper left offset');
is($right, 17, '    Range has proper right offset');
is_deeply([$fail_re->get_details], [], '    Fail does not have match info');
is_deeply([$even_re->get_details], [], '    Even does not have match info');
is_deeply([$exact_re->get_details], [], '    Exact does not have match info');

