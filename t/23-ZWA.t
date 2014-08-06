# Make sure that re_zwa works as advertised.
use strict;
use warnings;
use Test::More tests => 5;
use Scrooge;

my $data = [-10 .. 20];
my $arr_len = scalar(@$data);

##################################
# Basic subroutines for matching #
##################################

my $upward_zero_crossing = sub {
	# called with the match_info hash
	my ($match_info) = @_;
	
	# Check if "left" is *on* or just to the *right* of an upward zero crossing
	my $data = $match_info->{data};
	my $left = $match_info->{left};
	return 0 if $left == 0 or $left >= $match_info->{data_length};
	return '0 but true' if $data->[$left-1] < 0 and $data->[$left] >= 0;
	return 0;
};

subtest 'Explicit Constructor' => sub {
	my $explicit = new_ok 'Scrooge::ZWA', [position => 5];
	
	my %match_info = $explicit->match($data);
	is($match_info{length}, 0, 'length (0)');
	is($match_info{left}, 5, 'offset');
	
	$explicit = new_ok 'Scrooge::ZWA';
	%match_info = $explicit->match($data);
	is($match_info{length}, 0, 'length (0)');
	is($match_info{left}, 0, 'offset');
};

subtest 're_zwa_position, scalar position' => sub {
	my $simple = re_zwa_position(5);
	isa_ok($simple, 'Scrooge::ZWA');
	
	my %match_info = $simple->match($data);
	is($match_info{length}, 0, 'length (0)');
	is($match_info{left}, 5, 'offset');
	
	%match_info = re_zwa_position('[4 - 30%] + 5')->match($data);
	is($match_info{length}, 0, 'length (0)');
	is($match_info{left}, 5, 'offset');
};

subtest 're_zwa corner cases' => sub {
	my $pattern = re_zwa_position(-1);
	my %match_info = $pattern->match($data);
	is($match_info{left}, undef, 'position of -1 is inadmissable')
		or diag explain \%match_info;
	
	$pattern = re_zwa_position(0);
	%match_info = $pattern->match($data);
	is($match_info{left}, 0, 'position of 0 matches')
		or diag explain \%match_info;
	
	$pattern = re_zwa_position(1);
	%match_info = $pattern->match($data);
	is($match_info{left}, 1, 'position of 1 matches')
		or diag explain \%match_info;
	
	$pattern = re_zwa_position($arr_len - 1);
	%match_info = $pattern->match($data);
	is($match_info{left}, $arr_len - 1, 'position of data length less one matches')
		or diag explain \%match_info;
	
	$pattern = re_zwa_position('100% - 1');
	%match_info = $pattern->match($data);
	is($match_info{left}, $arr_len - 1, "position of `100% - 1' matches")
		or diag explain \%match_info;
	
	$pattern = re_zwa_position($arr_len);
	%match_info = $pattern->match($data);
	is($match_info{left}, $arr_len, 'position of full data length matches')
		or diag explain \%match_info;
	
	$pattern = re_zwa_position('100%');
	%match_info = $pattern->match($data);
	is($match_info{left}, $arr_len, "position of `100%' matches")
		or diag explain \%match_info;
	
	$pattern = re_zwa_position($arr_len + 1);
	%match_info = $pattern->match($data);
	is($match_info{left}, undef, 'position of data length plus one fails')
		or diag explain \%match_info;
	
	$pattern = re_zwa_position('100% + 1');
	%match_info = $pattern->match($data);
	is($match_info{left}, undef, "position `100% + 1' fails")
		or diag explain \%match_info;
};

subtest 're_zwa_sub, nontrivial match function' => sub {
	my %match_info = re_zwa_sub($upward_zero_crossing)->match($data);
	is($match_info{length}, 0, 'length (0)');
	is($match_info{left}, 10, 'offset');
	
	%match_info = re_zwa_sub(4, $upward_zero_crossing)->match($data);
	is_deeply(\%match_info, {}, 'fails due to incommensurate position');
	
	%match_info = re_zwa_sub([5, 15], $upward_zero_crossing)->match($data);
	is($match_info{length}, 0, 'length (0)');
	is($match_info{left}, 10, 'offset');
};

subtest 're_zwa_sub corner cases' => sub {
	my $length = re_zwa_sub([9 => 11], $upward_zero_crossing)->match($data);
	is($length, '0 but true', 'range squarely around correct location');
	
	$length = re_zwa_sub([8 => 10], $upward_zero_crossing)->match($data);
	is($length, '0 but true', 'range just barely includes correct location');
	
	$length = re_zwa_sub([10 => 12], $upward_zero_crossing)->match($data);
	is($length, '0 but true', 'range just barely includes correct location');
	
	$length = re_zwa_sub([7 => 9], $upward_zero_crossing)->match($data);
	is($length, undef, 'range does not include correct location');
	
	$length = re_zwa_sub([11 => 13], $upward_zero_crossing)->match($data);
	is($length, undef, 'range does not include correct location');
};
