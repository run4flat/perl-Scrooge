use strict;
use warnings;
use Test::More tests => 45;
use PDL;
use Scrooge::PDL;

##########################
# Range string tests: 10 #
##########################

my $data = sequence(21) + 5;
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
$got = Scrooge::PDL::parse_range_strings($data, '5 - 2@');
ok((5 - 2.01 * $st_dev < $got and $got < 5 - 1.99 * $st_dev),
	"parse_range_strings: '5 - 2\@' => 5 - 2 * st-dev = $got");

########################
# Constructor tests: 3 #
########################

my $two_to_five = eval{re_range(name => 'test regex', above => '2', below => '5')};
is($@, '', 'Basic constructor does not croak');
isa_ok($two_to_five, 'Scrooge::PDL::Range');
is($two_to_five->{name}, 'test regex', 'Constructor correctly interprets name');

#########################
# Basic Match Tests: 20 #
#########################
$data = pdl(-3, 4, 5, 9);
my ($matched, $offset) = $two_to_five->apply($data);
isnt($matched, undef, 'two_to_five matched against (-3, 4, 5, 9)');
is($matched, 1, 'default quantifier is a single match');
is($offset, 1, 'identifies the first matching element');

$data = pdl(7, 8, 9);
($matched, $offset) = $two_to_five->apply($data);
is($matched, undef, 'two_to_five could not match piddle (7, 8, 9)');

$data = sin(sequence(100)/10);
$data->slice('37') .= 100;

$two_to_five = eval{re_range(name=>'test regex',above => 2, below => 1000)};
($matched, $offset) = $two_to_five->apply($data);
isnt($matched, undef, 'two_to_five matched against piddle');
is($matched, 1, 'default quantifier is a single match');
is($offset, 37, 'identifies the first matching element');


$two_to_five = eval{re_range(name => 'test regex', above => 'avg + 2@', below => 1000)};
($matched, $offset) = $two_to_five->apply($data);
isnt($matched, undef, 'two_to_five matched piddle');
is($matched, 1, 'default quantifier is a single match');
is($offset, 37, 'identifies first matching element');

$two_to_five = eval{re_range(name => 'test regex', above => 2, below => 'avg + 10@')};
($matched, $offset) = $two_to_five->apply($data);
isnt($matched, undef, 'two_to_fve matched piddle');
is($matched, 1, 'default quantifier is a single match');
is($offset, 37, 'identifies first matching element');

$two_to_five = eval{re_range(name => 'test regex', above => 'avg - 3@', below => 'avg - 2@')};
($matched, $offset) = $two_to_five->apply($data);
is($matched, undef, 'two_to_five could not match piddle');

$two_to_five = eval{re_range(name => 'test regex', above => -1, below => 200)};
($matched, $offset) = $two_to_five->apply($data);
isnt($matched, undef, 'two_to_five matched piddle');
is($matched, 1, 'default quantifier is a single match');
is($offset, 0, 'identifies first matching element');

$data->slice('9') .= -10;

$two_to_five = eval{re_range(name => 'test regex', above => 'avg - 10@', below => 'avg - 1@')};
($matched, $offset) = $two_to_five->apply($data);
isnt($matched, undef, 'two_to_five matched piddle');
is($matched, 1, 'default quantifier is a single match');
is($offset, 9, 'identifies first matching element');

#############################
# Quantified Match Tests: 12 #
#############################

$data->slice('10') .= -11;
$data->slice('11') .= -12;

$two_to_five = eval{re_range(name => 'test regex', above => 'avg - 15@', below => 'avg - 1@', quantifiers => [1,3])};
($matched, $offset) = $two_to_five->apply($data);
isnt($matched, undef, 'two_to_five matched piddle');
is($matched, 3, 'matched a segment of lentgth 3');
is($offset, 9, 'identifies first matching value');


$data = sin(sequence(100)/10);
$two_to_five = re_range(name => 'test regex', above => -1, below => 1, quantifiers => [1,100]);
($matched, $offset) = $two_to_five->apply($data);
isnt($matched, undef, 'two_to_five matched piddle');
is($matched, 100, 'whole segment matched');
is($offset, 0, 'identifies first matching element');


$two_to_five = re_range(name => 'test regex', above => -1, below => 1, quantifiers => [1, 200]);
($matched, $offset) = $two_to_five->apply($data);
isnt($matched, undef, 'two_to_five matched piddle');
is($matched, 100, 'whole segment matched');
is($offset, 0, 'identifies first matching element');

$two_to_five = re_range(name => 'test regex', above => -1, below => 1, quantifiers => [50, 200]);
($matched, $offset) = $two_to_five->apply($data);
isnt($matched, undef, 'two_to_five matched piddle');
is($matched, 100, 'whole segment matched');
is($offset, 0, 'identifies first matching element');