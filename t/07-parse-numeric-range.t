# Make sure that parse_endpoint_string works as advertized.
use strict;
use warnings;
use Test::More tests => 9;
use Scrooge::Numeric;

############
# endpoint #
############
sub is_parse_endpoint {
	my ($rep, $expected_spec) = @_;
	my $got_spec = Scrooge::Numeric->parse_endpoint_string($rep);
	is_deeply($got_spec, $expected_spec, "parse_endpoint_string('$rep')");
}
sub is_parse_endpoint_error {
	my ($rep, $expected_error) = @_;
	eval { Scrooge::Numeric->parse_endpoint_string($rep) };
	like($@, $expected_error, "parse_endpoint_string('$rep') croaks");
}

subtest 'parse_endpoint single terms' => sub {
	is_parse_endpoint(5 => {raw => 5});
	is_parse_endpoint('-5.4e-3' => { raw => -5.4e-3 });
	is_parse_endpoint($_ => {$_ => 1}) for (qw(m M x X @ inf));
	is_parse_endpoint("-$_" => {$_ => -1}) for (qw(m M x X @ inf));
	is_parse_endpoint('13.2%' => {pct => 13.2});
	is_parse_endpoint('2.1$' => {stdev => 2.1});
	is_parse_endpoint('$' => {stdev => 1});
};

subtest 'parse_endpoint multiple terms' => sub {
	is_parse_endpoint('5 + 4' => {raw => 9});
	is_parse_endpoint('@-$' => {'@' => 1, stdev => -1});
	is_parse_endpoint('m + 10% - 2$' => {m => 1, pct => 10, stdev => -2});
	is_parse_endpoint('M-1' => {M => 1, raw => -1});
};

subtest 'parse_endpoint croaking behavior' => sub {
	is_parse_endpoint_error('3.54e -5' => qr/Unable to parse/);
	is_parse_endpoint_error('2m' => qr/Cannot use `m' as a suffix/);
	is_parse_endpoint_error('5 + 4 +' => qr/Found trailing `\+'/);
	is_parse_endpoint_error('3inf' => qr/Cannot use `inf' as a suffix/);
	is_parse_endpoint_error('foo' => qr/Unable to parse/);
	is_parse_endpoint_error('10%5' => qr/Operator expected/);
	is_parse_endpoint_error('10%foo' => qr/Operator expected/);
	is_parse_endpoint_error('3-%' => qr/Unable to parse/);
	is_parse_endpoint_error('3@' => qr/Cannot use `\@' as a suffix/);
	is_parse_endpoint_error('e4 + 7' => qr/Unable to parse/);
};

############
# interval #
############

sub is_parse_interval {
	my ($rep, $expected_spec) = @_;
	my $got_spec = Scrooge::Numeric->parse_interval_string($rep);
	is_deeply($got_spec, $expected_spec, "parse_interval_string('$rep')");
}
sub is_parse_interval_error {
	my ($rep, $expected_error) = @_;
	eval { Scrooge::Numeric->parse_interval_string($rep) };
	if (defined $rep) {
		$rep = "'$rep'";
	}
	else {
		$rep = 'undef';
	}
	like($@, $expected_error, "parse_endpoint_string($rep) croaks");
}

subtest 'parse_interval croaking' => sub {
	is_parse_interval_error(undef, qr/No interval string/);
};

subtest 'parse_interval behavior' => sub {
	is_parse_interval('(3,5)' => {
		left_delim  => '(',
		right_delim => ')',
		left_spec   => { raw => 3 },
		right_spec  => { raw => 5 },
	});
	is_parse_interval('[1e-5,inf-1)' => {
		left_delim  => '[',
		right_delim => ')',
		left_spec   => { raw => 1e-5 },
		right_spec  => { raw => -1, inf => 1 },
	});
};

#####################
# evaluate_endpoint #
#####################

my $props = {
	x => 1, m => 10, '@' => 100, M => 1000, X => 10_000, stdev => 100_000
};
sub is_eval_endpoint {
	my ($endpoint, $expected, $description) = @_;
	my $endpoint_hash = ref($endpoint) ? $endpoint
		: Scrooge::Numeric->parse_endpoint_string($endpoint);
	my $got = Scrooge::Numeric->evaluate_endpoint($endpoint_hash, $props);
	is ($got, $expected, $description);
}

sub is_eval_endpoint_error {
	my ($endpoint, $expected_error, $description) = @_;
	my $endpoint_hash = ref($endpoint) ? $endpoint
		: Scrooge::Numeric->parse_endpoint_string($endpoint);
	eval { Scrooge::Numeric->evaluate_endpoint($endpoint_hash, $props) };
	like($@, $expected_error, $description);
}

subtest 'evaluate_endpoint' => sub {
	# Create a set of properties that are senseless, but easy to analyze
	is_eval_endpoint({inf => 1, foobar => 1}, 'inf', 'inf overrides other properties');
	is_eval_endpoint('20', 20, 'raw numbers');
	is_eval_endpoint('x+X+m+M+@+2$', 211111, 'basic arithmetic with systematic properties');
	is_eval_endpoint('10%', 99, 'percentages');
	is_eval_endpoint('-210+x+X+m+M+@+2$+10%', 211000, 'all together now');
};

subtest 'evaluate_endpoint croaking' => sub {
	$props = { };
	is_eval_endpoint('20', 20, 'Missing properties are ok if not used in endpoint');
	my %regex_for_key = (
		x => qr/minimum.*possibly/,
		X => qr/maximum.*possibly/,
		m => qr/minimum.*not/,
		M => qr/maximum.*not/,
		'@' => qr/average/,
		'$' => qr/standard deviation/,
		'10%' => qr/min and max, but m and M/,
	);
	while(my ($k, $regex) = each %regex_for_key) {
		is_eval_endpoint_error($k, qr/endpoint needs.*$regex/,
			"craoks if $k is used but corresponding dataset property is not given");
	}
	is_eval_endpoint_error({foo => 1}, qr/Invalid key/, 'croaks on invalid endpoint keys');
};

###############################
# build_interval_check_subref #
###############################

my ($interval);
sub is_builder {
	my ($left, $right, $value_to_check, $bool) = @_;
	my $interval = Scrooge::Numeric->parse_interval_string("$left, $right");
	my $sub = Scrooge::Numeric->build_interval_check_subref($interval, {});
	is(0 + $sub->($value_to_check), $bool,
		(defined $value_to_check ? $value_to_check : '<undef>')
			. " is " . ($bool ? '' : 'not ') . "in interval $left, $right");
}

subtest 'build_interval_check_subref' => sub {
	is_builder('[-1' => '1]', 0 => 1);
	is_builder('[-1' => '1]', -1 => 1);
	is_builder('[-1' => '1]', 1 => 1);
	is_builder('[-1' => '1]', -5 => 0);
	is_builder('[-1' => '1]', 5 => 0);
	
	is_builder('(-1' => '1]', 0 => 1);
	is_builder('(-1' => '1]', -1 => 0);
	is_builder('(-1' => '1]', 1 => 1);
	is_builder('(-1' => '1]', -5 => 0);
	is_builder('(-1' => '1]', 5 => 0);
	
	is_builder('[-1' => '1)', 0 => 1);
	is_builder('[-1' => '1)', -1 => 1);
	is_builder('[-1' => '1)', 1 => 0);
	is_builder('[-1' => '1)', -5 => 0);
	is_builder('[-1' => '1)', 5 => 0);
	
	is_builder('(-1' => '1)', 0 => 1);
	is_builder('(-1' => '1)', -1 => 0);
	is_builder('(-1' => '1)', 1 => 0);
	is_builder('(-1' => '1)', -5 => 0);
	is_builder('(-1' => '1)', 5 => 0);
	
	# non-numbers
	is_builder('(-1' => '1)', a => 0);
	is_builder('(-1' => '1)', undef, 0);
	
	# Infinity
	is_builder('[-inf' => '1]', 0 => 1);
	is_builder('[-inf' => '1]', 1 => 1);
	is_builder('[-inf' => '1]', '-inf' => 1);
	is_builder('[-inf' => '1]', 10 => 0);
	is_builder('[1' => 'inf]', 'inf' => 1);
	is_builder('[1' => 'inf]', 5 => 1);
	is_builder('[1' => 'inf)', 'inf' => 0);
};

sub is_builder_error {
	my ($interval, $expected_error, $description) = @_;
	eval { Scrooge::Numeric->build_interval_check_subref($interval, $props) };
	like($@, $expected_error, $description);
}

subtest 'build_interval_check_subref croaking behavior' => sub {
	for my $k (qw(left_delim left_spec right_delim right_spec)) {
		my $interval = Scrooge::Numeric->parse_interval_string("[-1, 1]");
		delete $interval->{$k};
		is_builder_error($interval, qr/interval does not contain $k/,
			"Missing $k");
	}
	for my $k (qw(left right)) {
		my $interval = Scrooge::Numeric->parse_interval_string("[-1, 1]");
		$interval->{$k . '_delim'} = 'foo';
		is_builder_error($interval, qr/interval has bad $k delimiter/,
			"Bad $k delimiter");
	}
	for my $k (qw(left right)) {
		my $interval = Scrooge::Numeric->parse_interval_string("[-1, 1]");
		$interval->{$k . '_spec'} = 'foo';
		is_builder_error($interval, qr/$k spec of interval is not a hashref/,
			"Bad $k spec");
	}
};

