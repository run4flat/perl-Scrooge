use strict;
use warnings;
use Test::More tests => 8;
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
my $zwa = Scrooge::Test::OffsetZWA->new(name => 'zwa');

#####################
# Constructor tests #
#####################

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
};

####################
# Croaking pattern #
####################

subtest 'Croaking patterns' => sub {
	my $pattern = eval{re_or($should_croak)};
	is($@, '', 'Constructor without name does not croak');
	isa_ok($pattern, 'Scrooge::Or');
	eval{$pattern->match($data)};
	isnt($@, '', 'croaks when one of the patterns consumes too much');
	
	eval{re_or($croak, $all)->match($data)};
	isnt($@, '', 'croaks when one of its constituents croaks even if a later one would pass');
	
	eval{re_or($all, $croak)->match($data)};
	is($@, '', 'short-circuits on the first success');
	
	eval{re_or($fail, $croak)->match($data)};
	isnt($@, '', 'does not short-circuit unless it actually encounters success');
};

##################
# Simple pattern #
##################

subtest 'Wrapping re_or around a single pattern' => sub {
	my @keys_to_compare = qw(left right length);
	for my $pattern ($fail, $all, $even, $exact, $range, $offset, $zwa) {
		my %got = re_or($pattern)->match($data);
		%got = map {$_ => $got{$_}} @keys_to_compare;
		my %expected = $pattern->match($data);
		%expected = map {$_ => $expected{$_}} @keys_to_compare;
		is_deeply(\%got, \%expected,
			'does not alter behavior of ' . $pattern->{name} . ' pattern');
	}
};

###################
# Failing pattern #
###################

$exact->{N} = 25;
$offset->{offset} = 30;
my $length = re_or($fail, $exact, $offset)->match($data);
is($length, undef, 'Agglomeration of failed patterns');

####################
# Complex patterns #
####################

subtest 're_or for two patterns that will fail and one that will succeed' => sub {
	$offset->{offset} = 4;
	$offset->{N} = 8;
	my %match_info = re_or($fail, $exact, $offset)->match($data);
	is($match_info{length}, 8, 'length');
	is($match_info{left}, 4, 'offset');
	ok(not (exists $match_info{fail}), 'No info stored under fail name key')
		or diag explain \%match_info;
	ok(not (exists $match_info{exact}), 'No info stored under exact name key')
		or diag explain \%match_info;
	ok(exists ($match_info{offset}), 'Info stored under offset name key')
		or diag explain \%match_info;
};

subtest 're_or for many patterns that match' => sub {
	$exact->{N} = 15;
	my %match_info = re_or($fail, $exact, $even, $range)->match($data);
	if(ok(exists($match_info{exact}), 'matches against the Exact pattern')) {
		is($match_info{left}, 0, 'offset');
		is($match_info{exact}[0]{left}, 0, 'subpattern offset via name');
		is($match_info{positive_matches}[0]{left}, 0,
			'subpattern offset via positive_matches');
		is($match_info{length}, 15, 'length');
		is($match_info{exact}[0]{length}, 15, 'subpattern length via name');
		is($match_info{positive_matches}[0]{length}, 15,
			'subpattern length via positive_matches');
	}
	else {
		diag explain \%match_info;
	}
	ok(not (exists $match_info{fail}), 'No match info for fail')
		or diag explain \%match_info;
	ok(not (exists $match_info{even}), 'No match info for even')
		or diag explain \%match_info;
	ok(not (exists $match_info{range}), 'No match info for range')
		or diag explain \%match_info;
};

subtest 're_or where zero-width-assertion should win' => sub {
	$offset->{offset} = 5;
	$zwa->{offset} = 3;
	my %match_info = re_or($fail, $zwa, $offset)->match($data);
	if(ok(exists($match_info{zwa}), 'matches against the zwa pattern')) {
		is($match_info{left}, 3, 'offset');
		is($match_info{length}, 0, 'length');
	}
	else {
		diag explain \%match_info;
	}
	ok(not (exists $match_info{fail}), 'No match info for fail')
		or diag explain \%match_info;
	ok(not (exists $match_info{offset}), 'No match info for offset')
		or diag explain \%match_info;
};

subtest 're_or for many patterns that match' => sub {
	my %match_info = re_or($even, $exact, $range)->match($data);
	if(ok(exists($match_info{even}), 'matches against the even pattern')) {
		is($match_info{left}, 0, 'offset');
		is($match_info{even}[0]{left}, 0, 'subpattern offset via name');
		is($match_info{positive_matches}[0]{left}, 0,
			'subpattern offset via positive_matches');
		is($match_info{length}, 20, 'length');
		is($match_info{even}[0]{length}, 20, 'subpattern length via name');
		is($match_info{positive_matches}[0]{length}, 20,
			'subpattern length via positive_matches');
	}
	else {
		diag explain \%match_info;
	}
	ok(not (exists $match_info{exact}), 'No match info for exact')
		or diag explain \%match_info;
	ok(not (exists $match_info{range}), 'No match info for range')
		or diag explain \%match_info;
};

