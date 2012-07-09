# Tests the Tracker module, which is used in a handful of test suites.

# Load the tracker module:
my $module_name = 'Tracker.pm';
if (-f $module_name) {
	require $module_name;
}
elsif (-f "t/$module_name") {
	require "t/$module_name";
}
elsif (-f "t\\$module_name") {
	require "t\\$module_name";
}
else {
	die "Unable to load $module_name";
}

use strict;
use warnings;
use Test::More tests => 18;

# Create a mock Regex::Engine class for testing the Tracker:
package Regex::Engine;

my $hello_is_run = 0;
sub hello {
	$hello_is_run++;
}

sub run_hello {
	$_[0]->hello;
}

sub call_many {
	$_[0]->hello;
	$_[0]->run_hello;
	$_[0]->hello;
}

sub untracked {
	$_[0]->run_hello;
}

###########################################################################
#                 Regex::Engine::Test::Tracker::Basic - 8                    #
###########################################################################

package Regex::Engine::Test::Tracker::Basic;
our @ISA = 'Regex::Engine';
Tracker::track(qw(run_hello hello call_many));
my $self = bless [], __PACKAGE__;


# A function that does not call anything else
our @call_structure = ();
$self->hello();
my $expected = [ hello => [] ];
is_deeply(\@call_structure, $expected, 'Calling hello is properly tracked')
	or diag(Dumper(\@call_structure));
is($hello_is_run, 1, 'Calling the derived function also calls the parent function');

# A function that calls another function:
@call_structure = ();
$self->run_hello;
$expected = [
	run_hello => [ hello => [] ]
];
is_deeply(\@call_structure, $expected, 'Calling run_hello is properly tracked')
	or diag(Dumper(\@call_structure));
is($hello_is_run, 2, 'Everything is properly executed');

# A function that calls many other functions:
@call_structure = ();
$self->call_many;
$expected = [
	call_many => [
		hello => [],
		run_hello => [ hello => [] ],
		hello => [],
	]
];
is_deeply(\@call_structure, $expected, 'Calling call_many is properly tracked')
	or diag(Dumper(\@call_structure));
is($hello_is_run, 5, 'Everything is properly executed');

# An untracked function:
@call_structure = ();
$self->untracked;
$expected = [
	run_hello => [ hello => [] ],
];
is_deeply(\@call_structure, $expected, 'Calling untracked does not track untracked')
	or diag(Dumper(\@call_structure));
is($hello_is_run, 6, 'Everything is properly executed');


##########################################################################
#                Regex::Engine::Test::Tracker::Subref - 3                   #
##########################################################################

package Regex::Engine::Test::Tracker::Subref;
our @ISA = 'Regex::Engine';
Tracker::track({hello => 'our $test_val++'}, qw(run_hello call_many));
$self = bless [], __PACKAGE__;

our @call_structure = ();
$self->call_many;
$expected = [
	call_many => [
		hello => [],
		run_hello => [ hello => [] ],
		hello => [],
	]
];
is_deeply(\@call_structure, $expected, 'Calling call_many is properly tracked even with overrides')
	or diag(Dumper(\@call_structure));
is(our $test_val, 3, 'Override code is run');
is($hello_is_run, 6, 'Overriding hello means original function is not actually called');

###########################################################################
#                 Regex::Engine::Test::Tracker::Croak - 4                    #
###########################################################################

package Regex::Engine::Test::Tracker::Croak;
our @ISA = 'Regex::Engine';
Tracker::track({hello => 'die "test"'}, qw(run_hello call_many));
$self = bless [], __PACKAGE__;

our @call_structure = ();
eval{$self->hello};
isnt($@, '', 'Croaks propogate');
$expected = [ -hello => [] ];
is_deeply(\@call_structure, $expected, 'Simple croaks are properly tracked')
	or diag(Dumper(\@call_structure));

@call_structure = ();
eval{$self->call_many};
isnt($@, '', 'Croaks propogate');
$expected = [
	-call_many => [
		-hello => [],
	]
];
is_deeply(\@call_structure, $expected, 'Embedded croaks are properly tracked')
	or diag(Dumper(\@call_structure));


###########################################################################
#                Regex::Engine::Test::Tracker::Context - 3                   #
###########################################################################

my $context;
sub Regex::Engine::context {
	if(wantarray) {
		$context = 'list';
	}
	elsif (defined wantarray) {
		$context = 'scalar';
	}
	else {
		$context = 'void';
	}
}

package Regex::Engine::Test::Tracker::Context;
our @ISA = 'Regex::Engine';
Tracker::track(qw(context));
$self = bless [], __PACKAGE__;

my ($ignore) = $self->context;
is($context, 'list', 'List context is correctly propogated');

$ignore = $self->context;
is($context, 'scalar', 'Scalar context is correctly propogated');

$self->context;
is($context, 'void', 'Void context is correctly propogated');
