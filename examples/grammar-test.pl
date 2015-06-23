use strict;
use warnings;

package Test::Grammar;
use Scrooge;
use Scrooge::Grammar;

SEQ TOP => qw(numbers letters numbers);
SEQ numbers => re_sub [0 => '100%'], sub {
	my $match_info = shift;
	my $data = $match_info->{data};
	my $left = $match_info->{left};
	print "Looking for numbers from $left to $match_info->{right}\n";
	my $i;
	for ($i = $left; $i <= $match_info->{right}; $i++) {
		last if $data->[$i] !~ /^\d+$/;
	}
	$i--;
	return $i - $left + 1;
};

SEQ letters => re_sub [0 => '100%'], sub {
	my $match_info = shift;
	my $data = $match_info->{data};
	my $left = $match_info->{left};
	print "Looking for letters from $left to $match_info->{right}\n";
	my $i;
	for ($i = $left; $i <= $match_info->{right}; $i++) {
		last if $data->[$i] !~ /^[a-zA-Z]+$/;
	}
	$i--;
	return $i - $left + 1;
};

package main;
my @data = qw(1 2 3 a b c 4 5 6);
if (Test::Grammar->match(\@data)) {
	print "matched grammar!\n";
}

if (Test::Grammar->numbers->match(\@data)){
	print "matched numbers!\n";
}
