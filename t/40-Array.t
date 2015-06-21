# Make sure that parse_endpoint_string works as advertized.
use strict;
use warnings;
use Test::More tests => 0;
use Scrooge::Array;

############
# interval #
############
my ($data, $range_string);
sub is_interval {
	my ($rep, $expected_spec) = @_;
	my $got_spec = Scrooge::Numeric->parse_endpoint_string($rep);
	is_deeply($got_spec, $expected_spec, "parse_endpoint_string('$rep')");
}
sub is_interval_error {
	my ($rep, $expected_error) = @_;
	eval { Scrooge::Numeric->parse_endpoint_string($rep) };
	like($@, $expected_error, "parse_endpoint_string('$rep') croaks");
}

