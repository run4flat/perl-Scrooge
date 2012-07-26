# The documentation guarantees the order of operations for certain functions
# as well as guaranteeing that certain functions will not be called if
# _prep returns zero. This checks those guarantees by creating test regex
# classes that track the behavior.

use PDL;
use strict;
use warnings;
use Test::More tests => 15;
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


#######################################################################
#                        Constructor Tests - 2                        #
#######################################################################

package Scrooge::Test::Tracker::New;
our @ISA = ('Scrooge');
Tracker::track({_apply => '1', _prep => '1', _init => '1', _cleanup => '1'},
	qw(new _to_stash apply is_prepping prep min_size max_size is_applying
			store_match clear_stored_match is_cleaning cleanup)
);

my $regex = Scrooge::Test::Tracker::New->new();
# Ensure the class was properly created:
isa_ok($regex, 'Scrooge::Test::Tracker::New')
	or diag($regex);

# The call order for new should look like this:
my $expected = [
	new => [
		_init => [],
	],
];
our @call_structure;
is_deeply(\@call_structure, $expected, 'New calls _init');

#######################################################################
#                         Successful Prep - 4                         #
#######################################################################

package Scrooge::Test::Tracker::Override;
our @ISA = ('Scrooge');
Tracker::track(
	{
		_apply		=> q{ our $apply_returns->() },
		_cleanup	=> q{ our $cleanup_returns -> () },
		_prep		=> q{ our $prep_returns->() },
		_init		=> q{ $self->min_size(1); $self->max_size(1) },
	},
	qw(new _to_stash apply is_prepping prep is_applying min_size max_size
			store_match clear_stored_match is_cleaning cleanup)
);

our $prep_returns = sub {1};
our $apply_returns = sub {1};
our $cleanup_returns = sub {1};

$regex = Scrooge::Test::Tracker::Override->new;
our @call_structure = ();

my $data = sequence(50);
$@ = '';
my ($length, $offset) = eval{$regex->apply($data)};
is($@, '', 'Regex does not croak on simple regex');
is($length, 1, 'Matched length should be 1');
is($offset, 0, 'Matched offset should be 0');

# For the basic application ($regex->{data} not defined), the call order
# should look like this:
$expected = [
	apply => [
		is_prepping		=> [],
		prep			=> [ _prep => [] ],
		is_applying		=> [],
		min_size		=> [],
		max_size		=> [],
		_apply			=> [],
		store_match		=> [],
		is_cleaning		=> [],
		cleanup			=> [ _cleanup => [] ],
	]
];


is_deeply(\@call_structure, $expected, 'Basic call order agrees with expectations');

#######################################################################
#                           Failed Prep - 4                           #
#######################################################################

@call_structure = ();
$prep_returns = sub {0};
$expected = [
	apply => [
		is_prepping		=> [],
		prep			=> [ _prep => [] ],
		is_cleaning		=> [],
		cleanup			=> [ _cleanup => [] ],
	]
];

($length, $offset) = eval{$regex->apply($data)};
is($@, '', 'Regex does not croak on failed prep');
is($length, undef, 'Matched length should be undef for failed prep');
is($offset, undef, 'Matched offset should be undef for failed prep');

is_deeply(\@call_structure, $expected, 'Failed prep agrees with expectations')
	or diag(Dumper(\@call_structure));

#######################################################################
#                          Croaking Prep - 1                          #
#######################################################################

# Note: croaking functions are notated in ALL CAPS

@call_structure = ();
$prep_returns = sub {die 'test'};
$expected = [
	-apply => [
		is_prepping		=> [],
		-prep			=> [ -_prep => [] ],
		is_cleaning		=> [],
		cleanup			=> [ _cleanup => [] ],
	]
];

eval{$regex->apply($data)};
is_deeply(\@call_structure, $expected, 'Croaking prep agrees with expectations')
	or diag(Dumper(\@call_structure));

$prep_returns = sub {1};

########################################################################
#                          Croaking Apply - 1                          #
########################################################################

@call_structure = ();
$apply_returns = sub {die 'test'};
$expected = [
	-apply => [
		is_prepping		=> [],
		prep			=> [ _prep => [] ],
		is_applying		=> [],
		min_size		=> [],
		max_size		=> [],
		-_apply			=> [],
		is_cleaning		=> [],
		cleanup			=> [ _cleanup => [] ],
	]
];

eval{$regex->apply($data)};
is_deeply(\@call_structure, $expected, 'Croaking apply agrees with expectations')
	or diag(Dumper(\@call_structure));

$apply_returns = sub {1};

########################################################################
#                         Croaking Cleanup - 1                         #
########################################################################

@call_structure = ();
$cleanup_returns = sub { die 'test' };
$expected = [
	-apply => [
		is_prepping		=> [],
		prep			=> [ _prep => [] ],
		is_applying		=> [],
		min_size		=> [],
		max_size		=> [],
		_apply			=> [],
		store_match		=> [],
		is_cleaning		=> [],
		-cleanup			=> [ -_cleanup => [] ],
	]
];

eval{$regex->apply($data)};
is_deeply(\@call_structure, $expected, 'Croaking cleanup agrees with expectations')
	or diag(Dumper(\@call_structure));

$cleanup_returns = sub {1};

#########################################################################
#                     Croaking Prep and Cleanup - 1                     #
#########################################################################

@call_structure = ();
$cleanup_returns = sub { die 'test' };
$prep_returns = sub {die 'test'};
$expected = [
	-apply => [
		is_prepping		=> [],
		-prep			=> [ -_prep => [] ],
		is_cleaning		=> [],
		-cleanup			=> [ -_cleanup => [] ],
	]
];

eval{$regex->apply($data)};
is_deeply(\@call_structure, $expected, 'Croaking prep and cleanup agrees with expectations')
	or diag(Dumper(\@call_structure));

$cleanup_returns = sub {1};
$prep_returns = sub {1};

########################################################################
#                    Croaking Apply and Cleanup - 1                    #
########################################################################

@call_structure = ();
$apply_returns = sub { die 'test' };
$cleanup_returns = sub { die 'test' };
$expected = [
	-apply => [
		is_prepping		=> [],
		prep			=> [ _prep => [] ],
		is_applying		=> [],
		min_size		=> [],
		max_size		=> [],
		-_apply			=> [],
		is_cleaning		=> [],
		-cleanup			=> [ -_cleanup => [] ],
	]
];

eval{$regex->apply($data)};
is_deeply(\@call_structure, $expected, 'Croaking apply and cleanup agrees with expectations')
	or diag(Dumper(\@call_structure));

$apply_returns = sub { 1 };
$cleanup_returns = sub { 1 };
