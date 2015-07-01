# Tests the functionality of Scrooge::Array::This
use strict;
use warnings;
use Test::More tests => 5;
use Scrooge::Array;

###################
# Non-array input #
###################

subtest 'Array vs Non-array input' => sub {
	my $pattern = Scrooge::Array::This->new(
		this_subref => sub { 1 },
		quantifiers => [1, '100%'],
	);
	my $data = { a => 1, b => 2, c => 3};
	ok(!$pattern->match($data), "Silently fails on hash input");
	ok(!$pattern->match('data'), "Silently fails on string input");
	$data = [ 1, 2, 3];
	is(scalar($pattern->match($data)), 3, "Correctly works on array input");
};

subtest 'this_subref correctly scopes $_' => sub {
	local $_ = -1;
	my $pattern = Scrooge::Array::This->new(
		this_subref => sub { $_ == 5 },
		quantifiers => [1, '100%'],
	);
	my %match_info = $pattern->match([3, 4, 5]);
	is ($_, -1, 'Does not mess up $_');
	if (exists $match_info{left}) {
		is($match_info{left}, 2, 'Correct offset');
		is($match_info{length}, 1, 'Correct length');
		is($match_info{right}, 2, 'Correct end offset');
	}
	else {
		fail('Correctly identifies a successful match');
	}
};

subtest 'Caching and non-caching agree' => sub {
	my $cached_pattern = Scrooge::Array::This->new(
		this_subref => sub { $_ == 5 },
		this_cached => 1,
		quantifiers => [1, '100%'],
	);
	my $regular_pattern = Scrooge::Array::This->new(
		this_subref => sub { $_ == 5 },
		quantifiers => [1, '100%'],
	);
	my $data = [1, 3, 5, 3, 5];
	my %cached_info = $cached_pattern->match($data);
	my %regular_info = $regular_pattern->match($data);
	if (exists $cached_info{left} and exists $regular_info{left}) {
		is($regular_info{left}, 2, 'non-caching matches at correct position');
		is($cached_info{left}, 2, 'caching matches at correct position');
		is($regular_info{length}, 1, 'non-caching matches correct length');
		is($cached_info{length}, 1, 'caching matches correct length');
		is($regular_info{right}, 2, 'non-caching matches correct end-offset');
		is($cached_info{right}, 2, 'caching matches correct end-offset');
	}
	else {
		fail('Correctly matches on both');
	}
};

subtest 'Minimal caching' => sub {
	# A pattern that can match up to everything
	my $cached_pattern = Scrooge::Array::This->new(
		this_subref => sub { $_ == 5 },
		this_cached => 1,
		quantifiers => [1, '100%'],
	);
	my $data = [1, 3, 5, 3, 5];
	my %cached_info = $cached_pattern->match($data);
	if (exists $cached_info{left}) {
		is_deeply($cached_info{this_cache}, [0, 0, 1, 0],
			'Goes only one step beyond, if necessary')
				or diag explain $cached_info{this_cache};
	}
	else {
		fail('Correctly matches');
	}
	
	# A pattern that only matches the first occurence
	$cached_pattern = Scrooge::Array::This->new(
		this_subref => sub { $_ == 5 },
		this_cached => 1,
		quantifiers => [1, 1],
	);
	%cached_info = $cached_pattern->match($data);
	if (exists $cached_info{left}) {
		is_deeply($cached_info{this_cache}, [0, 0, -1],
			'Does not go one step beyond if not necessary')
				or diag explain $cached_info{this_cache};
	}
	else {
		fail('Correctly matches');
	}
};

subtest 'Supports zero-width matches' => sub {
	my $pattern = Scrooge::Array::This->new(
		this_subref => sub { $_ == 5 },
		quantifiers => [0, '100%'],
	);
	my %match_info = $pattern->match([3, 4, 6]);
	if (exists $match_info{left}) {
		is($match_info{left}, 0, 'Correct offset');
		is($match_info{length}, 0, 'Correct length');
		is($match_info{right}, -1, 'Correct end offset');
	}
	else {
		fail('Correctly identifies a successful match');
	}
};
