# Make sure that re_sub works as advertised.
use strict;
use warnings;
use Test::More tests => 4;
use Scrooge;

my $data = [-10 .. 20];

##################################
# Basic subroutines for matching #
##################################

my $match_all_subref = sub {
	my ($match_info) = @_;
	# Match all values:
	return $match_info->{length};
};

my $match_positive = sub {
	# called with the match_info hash
	my ($match_info) = @_;
	
	# Find the number of positive elements starting from left
	my $data = $match_info->{data};
	my ($left, $length) = ($match_info->{left}, $match_info->{length});
	for (my $i = 0; $i < $length; $i++) {
		# If this offset is zero, then the previous entry was the last
		# positive number. The length of that sequence is equal to this
		# offset, $i.
		return $i if $data->[$i + $left] <= 0;
	}
	return $length;
};


subtest 'Explicit Constructor' => sub {
	my $explicit = new_ok 'Scrooge::Sub',
		[quantifiers => [1,1], subref => $match_all_subref];
	
	my %match_info = $explicit->match($data);
	is($match_info{length}, 1, 'length');
	is($match_info{left}, 0, 'offset');
};

subtest 're_sub, no quantifiers' => sub {
	my $simple = eval {re_sub($match_all_subref)};
	is($@, '', 're_sub does not croak');
	isa_ok($simple, 'Scrooge::Sub');
	
	my %match_info = $simple->match($data);
	is($match_info{length}, 1, 'length');
	is($match_info{left}, 0, 'offset');
};

subtest 're_sub, quantifiers, nontrivial match function' => sub {
	my $pattern = re_sub([1 => '100%'], $match_positive);
	
	my %match_info = $pattern->match($data);
	is($match_info{length}, 20, 'length');
	is($match_info{left}, 11, 'offset');
};

subtest 're_sub, impossible quantifiers, nontrivial match function' => sub {
	my $pattern = re_sub([21 => '100%'], $match_positive);
	
	my %match_info = $pattern->match($data);
	is_deeply(\%match_info, {}, 'fails due to quantifiers');
};
