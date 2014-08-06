# Make sure that parse_repeat works as advertized.
use strict;
use warnings;
use Test::More tests => 4;
use Scrooge;

#####################
# Testing functions #
#####################
sub is_parse_repeat {
	my ($stringy_rep, $expected_min, $expected_max) = @_;
	
	# Make sure the stringy rep parses
	no warnings 'uninitialized';
	my $rep = eval "+$stringy_rep";
	use warnings 'uninitialized';
	$@ eq '' or die "Malformed stringy_rep `$stringy_rep'\n";
	
	# Run the test
	my @results = eval { Scrooge::Repeat->parse_repeat($rep) };
	if (@results) {
		my ($got_min, $got_max) = @results;
		is($got_min, $expected_min, "min for parse_position `$stringy_rep'");
		is($got_max, $expected_max, "max for parse_position `$stringy_rep'");
	}
	else {
		fail("Got unexpected parse error `$@' while parsing `$stringy_rep'");
	};
}
sub is_parse_error {
	my ($stringy_rep, $expected_error) = @_;
	
	# Make sure the stringy rep parses
	no warnings 'uninitialized';
	my $rep = eval "+$stringy_rep";
	use warnings 'uninitialized';
	$@ eq '' or die "Malformed stringy_rep `$stringy_rep'\n";
	
	# Run the test
	eval { Scrooge::Repeat->parse_repeat($rep) };
	like($@, $expected_error, "parse_position `$stringy_rep' croaks");
}

#########
# Tests #
#########

subtest 'Scalar inputs' => sub {
	# Good inputs
	is_parse_repeat("undef", 0 => undef);
	is_parse_repeat("'*'", 0 => undef);
	is_parse_repeat("'+'", 1 => undef);
	is_parse_repeat("5", 5 => 5);
	is_parse_repeat("',5'", 0 => 5);
	is_parse_repeat("',0'", 0 => 0);
	is_parse_repeat("'5,'", 5 => undef);
	is_parse_repeat("'0,'", 0 => undef);
	is_parse_repeat("','", 0 => undef);
	
	# Croaking inputs
	is_parse_error("5.1", qr/Unable to parse scalar repeat/);
	is_parse_error("'foo'", qr/Unable to parse scalar repeat/);
};

subtest 'Hashref inputs' => sub {
	is_parse_repeat("{1 => 5}", 1 => 5);
	is_parse_repeat("{5,5}", 5 => 5);
	is_parse_repeat("{1.4 => 5.7}", 1 => 5);
	is_parse_repeat("{1 => undef}", 1 => undef);
	
	# Croaking inputs
	is_parse_error("{abc => 1}", qr/Repeat must be a number/);
	is_parse_error("{1 => -5}", qr/Repeat must be non-negative/);
	is_parse_error("{undef => 5}", qr/Repeat must be a number/);
	is_parse_error("{undef, 5}", qr/Repeat must be a number/);
	is_parse_error("{1=>2, 3=>4}", qr/Hashref repeats must have a single key\/value pair/);
	is_parse_error("{}", qr/Hashref repeats must have a single key\/value pair/);
};

subtest 'Arrayref inputs' => sub {
	is_parse_repeat("[1 => 5]", 1 => 5);
	is_parse_repeat("[1.3 => 2.9]", 1 => 2);
	is_parse_repeat("[4 => undef]", 4 => undef);
	is_parse_repeat("[undef, undef]", 0 => undef);
	
	# Croaking inputs
	is_parse_error("[undef => 5]", qr/Repeat must be a number/);
	is_parse_error("[]", qr/Arrayref repeats must contain two elements/);
	is_parse_error("[4]", qr/Arrayref repeats must contain two elements/);
	is_parse_error("[4,]", qr/Arrayref repeats must contain two elements/);
	is_parse_error("[1 .. 3]", qr/Arrayref repeats must contain two elements/);
};

subtest 'Other inputs' => sub {
	is_parse_error("sub {}", qr/Scrooge::Repeat::parse_repeat does not know how to parse/);
	is_parse_error("qr//", qr/Scrooge::Repeat::parse_repeat does not know how to parse/);
};