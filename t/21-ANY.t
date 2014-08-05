# Make sure that re_any works as advertised. Includes some minor tests for
# quantifiers, but those were tested in 05-parse-position.t
use strict;
use warnings;
use Test::More tests => 7;
use Scrooge;

my $arr_len = 20;
my $data = [1 .. 20];

# Check that the explicit constructor works:
subtest 'Explicit constructor' => sub {
	plan tests => 3;
	
	my $explicit = new_ok 'Scrooge::Quantified' => [quantifiers => [1,1]];
	my %match_info = $explicit->match($data);
	is($match_info{length}, 1, 'length of match');
	is($match_info{left}, 0, 'offset');
};

# ---( Simple Constructor, No Quantifiers: 3 )---

# Make sure the simple constructor works and uses quantifiers [1,1]
subtest 're_any without arguments' => sub {
	plan tests => 4;
	
	my $simple = eval {re_any()};
	is($@, '', 're_any does not croak');
	isa_ok($simple, 'Scrooge::Quantified');
	my %match_info = $simple->match($data);
	is($match_info{length}, 1, 'default length is 1');
	is($match_info{left}, 0, 'offset');
};

# ---( Simple Constructor, quantifiers: N )---

sub test_re_any {
	my %test_params = @_;
	my $simple = eval {re_any([$test_params{min}, $test_params{max}])};
	is($@, '', "re_any([$test_params{min}, $test_params{max}]) does not croak")
		or return;
	isa_ok($simple, 'Scrooge::Quantified') or return;
	
	# Match
	my $length = $simple->match($data);
	my $expected = $test_params{expected_length};
	if (defined $expected) {
		is($length, $expected, "matches the expected length ($expected)");
	}
	else {
		is($length, undef, "fails to match (as expected)");
	}
}

sub test_set_re_any {
	my ($description, @tests) = @_;
	subtest $description => sub {
		plan tests => 3 * @tests;
		test_re_any %$_ foreach (@tests);
	};
}

# Good handling of quantifiers, including larger-than 100%, less than
# 0%, too large, too small, etc

test_set_re_any 're_any with positive integer quantifiers' => 
	{ min => 0,  max => 10, expected_length => 10 },
	{ min => 5,  max => 5, expected_length => 5 },
	{ min => 5,  max => 12, expected_length => 12 },
	{ min => 0,  max => 25, expected_length => 20 },
	{ min => 21, max => 30, expected_length => undef },
	;

test_set_re_any 're_any with positive integer quantifiers, corner cases' => 
	{ min => 0,  max => 19, expected_length => 19 },
	{ min => 0,  max => 20, expected_length => 20 },
	{ min => 0,  max => 21, expected_length => 20 },
	{ min => 19, max => 25, expected_length => 20 },
	{ min => 20, max => 25, expected_length => 20 },
	{ min => 21, max => 25, expected_length => undef },
	;

test_set_re_any 're_any with (dumb) negative integer quantifiers' => 
	{ min => 0,   max => -5, expected_length => undef },
	{ min => -15, max => 20, expected_length => 20 },
	{ min => -15, max => -2, expected_length => undef },
	;

test_set_re_any 're_any with percentage quantifiers' => 
	{ min => 0,      max => '50%', expected_length => 10 },
	{ min => '25%',  max => '90%', expected_length => 18 },
	{ min => '-25%', max => '75%', expected_length => 15 },
	;

test_set_re_any 're_any with min > max' => 
	{ min => 15, max => 10,  expected_length => undef },
	{ min => 25, max => -5,  expected_length => undef },
	{ min => 0,  max => -25, expected_length => undef },
	;
