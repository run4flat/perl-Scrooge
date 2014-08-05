# Make sure that re_zwa works as advertised.
use strict;
use warnings;
use Test::More tests => 1;
use Scrooge;

my $data = [-10 .. 20];

##################################
# Basic subroutines for matching #
##################################

my $upward_zero_crossing = sub {
	# called with the match_info hash
	my ($match_info) = @_;
	
	# Check if we are just *past* an upward zero crossing
	my $data = $match_info->{data};
	my $left = $match_info->{left};
	return 0 if $left == 0 or $left >= $match_info->{data_length};
	return '0 but true' if $data->[$left-1] < 0 and $data->[$left] > 0;
	return 0;
};

subtest 'Explicit Constructor' => sub {
	my $explicit = new_ok 'Scrooge::ZWA', [position => 5];
	
	my %match_info = $explicit->match($data);
	is($match_info{length}, 0, 'length');
	is($match_info{left}, 5, 'offset');
};

__END__
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
