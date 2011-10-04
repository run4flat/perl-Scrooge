# The documentation guarantees the order of operations for certain functions
# as well as guaranteeing that certain functions will not be called if
# _prep returns zero. This checks those guarantees by creating test regex
# classes that track the behavior.

use blib;
use PDL;
use strict;
use warnings;
use Test::More tests => 24;
use blib;
use PDL::Regex;

######################
# NRE::Test::Tracker #
######################

# This builds a small test class that tracks the order of functions and
# allows for easy changes to the return value of _prep. The functions that
# have been called are added to the @has_been_called list, which is
# initially empty. You should clear it between applications of the regex:
my @has_been_called = ();
# The return value of prep is whatever is stored in this variable:
my $prep_returns = 1;

package NRE::Test::Tracker;
our @ISA = qw(NRE);
use strict;
use warnings;

# Match anything:
sub _apply { push @has_been_called, '_apply'; 1 }
# Track apply
sub apply { push @has_been_called, 'apply'; $_[0]->SUPER::apply($_[1]) }
# Track _prep and have _prep return a value of our choosing:
sub _prep {
	push @has_been_called, '_prep';
	my ($self, $piddle) = @_;
	$self->SUPER::_prep($piddle);
	return $prep_returns;
}
# Provide rudimentary _min_size and _max_size functions:
sub _min_size { push @has_been_called, '_min_size'; 1 }
sub _max_size { push @has_been_called, '_max_size'; 1 }
# Track _cleanup and _store_match:
sub _cleanup { push @has_been_called, '_cleanup'; $_[0]->SUPER::_cleanup }
sub _store_match {
	push @has_been_called, '_store_match';
	my ($self, @args) = @_;
	return $self->SUPER::_store_match(@args);
}

package main;

#######################################################################
#                   Constructor/Execution Tests - 5                   #
#######################################################################

# Builds the regex and makes sure it runs:

my $regex = NRE::Test::Tracker->_new();
# Ensure the class was properly created:
isa_ok($regex, 'NRE::Test::Tracker');
# Make sure new doesn't call any of the tracked functions:
ok(@has_been_called == 0, 'Default constructor has not called anything');
my $data = sequence(10);
$@ = '';
my ($length, $offset) = eval{$regex->apply($data)};
is($@, '', 'Regex does not croak');
is($length, 1, 'Matched length should be 1');
is($offset, 0, 'Matched offset should be 0');

#######################################################################
#                         Successful Prep - 6                         #
#######################################################################

# Associate each function with its call-order index:
my %ran = map {$_ => 1} @has_been_called;

ok($ran{_prep}, 'Successful prep: _prep should run');
ok($ran{_apply}, 'Successful prep: _apply should run');
ok($ran{_min_size}, 'Successful prep: _min_size should run');
ok($ran{_max_size}, 'Successful prep: _min_size should run');
ok($ran{_cleanup}, 'Successful prep: _cleanup should run');
ok($ran{_store_match}, 'Successful prep: _store_match should run');

########################################################################
#                       Basic Ordering Tests - 4                       #
########################################################################

# Associate each function with its call-order index:
my %placement = map {$has_been_called[$_] => $_} 0..$#has_been_called;

ok($placement{apply} < $placement{_prep}, 'apply is initiated before _prep');
ok($placement{_prep} < $placement{_min_size}, '_prep is initiated before _min_size');
ok($placement{_prep} < $placement{_max_size}, '_prep is initiated before _max_size');
ok($placement{_min_size} < $placement{_apply}, '_min_size is initiated before _apply');

#######################################################################
#                           Failed Prep - 9                           #
#######################################################################

# make the regex fail on _prep and clear the called list:
$prep_returns = 0;
@has_been_called = ();

$@ = '';
($length, $offset) = eval{ $regex->apply($data) };
is($@, '', 'Failed prep does not croak');
is($length, undef, 'Failed match returns undefined length');
is($offset, undef, 'Failed match returns undefined offset');

# Tabulate whether each function ran or not:
%ran = map {$_ => 1} @has_been_called;

ok($ran{_prep}, 'Failed prep: _prep should run');
is($ran{_apply}, undef, 'Failed prep: _apply should not run');
is($ran{_min_size}, undef, 'Failed prep: _min_size should not run');
is($ran{_max_size}, undef, 'Failed prep: _min_size should not run');
ok($ran{_cleanup}, 'Failed prep: _cleanup should run');
is($ran{_store_match}, undef, 'Failed prep: _store_match should not run');
