use strict;
use warnings;
use Test::More tests => 10;
use PDL;
use Scrooge::PDL;

my $data = sequence(21) + 5;

##########################
# Range string tests: 10 #
##########################

sub do_check {
	my ($input, $expected, $output_string) = @_;
	if ($output_string) {
		$output_string .= " ($expected)";
	}
	else {
		$output_string = $expected;
	}
	is(Scrooge::PDL::parse_range_strings($data, $input), $expected
		, "parse_range_strings: '$input' => $output_string");
}

do_check(0           => 0);
do_check('100%'      => 25, 'the max');
do_check('10%'       => 7, 'the min plus 10%');
do_check('max - 10%' => 23);
do_check('min + 10%' => 7);
do_check('2 + 5'     => 7);
do_check('avg'       => avg($data), "the data's average");
do_check('1e-4%'     => 5 + 2e-5);

my ($avg, $st_dev) = $data->stats;
my $got = Scrooge::PDL::parse_range_strings($data, '1@');
ok(($avg + 0.99 * $st_dev < $got and $got < $avg + 1.01 * $st_dev),
	"parse_range_strings: '1\@' => mean + 1 st-dev = $got");
my $got = Scrooge::PDL::parse_range_strings($data, '5 - 2@');
ok((5 - 2.01 * $st_dev < $got and $got < 5 - 1.99 * $st_dev),
	"parse_range_strings: '5 - 2\@' => 5 - 2 * st-dev = $got");

