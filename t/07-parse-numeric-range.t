# Make sure that parse_range_string works as advertized.
use strict;
use warnings;
use Test::More tests => 6;
use Scrooge::Numeric;

#####################
# Testing functions #
#####################
sub is_parse_range {
	my ($rep, $expected_spec) = @_;
	my $got_spec = Scrooge::Numeric->parse_range_string($rep);
	is_deeply($got_spec, $expected_spec, $rep);
}
sub is_parse_range_error {
	my ($rep, $expected_error) = @_;
	eval { Scrooge::Numeric->parse_range_string($rep) };
	like($@, $expected_error, "parse_range_string('$rep') croaks");
}
sub is_parse_pair {
	my ($rep, $expected_spec) = @_;
	my $got_spec = Scrooge::Numeric->parse_range_string_pair($rep);
	is_deeply($got_spec, $expected_spec, $rep);
}
sub is_parse_pair_error {
	my ($rep, $expected_error) = @_;
	eval { Scrooge::Numeric->parse_range_string_pair($rep) };
	if (defined $rep) {
		$rep = "'$rep'";
	}
	else {
		$rep = 'undef';
	}
	like($@, $expected_error, "parse_range_string($rep) croaks");
}

#########
# Tests #
#########

subtest 'parse_range single terms' => sub {
	is_parse_range(5 => {raw => 5});
	is_parse_range('-5.4e-3' => { raw => -5.4e-3 });
	is_parse_range($_ => {$_ => 1}) for (qw(m M x X @ inf));
	is_parse_range("-$_" => {$_ => -1}) for (qw(m M x X @ inf));
	is_parse_range('13.2%' => {pct => 13.2});
	is_parse_range('2.1$' => {stdev => 2.1});
	is_parse_range('$' => {stdev => 1});
};

subtest 'parse_range multiple terms' => sub {
	is_parse_range('5 + 4' => {raw => 9});
	is_parse_range('@-$' => {'@' => 1, stdev => -1});
	is_parse_range('m + 10% - 2$' => {m => 1, pct => 10, stdev => -2});
	is_parse_range('M-1' => {M => 1, raw => -1});
};

subtest 'parse_range maybe should fail, but do not' => sub {
	is_parse_range('3.54e -5' => { raw => 3.54e-5});
};

subtest 'parse_range croaking behavior' => sub {
	is_parse_range_error('2m' => qr/In range string/);
	is_parse_range_error('5 + 4 +' => qr/Unable to parse/);
	is_parse_range_error('3inf' => qr/In range string/);
	is_parse_range_error('foo' => qr/Unable to parse/);
	is_parse_range_error('10%foo' => qr/In range string/);
	is_parse_range_error('3-%' => qr/Unable to parse/);
	is_parse_range_error('3@' => qr/In range string/);
	is_parse_range_error('e4 + 7' => qr/Unable to parse/);
};

subtest 'parse_pair croaking' => sub {
	is_parse_pair_error(undef, qr/No range string/);
};

subtest 'parse_pair behavior' => sub {
	is_parse_pair('(3,5)' => {
		left_delim  => '(',
		right_delim => ')',
		left_spec   => { raw => 3 },
		right_spec  => { raw => 5 },
	});
	is_parse_pair('[1e-5,inf-1)' => {
		left_delim  => '[',
		right_delim => ')',
		left_spec   => { raw => 1e-5 },
		right_spec  => { raw => -1, inf => 1 },
	});
};

