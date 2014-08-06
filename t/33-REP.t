# Tests Scrooge::Repeat
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

__END__

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

####################
# Complex patterns #
####################

subtest 'Assertion sandwich: two position anchors surrounding match-anything' => sub {
	# Create two zero-width assertion patterns:
	$zwa_pat->{offset} = 4;
	my $at_ten = Scrooge::Test::OffsetZWA->new(name => 'at_ten', offset => 10);
	if(my %match_info = re_seq($zwa_pat, $all_pat, $at_ten)->match($data)) {
		is($match_info{length}, 6, 'length');
		is($match_info{left}, 4, 'offset');
		is($match_info{zwa}[0]{left}, 4, 'left zwa offset');
		is($match_info{all}[0]{left}, 4, "`all' offset");
		is($match_info{all}[0]{length}, 6, "`all' length");
		is($match_info{at_ten}[0]{left}, 10, 'at_ten offset');
	}
	else {
		fail('pattern did not match!');
	}
};

# Perform a match at three different segments with the same pattern and make
# sure it stores all three:
subtest 'Reusing patterns' => sub {
	my $at_ten = Scrooge::Test::OffsetZWA->new(name => 'at_ten', offset => 10);
	if(my %match_info
		= re_seq($all_pat, $zwa_pat, $all_pat, $at_ten, $all_pat)->match($data)
	) {
		is($match_info{length}, 20, 'full match length');
		is($match_info{left}, 0, 'full match offset');
		
		is($match_info{all}[0]{left}, 0, 'first all offset');
		is($match_info{all}[1]{left}, 4, 'second all offset');
		is($match_info{all}[2]{left}, 10, 'third all offset');
		
		is($match_info{all}[0]{length}, 4, 'first all length');
		is($match_info{all}[1]{length}, 6, 'second all length');
		is($match_info{all}[2]{length}, 10, 'third all length');
	}
	else {
		fail('sequence did not match');
	}
};

