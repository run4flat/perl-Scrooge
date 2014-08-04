# Runs Basics' test

# Load the basics module:
my $module_name = 'Basics.pm';
if (-f $module_name) {
	require $module_name;
}
elsif (-f "t/$module_name") {
	require "t/$module_name";
}
elsif (-f "t\\$module_name") {
	require "t\\$module_name";
}

use strict;
use warnings;
use Scrooge;
use Test::More tests => 11;

my ($pattern, $length, $class, %match_info);
my $arr_len = 10;
my $array = [1..$arr_len];


#############################
# Scrooge::data_length test #
#############################

is(Scrooge::data_length($array), $arr_len,
	'Scrooge::data_length knows how to measure array lengths');


###############################
$class = 'Scrooge::Test::Fail';
###############################

subtest $class => sub {
	plan tests => 3;

	# Build
	$pattern = new_ok $class;

	# scalar context
	$length = $pattern->match($array);
	is($length, undef,
		'always fails, returning undef for length in scalar context');
	
	# list context
	%match_info = $pattern->match($array);
	is(scalar(keys %match_info), 0,
		'always fails, returning an empty list in list context');
};


#####################################
$class = 'Scrooge::Test::Fail::Prep';
#####################################

subtest $class => sub {
	plan tests => 3;
	
	# Build
	$pattern = new_ok $class;

	# scalar context
	$length = $pattern->match($array);
	is($length, undef,
		'always fails, returning undef for length in scalar context');
	
	# list context
	%match_info = $pattern->match($array);
	is(scalar(keys %match_info), 0,
		 'always fails, returning an empty list in list context');
};

##############################
$class = 'Scrooge::Test::All';
##############################

subtest $class => sub {
	plan tests => 5;
	
	# Build
	$pattern = new_ok $class;

	# scalar context
	$length = $pattern->match($array);
	is($length, $arr_len,
		'always matches all that it is given and reports the proper length in scalar context');

	# list context
	%match_info = $pattern->match($array);
	is($match_info{length}, $arr_len,
		'reports the proper match length in list context');
	is($match_info{left}, 0,
		'matches at the start of what it is given');
	is($match_info{right}, $arr_len - 1,
		'matches all the way to the end of what it is given');
};


################################
$class = 'Scrooge::Test::Croak';
################################

subtest $class => sub {
	plan tests => 2;
	
	# Build
	$pattern = new_ok $class;
	
	# Run it
	eval{$pattern->match($array)};
	isnt($@, '', 'Engine croaks when its pattern croaks');
};


######################################
$class = 'Scrooge::Test::ShouldCroak';
######################################

subtest $class => sub {
	plan tests => 2;
	
	# Build
	$pattern = new_ok $class;
	
	# Run
	eval{$pattern->match($array)};
	isnt($@, '', 'Engine croaks when pattern consumes more than it was given');
};


###############################
$class = 'Scrooge::Test::Even';
###############################

subtest $class => sub {
	plan tests => 7;
	
	# Build
	$pattern = new_ok $class;
	
	# Scalar context
	$length = $pattern->match($array);
	is($length, $arr_len, 'matches full length if it is even');
	$length = $pattern->match([1..$arr_len-1]);
	is($length, $arr_len - 2, 'matches the longest even length');
	$length = $pattern->match([1..$arr_len-2]);
	is($length, $arr_len - 2, 'matches the longest even length');
	$length = $pattern->match([1..$arr_len-3]);
	is($length, $arr_len - 4, 'matches the longest even length');
	
	# List context
	%match_info = $pattern->match($array);
	is($match_info{left}, 0, 'list context matches at the beginning');
	is($match_info{length}, $arr_len,
		'list context matches the full length');
};


##################################
$class = 'Scrooge::Test::Exactly';
##################################

subtest $class => sub {
	plan tests => 6;
	
	# Build
	$pattern = new_ok $class => [N => 8];
	
	# Simple run in scalar context
	$length = $pattern->match($array);
	is($length, 8, 'matches if N is two less than the data length');
	
	# Try different lengths near the edge of failure
	
	$pattern->{N} = 9;
	$length = $pattern->match($array);
	is($length, 9, 'matches if N is one less than the data length');
	
	$pattern->{N} = 10;
	$length = $pattern->match($array);
	is($length, 10, 'matches if N is the data length');
	
	$pattern->{N} = 11;
	$length = $pattern->match($array);
	is($length, undef, 'fails if N is one greater than the data length');
	
	$pattern->{N} = 12;
	$length = $pattern->match($array);
	is($length, undef, 'fails if N is two greater than the data length');
};


################################
$class = 'Scrooge::Test::Range';
################################

subtest $class => sub {
	plan tests => 10;
	
	# Build
	$pattern = new_ok $class;
	
	# Check defaults
	is($pattern->{min_size}, 1, 'Default min_size is 1');
	is($pattern->{max_size}, 1, 'Default max_size is 1');
	
	# Max length tests
	$length = $pattern->match($array);
	is($length, 1, 'matches the maximum possible specified number of elements');
	
	$pattern->{max_size} = 5;
	$length = $pattern->match($array);
	is($length, 5,
		'matches the maximum possible specified number of elements, even if greater than min_size');
	
	$pattern->{max_size} = 12;
	%match_info = $pattern->match($array);
	is($match_info{length}, 10,
		'matches the maximum possible specified number of elements, even if less than max_size');
	is($match_info{left}, 0, 'matches at the beginning');
	
	# Min length tests
	$pattern->{min_size} = 10;
	$length = $pattern->match($array);
	is($length, 10,
		'matches the maximum possible specified number of elements, even when min is the full length');
	
	$pattern->{min_size} = 11;
	$length = eval{ $pattern->match($array) };
	is($@, '', 'failed match does not throw an exception');
	is($length, undef, 'fails if data is smaller than min');
};


##########################################
$class = 'Scrooge::Test::Exactly::Offset';
##########################################

subtest $class => sub {
	plan tests => 11;
	
	# Build, check defaults
	$pattern = new_ok $class;
	is($pattern->{N}, 1, 'default size is 1');
	is($pattern->{offset}, 0, 'default offset is 0');
	
	# Compare with Test::Exactly
	my $exact_pattern = Scrooge::Test::Exactly->new(N => 5);
	$pattern = Scrooge::Test::Exactly::Offset->new(N => 5);
	is_deeply({$exact_pattern->match($array)}, {$pattern->match($array)},
		, 'agrees with basic Scrooge::Test::Exactly when no offset');
	
	# Simple nonzero offsets
	$pattern->{offset} = 2;
	%match_info = $pattern->match($array);
	is($match_info{length}, 5, 'matches specified length');
	is($match_info{left}, 2, 'matches specified offset');
	
	# corner case:
	$pattern->{offset} = 5;
	%match_info = $pattern->match($array);
	is($match_info{length}, 5, 'matches when N + offset = data_length');
	is($match_info{left}, 5, 'correct offset when N + offset = data_length');
	
	# ---( Failing situations, 3 )---
	$pattern->{offset} = 6;
	%match_info = $pattern->match($array);
	is(scalar(keys %match_info), 0, 'fails when N + offset = data_length + 1');
	# make sure it doesn't croak if offset is too large
	$pattern->{offset} = 20;
	$length = eval{$pattern->match($array)};
	is($@, '', 'large offset does not cause death');
	is($length, undef, 'large offset does cause failure');
};


####################################
$class = 'Scrooge::Test::OffsetZWA';
####################################

subtest $class => sub {
	plan tests => 13;
	
	# Build, check defaults
	$pattern = new_ok $class;
	is($pattern->{offset}, 0, 'default offset is 0');
	
	# Simple zero offsets, scalar and list contexts
	$length = $pattern->match($array);
	is($length, '0 but true',
		'in scalar context, default matches with boolean true zero length');
	%match_info = $pattern->match($array);
	is($match_info{left}, 0,
		'in list context, default indicates a left position of zero');
	is($match_info{right}, -1,
		'in list context, default indicates a right position of -1');
	is($match_info{length}, 0,
		'in list context, default indicates a length of numeric zero');
	
	# Simple nonzero offsets
	$pattern->{offset} = 2;
	%match_info = $pattern->match($array);
	is($match_info{length}, 0, 'matches zero length for nonzero offset');
	is($match_info{left}, 2, 'matches specified offset');
	
	# corner cases:
	$pattern->{offset} = 9;
	%match_info = $pattern->match($array);
	is($match_info{length}, 0, 'zero length when offset = data_length - 1');
	is($match_info{left}, 9, 'correct offset when offset = data_length - 1');
	$pattern->{offset} = 10;
	%match_info = $pattern->match($array);
	is($match_info{length}, 0, 'zero length when offset = data_length');
	is($match_info{left}, 10, 'correct offset when offset = data_length');
	$pattern->{offset} = 11;
	%match_info = $pattern->match($array);
	is_deeply(\%match_info, {}, 'fails when offset = data_length + 1');
};
