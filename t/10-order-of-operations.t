# The documentation guarantees the order of operations for certain functions
# as well as guaranteeing that certain functions will not be called if
# prep returns zero. This checks those guarantees by creating test pattern
# classes that track the behavior.

use strict;
use warnings;
use Test::More tests => 6;
use Scrooge;
use Data::Dumper;

# Load the tracker module:
if (-f 'Tracker.pm') {
	require 'Tracker.pm';
	require 'Basics.pm';
}
elsif (-f 't/Tracker.pm') {
	require 't/Tracker.pm';
	require 't/Basics.pm';
}
elsif (-f 't\Tracker.pm') {
	require 't\Tracker.pm';
	require 't\Basics.pm';
}
else {
	die "Unable to find (and therefore load) Tracker.pm and Basics.pm";
}


####################################
package Scrooge::Test::Tracker::New;
####################################
@Scrooge::Test::Tracker::New::ISA = ('Scrooge');
use Test::More;
Tracker::track({apply => '1', prep => '1', init => '1', cleanup => '1'},
	qw(new match clear_stored_match)
);

subtest __PACKAGE__, sub {
	# Build
	my $pattern = new_ok (__PACKAGE__);

	# The call order for new should look like this:
	my $expected = [
		new => [
			init => [],
		],
	];
	our @call_structure;
	is_deeply(\@call_structure, $expected, 'New calls init');
};


#########################################
package Scrooge::Test::Tracker::Override;
#########################################
# This makes it very easy to change the behavior of the pattern: I simply
# change the subref associated with the packge variable.
use Test::More;
@Scrooge::Test::Tracker::Override::ISA = ('Scrooge');
Tracker::track(
	{
		apply    => q{ our $apply_returns->() },
		cleanup  => q{ our $cleanup_returns->() },
		prep     => q{ our $prep_returns->() },
		init     => q{ $self->{min_size} = 1; $self->{max_size} = 1 },
	},
	qw(new match clear_stored_match)
);

our $prep_returns = sub {1};
our $apply_returns = sub {1};
our $cleanup_returns = sub {1};
my $pattern = Scrooge::Test::Tracker::Override->new;
my $data = [1 .. 50];


##################################
my $test_name = 'Successful Prep';
##################################

subtest $test_name => sub {
	plan tests => 3;
	
	# Clear out the call structure
	our @call_structure = ();
	
	$@ = '';
	my $length = eval{$pattern->match($data)};
	is($@, '', 'does not croak on simple pattern');
	is($length, 1, 'matched length agrees with min/max size (1)');
	
	# For the basic application, the call order should look like this:
	my $expected = [
		match => [
			prep			=> [],
			apply			=> [],
			cleanup			=> [],
		]
	];
	
	is_deeply(\@call_structure, $expected, 'Basic call order agrees with expectations');
};


###########################
$test_name = 'Failed Prep';
###########################

subtest $test_name => sub {
	plan tests => 3;
	
	our @call_structure = ();
	$prep_returns = sub {0};
	my $expected = [
		match => [
			prep			=> [],
			cleanup			=> [],
		]
	];

	my $length = eval{$pattern->match($data)};
	is($@, '', 'pattern does not croak');
	is($length, undef, 'matched length is not defined');
	is_deeply(\@call_structure, $expected,
		'function call order agrees with expectations')
		or diag(Dumper(\@call_structure));
};


#############################
$test_name = 'Croaking Prep';
#############################
# Note: croaking functions are notated with a dash

do {
	our @call_structure = ();
	$prep_returns = sub {die 'test'};
	my $expected = [
		-match => [
			-prep			=> [],
			cleanup			=> [],
		]
	];

	eval{$pattern->match($data)};
	is_deeply(\@call_structure, $expected, 'cleanup follows croaking prep')
		or diag(Dumper(\@call_structure));
	
	# Reset the prep function so it does not die
	$prep_returns = sub {1};
};


##############################
$test_name = 'Croaking Apply';
##############################

do {
	our @call_structure = ();
	$apply_returns = sub {die 'test'};
	my $expected = [
		-match => [
			prep    => [],
			-apply  => [],
			cleanup => [],
		]
	];

	eval{$pattern->match($data)};
	is_deeply(\@call_structure, $expected, 'cleanup follows croaking apply')
		or diag(Dumper(\@call_structure));
	
	# Reset the apply function so it works as expected
	$apply_returns = sub {1};
};

################################
$test_name = 'Croaking Cleanup';
################################

do {
	our @call_structure = ();
	$cleanup_returns = sub { die 'test' };
	my $expected = [
		-match => [
			prep     => [],
			apply    => [],
			-cleanup => [],
		]
	];

	eval{$pattern->match($data)};
	is_deeply(\@call_structure, $expected, 'croaking cleanup... croaks')
		or diag(Dumper(\@call_structure));

	$cleanup_returns = sub {1};
}
