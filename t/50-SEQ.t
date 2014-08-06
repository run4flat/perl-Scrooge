use strict;
use warnings;
use Test::More tests => 3;
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
my $data = [1 .. 20];
my $fail_pat = Scrooge::Test::Fail->new(name => 'fail');
my $should_croak_pat = Scrooge::Test::ShouldCroak->new(name => 'should_croak');
my $croak_pat = Scrooge::Test::Croak->new(name => 'croak');
my $all_pat = Scrooge::Test::All->new(name => 'all');
my $even_pat = Scrooge::Test::Even->new(name => 'even');
my $exact_pat = Scrooge::Test::Exactly->new(name => 'exact');
my $range_pat = Scrooge::Test::Range->new(name => 'range');
my $offset_pat = Scrooge::Test::Exactly::Offset->new(name => 'offset');
my $zwa_pat = Scrooge::Test::OffsetZWA->new(name => 'zwa');

#####################
# Constructor tests #
#####################

subtest 'Basic constructor and simple sequence' => sub {
	my $pattern = re_seq('test pattern', $all_pat, $even_pat);
	isa_ok($pattern, 'Scrooge::Sequence');
	is($pattern->{name}, 'test pattern', 're_seq correctly sets up name');
	
	my %match_info = $pattern->match($data);
	
	# Check full match details
	is($match_info{length}, 20, 'full match length');
	is($match_info{left}, 0, 'full match offset');
	
	# Check "all" match detauls
	is($match_info{all}[0]{left}, 0, "`all' match offset");
	is($match_info{all}[0]{length}, 18, "`all' match length");
	
	# Check "even" match details
	is($match_info{even}[0]{left}, 18, "`even' match offset");
	is($match_info{even}[0]{length}, 2, "`even' match length");
};

####################
# Croaking pattern #
####################

subtest 'Croaking patterns' => sub {
	my $pattern = eval{re_seq($should_croak_pat)};
	is($@, '', 'Constructor without name does not croak');
	isa_ok($pattern, 'Scrooge::Sequence');
	
	eval{$pattern->match($data)};
	isnt($@, '', 're_seq croaks when the last pattern consumes too much');
	
	eval{re_seq($should_croak_pat, $all_pat)->match($data)};
	isnt($@, '', 're_seq croaks when one of the not-last patterns consumes too much');
	
	eval{re_seq($croak_pat, $fail_pat)->match($data)};
	isnt($@, '', 're_seq croaks when one of its constituents croaks');
	
	eval{re_seq($fail_pat, $croak_pat, $all_pat)->match($data)};
	is($@, '', 're_seq short-circuits at the first failed constituent');
	
	eval{re_seq($all_pat, $croak_pat)->match($data)};
	isnt($@, '', 're_seq only short-circuits on failure');
};

####################
# Wrapping pattern #
####################

subtest 'Wrapping re_and around a single pattern' => sub {
	my @keys_to_compare = qw(left right length);
	for my $pattern ($fail_pat, $all_pat, $even_pat, $exact_pat, $range_pat,
		$offset_pat, $zwa_pat
	) {
		my %got = re_seq($pattern)->match($data);
		%got = map {$_ => $got{$_}} @keys_to_compare;
		my %expected = $pattern->match($data);
		%expected = map {$_ => $expected{$_}} @keys_to_compare;
		is_deeply(\%got, \%expected,
			'does not alter behavior of ' . $pattern->{name} . ' pattern');
	}
};

__END__
######################
# Complex patterns: 9 #
######################

# Create two zero-width assertion patterns:
$offset_pat->set_N('0 but true');
$offset_pat->set_offset(4);
# XXX cannot set N => '0 but true'. Why?
my $at_ten = Scrooge::Test::Exactly::Offset->new(N => 1, offset => 10);
($length, $offset) = re_seq($offset_pat, $all_pat, $at_ten)->match($data);
ok($length, 'First complex pattern matches');
is($length, 7, '    Length was correctly determined to be 6');
is($offset, 4, '    Offset was correctly determined to be 4');
my $expected = {left => 4, right => 9};
is_deeply($all_pat->get_details, $expected, '    All has correct offset information');
$expected = {left => 4, right => 3};
is_deeply($offset_pat->get_details, $expected, '    Offset has correct offset information');

# Perform a match at three different segments with the same pattern and make
# sure it stores all three:
($length, $offset) = re_seq($all_pat, $offset_pat, $all_pat, $at_ten, $all_pat)->match($data);
ok($length, 'Second complex pattern matches');
is($length, 20, '    Length was correctly determined to be 20');
is($offset, 0, '    Offset was correctly determined to be 0');
$expected = [
	{left => 0, right => 3},
	{left => 4, right => 9},
	{left => 11, right => 19},
];
my @results = $all_pat->get_details;
is_deeply(\@results, $expected, '    Single pattern stores multiple matches correctly');

