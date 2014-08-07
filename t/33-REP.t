# Tests Scrooge::Repeat
use strict;
use warnings;
use Test::More tests => 7;
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
	$exact_pat->{N} = 6;
	my $pattern = new_ok 'Scrooge::Repeat' => [subpattern => $exact_pat];
	is($pattern->{min_quant}, 0, 'default minimum quantifier');
	is($pattern->{max_quant}, '100%', 'default maximum quantifier');
	is($pattern->{min_rep}, 0, 'default minimum repetitions');
	is($pattern->{max_rep}, undef, 'default maximum repetitions');
	
	my %match_info = $pattern->match($data);
	
	# Check full match details
	is($match_info{length}, 18, 'full match length');
	is($match_info{left}, 0, 'full match offset');
	
	# Check the sub-match details
	if(ok(exists($match_info{exact}), "`exact' key exists in match_info")) {
		is(scalar(@{$match_info{exact}}), 3, 'three matches of exact');
		is($match_info{exact}[0]{left}, 0, 'first offset');
		is($match_info{exact}[1]{left}, 6, 'second offset');
		is($match_info{exact}[2]{left}, 12, 'third offset');
		is($match_info{exact}[0]{length}, 6, 'first length');
		is($match_info{exact}[1]{length}, 6, 'second length');
		is($match_info{exact}[2]{length}, 6, 'third length');
	}
	if(ok(exists($match_info{positive_matches}), "`positive_matches' key exists in match_info")) {
		is(scalar(@{$match_info{positive_matches}}), 3, 'three positive matches');
		is($match_info{positive_matches}[0]{left}, 0, 'first offset');
		is($match_info{positive_matches}[1]{left}, 6, 'second offset');
		is($match_info{positive_matches}[2]{left}, 12, 'third offset');
		is($match_info{positive_matches}[0]{length}, 6, 'first length');
		is($match_info{positive_matches}[1]{length}, 6, 'second length');
		is($match_info{positive_matches}[2]{length}, 6, 'third length');
	}
};

#################################
# re_rep short-name constructor #
#################################

subtest 're_rep' => sub {
	my $pattern = eval{re_rep()};
	isnt($@, '', 're_rep with nothing (croaks)');
	
	$pattern = eval{re_rep($exact_pat)};
	is($@, '', 're_rep with just a pattern');
	isa_ok($pattern, 'Scrooge::Repeat');
	my $length = $pattern->match($data);
	is($length, 18, 'produces viable Scrooge::Repeat');
	
	$pattern = re_rep(2, $exact_pat);
	isa_ok($pattern, 'Scrooge::Repeat');
	$length = $pattern->match($data);
	is($length, 12, 'with two args is viable');
	
	$pattern = re_rep([5 => 10], q{,2}, $exact_pat);
	isa_ok($pattern, 'Scrooge::Repeat');
	$length = $pattern->match($data);
	is($length, 6, 'with three args is viable');
	
	$pattern = re_rep('test_pattern', [5 => '100%'], q{,5}, $exact_pat);
	isa_ok($pattern, 'Scrooge::Repeat');
	$length = $pattern->match($data);
	is($length, 18, 'with four args is viable');
	
	eval{re_rep(1 .. 5)};
	like($@, qr/expects between 1 and 4 arguments/,
		'croaks when given too many arguments');
};

####################
# Croaking pattern #
####################

subtest 'Croaking patterns' => sub {
	eval{re_rep($should_croak_pat)->match($data)};
	isnt($@, '', 're_rep croaks when its pattern consumes too much');
	
	eval{re_rep($croak_pat)->match($data)};
	isnt($@, '', 're_rep croaks when its pattern croaks');
};

####################
# Wrapping pattern #
####################

subtest 'Wrapping re_rep around a single pattern' => sub {
	my @keys_to_compare = qw(left right length);
	for my $pattern ($fail_pat, $all_pat, $even_pat, $exact_pat, $range_pat,
		$offset_pat, $zwa_pat
	) {
		my %got = re_rep(1 => $pattern)->match($data);
		%got = map {$_ => $got{$_}} @keys_to_compare;
		my %expected = $pattern->match($data);
		%expected = map {$_ => $expected{$_}} @keys_to_compare;
		is_deeply(\%got, \%expected,
			'does not alter behavior of ' . $pattern->{name} . ' pattern');
	}
};

################
# Corner Cases #
################

subtest 'Corner cases' => sub {
	my $length = re_rep(2 => $exact_pat)->match($data);
	is($length, 12, 'easy-to-fit repetitions');
	
	$length = re_rep(3 => $exact_pat)->match($data);
	is($length, 18, 'close-to-edge repetitions');
	
	$length = re_rep(4 => $exact_pat)->match($data);
	is($length, undef, 'too many repetitions');
	
	$length = re_rep([0, 24], 4 => $exact_pat)->match($data);
	is($length, undef,'too many repetitions (even though commensurate with too many quantifiers)');
	
	$length = re_rep([15 => 19], [2 => 3] => $exact_pat)->match($data);
	is($length, 18, 'close-to-edge repetitions/quantifiers');
	
	$length = re_rep([14 => 18], [2 => 3] => $exact_pat)->match($data);
	is($length, 18, 'on-edge repetitions/quantifiers');
	
	$length = re_rep([13 => 17], [2 => 3] => $exact_pat)->match($data);
	is($length, undef, 'incommensurate repetitions/quantifiers');
	
	$length = re_rep([12 => 16], {2,3} => $exact_pat)->match($data);
	is($length, 12, 'on-edge repetitions/quantifiers');
	
};

######################################################
# Repeat a pattern that matches on different lengths #
######################################################

subtest 'Pattern that matches on different lengths' => sub {
	my $data = [1, 1, 1, 2, 2, 3, 4, 4, 5, 5, 5];
	
	# This pattern finds series of identical values
	my $pattern = re_sub( [1 => '100%'], sub {
		my $match_info = shift;
		my $left = $match_info->{left};
		my $to_find = $data->[$left];
		my $length = 1;
		for my $offset ($left+1 .. $match_info->{right}) {
			return $length if $data->[$offset] != $to_find;
			$length++;
		}
		return $match_info->{length};
	});
	
	# Apply it to our data
	my %match_info = re_rep($pattern)->match($data);
	is($match_info{length}, 11, 'full match length');
	is($match_info{positive_matches}[0]{length}, 3, 'first match length');
	is($match_info{positive_matches}[1]{length}, 2, 'second match length');
	is($match_info{positive_matches}[2]{length}, 1, 'third match length');
	is($match_info{positive_matches}[3]{length}, 2, 'fourth match length');
	is($match_info{positive_matches}[4]{length}, 3, 'fifth match length');
};

##########################################
# Repeat on a sequence including repeats #
##########################################

subtest 'Repetition of a complicated pattern' => sub {
	my $is_even = re_sub([1 => 1], sub {
		my $match_info = shift;
		my $i = $match_info->{left};
		return 1 if $match_info->{data}[$i] % 2 == 0;
		return 0;
	});
	$range_pat->{min_size} = 1;
	$range_pat->{max_size} = 7;
	my $pattern = re_rep(3, re_seq($range_pat, $is_even));
	
	#                3   1         7      1         5      1
	# matches     [     | ][             | ][             |  ]   
	my $data = [qw(1 2 3 4  5 5 5 5 5 6 7 8  9 10 11 12 13 14 15)];
	my %match_info = $pattern->match($data);
	is($match_info{length}, 18, 'full match length');
	is(scalar(@{$match_info{positive_matches}}), 3, 'three repetitions');
	my @seq_results = @{$match_info{positive_matches}[0]{positive_matches}};
	is($seq_results[0]{length}, 3, 'first range length');
	is($seq_results[1]{length}, 1, 'first even-value length');
	@seq_results = @{$match_info{positive_matches}[1]{positive_matches}};
	is($seq_results[0]{length}, 7, 'second range length');
	is($seq_results[1]{length}, 1, 'second even-value length');
	@seq_results = @{$match_info{positive_matches}[2]{positive_matches}};
	is($seq_results[0]{length}, 5, 'third range length');
	is($seq_results[1]{length}, 1, 'third even-value length');
};