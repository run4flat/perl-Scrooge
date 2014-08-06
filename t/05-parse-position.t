# Make sure that parse_position works as advertized.
use strict;
use warnings;
use Test::More tests => 7;
use Scrooge;

# Utility function to make the testing more concise
sub is_parse_position {
	my ($max_index, $to_parse, $expected) = @_;
	my $got = Scrooge::parse_position($max_index, $to_parse);
	is($got, $expected, "parse_position $max_index, $to_parse");
}

sub is_parse_error {
	my ($to_parse, $expected_error) = @_;
	eval { Scrooge::parse_position(1, $to_parse) };
	like($@, $expected_error, "parsing `$to_parse' croaks, as expected");
}


subtest 'Numbers' => sub {
	is_parse_position(0, 5, 5);
	is_parse_position(10, 5, 5);
	is_parse_position(0, 8, 8);
	is_parse_position(10, 8, 8);
	is_parse_position(0, 12, 12);
	is_parse_position(10, 12, 12);
	is_parse_position(0, -5, -5);
	is_parse_position(10, -5, -5);
	is_parse_position(0, -8, -8);
	is_parse_position(10, -8, -8);
	is_parse_position(0, -12, -12);
	is_parse_position(10, -12, -12);
};

subtest 'Percentages' => sub {
	is_parse_position(0, '10%', 0);
	is_parse_position(10, '10%', 1);
	is_parse_position(0, '120%', 0);
	is_parse_position(10, '120%', 12);
	is_parse_position(0, '-10%', 0);
	is_parse_position(10, '-10%', -1);
	is_parse_position(0, '-120%', 0);
	is_parse_position(10, '-120%', -12);
};

subtest 'Bare Truncation' => sub {
	is_parse_position(0, '[5]', 0);
	is_parse_position(10, '[5]', 5);
	is_parse_position(10, '[15]', 10);
	is_parse_position(0, '[-5]', 0);
	is_parse_position(10, '[-5]', 0);
	is_parse_position(10, '[-8]', 0);
	is_parse_position(10, '[-12]', 0);
	is_parse_position(0, '[10%]', 0);
	is_parse_position(10, '[10%]', 1);
	is_parse_position(10, '[-10%]', 0);
	is_parse_position(10, '[110%]', 10);
	is_parse_position(10, '[-110%]', 0);
};

subtest 'Multiple integers' => sub {
	is_parse_position(0, '5 + 3', 8);
	is_parse_position(10, '5 + 3', 8);
	is_parse_position(10, '3 - 5', -2);
	is_parse_position(10, '5 - 3', 2);
	is_parse_position(10, '-3 + 5', 2);
	is_parse_position(10, '-5 + 3', -2);
};

subtest 'Combinations' => sub {
	is_parse_position(0, '5 + 30%', 5);
	is_parse_position(10, '5 + 30%', 8);
	is_parse_position(10, '-2 + 30%', 1);
	is_parse_position(10, '[20] - 4 + 30%', 9);
	is_parse_position(0, '[20] - 4 + 30%', -4);
};

subtest 'Complex truncations' => sub {
	is_parse_position(0, '[20 - 30%]', 0);
	is_parse_position(10, '[20 - 30%]', 10);
	is_parse_position(10, '[1 - 30%]', 0);
	is_parse_position(0, '[-4 + 30%]', 0);
	is_parse_position(10, '[-4 + 30%]', 0);
	is_parse_position(10, '[-4 - 30%]', 0);
	is_parse_position(10, '[-6 - 50%]', 0);
	is_parse_position(10, '[-3 + 40%]', 1);
	
	# position at 30%, or 5, which ever is greater
	is_parse_position(3, '[30% - 5] + 5', 5);
	is_parse_position(10, '[30% - 5] + 5', 5);
	is_parse_position(100, '[30% - 5] + 5', 30);
	# position at 70% or -5, which ever is smaller
	is_parse_position(3, '[70% + 5] - 5', -2);
	is_parse_position(10, '[70% + 5] - 5', 5);
	is_parse_position(100, '[70% + 5] - 5', 70);
	
	# same as above, but truncated
	is_parse_position(3, '[[30% - 5] + 5]', 3);
	is_parse_position(10, '[[30% - 5] + 5]', 5);
	is_parse_position(100, '[[30% - 5] + 5]', 30);
	is_parse_position(3, '[[70% + 5] - 5]', 0);
	is_parse_position(10, '[[70% + 5] - 5]', 5);
	is_parse_position(100, '[[70% + 5] - 5]', 70);
};

subtest 'Error handling' => sub {
	is_parse_error('abc', qr/Invalid position string/);
	is_parse_error('1+', qr/Invalid position string/);
	is_parse_error('[1', qr/Did not find closing bracket/);
	is_parse_error('[[1] + 1', qr/Did not find closing bracket/);
	is_parse_error('1 2', qr/Found whitespace/);
	is_parse_error('20% 5', qr/Found whitespace/);
};
