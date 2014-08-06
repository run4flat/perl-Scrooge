use strict;
use warnings;
use Test::More tests => 6;
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
my $zwa_pat = Scrooge::Test::OffsetZWA->new(name => 'zwa');


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

####################
# Croaking pattern #
####################

subtest 'Croaking patterns' => sub {
	my $pattern = re_and($should_croak_pat);
	pass('Constructor without name does not croak');
	isa_ok($pattern, 'Scrooge::And');
	
	eval{$pattern->match($data)};
	isnt($@, '', 'croaks when one of the patterns consumes too much');
	
	eval{re_and($croak_pat, $fail_pat)->match($data)};
	isnt($@, '', 'croaks when one of its constituents croaks');
	
	eval{re_and($fail_pat, $croak_pat, $all_pat)->match($data)};
	is($@, '', 'short-circuits at the first failed constituent');
	
	eval{re_and($all_pat, $croak_pat)->match($data)};
	isnt($@, '', 'only short-circuits on failure');
};

####################
# Wrapping pattern #
####################

subtest 'Wrapping re_and around a single pattern' => sub {
	my @keys_to_compare = qw(left right length);
	for my $pattern ($fail_pat, $all_pat, $even_pat, $exact_pat, $range_pat,
		$offset_pat, $zwa_pat
	) {
		my %got = re_and($pattern)->match($data);
		%got = map {$_ => $got{$_}} @keys_to_compare;
		my %expected = $pattern->match($data);
		%expected = map {$_ => $expected{$_}} @keys_to_compare;
		is_deeply(\%got, \%expected,
			'does not alter behavior of ' . $pattern->{name} . ' pattern');
	}
};

###########
# Failing #
###########

subtest "We're all in the same boat..." => sub {
	my $length = re_and($fail_pat, $all_pat)->match($data);
	is($length, undef, 'If the first fails, the whole pattern fails');
	$length = re_and($all_pat, $fail_pat)->match($data);
	is($length, undef, 'If the last fails, the whole pattern fails');
};

####################
# Complex patterns #
####################

subtest 'Three matching patterns all match under re_and' => sub {
	$exact_pat->{N} = 14;
	my %match_info = re_and($all_pat, $exact_pat, $even_pat)->match($data);
	is($match_info{left}, 0, 'correct offset');
	ok( 14 == $match_info{length}
	 && 14 == $match_info{positive_matches}[0]{length}
	 && 14 == $match_info{all}[0]{length}
	 && 14 == $match_info{positive_matches}[1]{length}
	 && 14 == $match_info{exact}[0]{length}
	 && 14 == $match_info{positive_matches}[2]{length}
	 && 14 == $match_info{even}[0]{length}
	 , 'correct length, easily accessible') or diag explain \%match_info;
	ok( 0 == $match_info{left}
	 && 0 == $match_info{positive_matches}[0]{left}
	 && 0 == $match_info{all}[0]{left}
	 && 0 == $match_info{positive_matches}[1]{left}
	 && 0 == $match_info{exact}[0]{left}
	 && 0 == $match_info{positive_matches}[2]{left}
	 && 0 == $match_info{even}[0]{left}
	 , 'correct offset, easily accessible') or diag explain \%match_info;
};

subtest "I may be even, but you're odd" => sub {
	$offset_pat->{offset} = 10;
	$offset_pat->{N} = 5;
	$zwa_pat->{offset} = 10;
	my %match_info = re_and($zwa_pat, $offset_pat)->match($data);
	is_deeply(\%match_info, {}, 'Zero-width and nonzero-width patterns do not match')
		or diag explain \%match_info;
	
	$exact_pat->{N} = 5;
	my %match_info = re_and($exact_pat, $even_pat)->match($data);
	is_deeply(\%match_info, {}, 'Incommensurate subpattern lengths leads to failure')
		or diag explain \%match_info;
};
