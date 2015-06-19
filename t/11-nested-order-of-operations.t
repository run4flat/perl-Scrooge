use strict;
use warnings;
use Test::More tests => 8;
use Scrooge;
use Data::Dumper;

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

my $data = [1 .. 50];

#############################################################
#                           Setup                           #
#############################################################

# I want to use a slightly more complex set of functions, so I'm going to
# have the overridable functions call even more local functions. :-)

package Scrooge::Test::Tracker::Nested;
@Scrooge::Test::Tracker::Nested::ISA = ('Scrooge');
Tracker::track(
	{
		apply    => q{ our $apply_returns->() },
		cleanup  => q{ our $cleanup_returns -> () },
		prep     => q{ our $_prep_returns->($self, @_) },
	}, qw(match)
);
our $_prep_returns = sub {
	my ($self, $match_info) = @_;
	return 0 unless $self->Scrooge::prep($match_info);
	return our $prep_returns->()
};

sub init {
	my $self = shift;
	$self->{min_size} = 1;
	$self->{max_size} = 1;
	$self->SUPER::init;
}

my $pattern = __PACKAGE__->new;
our @call_structure = ();
our $apply_returns = sub {1};
our $cleanup_returns = sub {1};
our $prep_returns = sub {1};

my $prep_counter = 0;
my $prep_pattern_length = 0;
my $single_recursive_prep = sub {
	# Alter the state data
	my $max_size = int rand(scalar(@$data));
	local $pattern->{min_size} = int rand($max_size);
	local $pattern->{max_size} = $max_size;
	
	# Only one level of recursion here:
	return 1 if $prep_counter++;
	
	# If we are at the top level, call self:
	$prep_pattern_length = $pattern->match($data);
	return 1;
};
$prep_returns = $single_recursive_prep;
my @N_to_return;
$apply_returns = sub {
	# Returns a random number of elements:
	my $min = $pattern->{min_size};
	my $max = $pattern->{max_size};
	push @N_to_return, int(rand($max - $min)) + $min;
	return $N_to_return[-1];
};

###################################################################
#                           Nested Prep                           #
###################################################################

my $expected = [
	match => [
		prep => [
			match => [
				prep    => [],
				apply   => [],
				cleanup => [],
			],
		],
		apply   => [],
		cleanup => [],
	]
];

@call_structure = ();
my $length = eval{$pattern->match($data)};
is_deeply(\@call_structure, $expected, 'Nested prep works fine')
	or diag(Dumper (\@call_structure));

$prep_returns = sub {1};

########################################################################
#                           Nested Apply - 3                           #
########################################################################

@N_to_return = ();
my $apply_counter = 0;
$pattern->{min_size} = 1;
$pattern->{max_size} = 40;
my $internal_pattern_length = -1;
$apply_returns = sub {
	# Only one level of recursion here:
	if ($apply_counter++ == 0) {
		$internal_pattern_length = $pattern->match($data);
	}
	
	# Returns a random number of elements:
	my $min = $pattern->{min_size};
	my $max = $pattern->{max_size};
	push @N_to_return, int(rand($max - $min)) + $min;
	return $N_to_return[-1];
};

$expected = [
	match => [
		prep  => [],
		apply => [
			match => [
				prep    => [],
				apply   => [],
				cleanup => [],
			],
		],
		cleanup => [],
	]
];

@call_structure = ();
$length = $pattern->match($data);
is($length, $N_to_return[-1], 'Nesting does not mess up final length');
is($internal_pattern_length, $N_to_return[0], 'Nesting does not mess up initial length');
is_deeply(\@call_structure, $expected, 'Nested apply agrees with expectations')
	or diag(Dumper (\@call_structure));

$apply_returns = sub {1};

########################################################################
#                          Nested Cleanup - 3                          #
########################################################################

my $cleanup_counter = 0;
my $cleanup_length;
$cleanup_returns = sub {
	# Only one level of recursion here:
	return if $cleanup_counter++;
	
	# If not, match this pattern to the data!
	$cleanup_length = $pattern->match($data);
	return;
};

$apply_returns = sub {
	# Returns a random number of elements:
	my $min = $pattern->{min_size};
	my $max = $pattern->{max_size};
	push @N_to_return, int(rand($max - $min)) + $min;
	return $N_to_return[-1];
};


$expected = [
	match => [
		prep    => [],
		apply   => [],
		cleanup => [
			match => [
				prep    => [],
				apply   => [],
				cleanup => [],
			],
		],
	]
];

@N_to_return = ();
@call_structure = ();
$length = eval{$pattern->match($data)};
is($length, $N_to_return[0],
	'Nested cleanup did not mess up top-level return value');
is($cleanup_length, $N_to_return[1],
	'Nested cleanup did not mess up nested return value');
is_deeply(\@call_structure, $expected, 'Nested cleanup executes fine')
	or diag(Dumper (\@call_structure));

$apply_returns = sub {1};

########################################################################
#                 Nested Apply with croaking Apply - 1                 #
########################################################################

$apply_counter = 0;
$apply_returns = sub {
	if ($apply_counter++ == 0) {
		my $result = $pattern->match($data);
		return $result;
	}
	die 'test';
};

$expected = [
	-match => [
		prep  => [],
		-apply => [
			-match => [
				prep    => [],
				-apply  => [],
				cleanup => [],
			],
		],
		cleanup => [],
	]
];

@call_structure = ();
eval{$pattern->match($data)};
is_deeply(\@call_structure, $expected, 'Nested apply with croaking apply performs full cleanup')
	or diag(Dumper (\@call_structure));

$apply_returns = sub {1};
