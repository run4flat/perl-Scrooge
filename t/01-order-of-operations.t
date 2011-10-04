# The documentation guarantees the order of operations for certain functions
# as well as guaranteeing that certain functions will not be called if
# _prep returns zero. This checks those guarantees by creating mock regex
# classes that query the behavior.

use blib;
use PDL;
use strict;
use warnings;
use Test::More tests => 23;
use blib;
use PDL::Regex;

#################################################################
#                             Order                             #
#################################################################

package NRE::Mock::MinMaxOrder;
our @ISA = qw(NRE);
use strict;
use warnings;
use Carp;
use Method::Signatures;

# Track the behavior _new, _apply, apply, _prep, _min_size, and _max_size:

# override new to create a string with the call order:
func _new ($class, %args) {
	return $class->SUPER::_new(has_run => '_new');
}

# Match anything:
method _apply ($left, $right) {
	$self->{has_run} .= ' _apply';
	return $right - $left + 1;
}

# Override apply:
method apply ($piddle) {
	$self->{has_run} .= ' apply';
	return $self->SUPER::apply($piddle);
}

method _prep ($piddle) {
	$self->{has_run} .= ' _prep';
	return $self->SUPER::_prep($piddle);
}

# Provide minimal min_size and max_size:
method _min_size () {
	$self->{has_run} .= ' _min_size';
	return 1;
}

method _max_size () {
	$self->{has_run} .= ' _max_size';
	return 1;
}

########################################################################
#                        Min/Max Size Tests - 7                        #
########################################################################

package main;

my $regex = NRE::Mock::MinMaxOrder->_new();
# Make sure new doesn't do anything fancy:
is($regex->{has_run}, '_new', 'Default constructor has not called anything fancy');
my $data = sequence(10);
my ($length, $offset) = $regex->apply($data);
is($length, 1, 'Matched length should be 1');
is($offset, 0, 'Matched offset should be 0');

# Make sure the call order is correct:
my @order = split /\s/, $regex->{has_run};
# Associate each function with its call-order index:
my %placement = map {$order[$_] => $_} 0..$#order;

ok($placement{apply} < $placement{_prep}, '_prep is not called before user-level function apply');
ok($placement{_prep} < $placement{_min_size}, '_prep is called before _min_size');
ok($placement{_prep} < $placement{_max_size}, '_prep is called before _max_size');
ok($placement{_min_size} < $placement{_apply}, '_prep comes before _apply');



#######################################################################
#                               Prep                                  #
#######################################################################


package NRE::Mock::FailedPrep;
our @ISA = qw(NRE);
use strict;
use warnings;
use Carp;
use Method::Signatures;

# Track the behavior _new, _apply, apply, _prep, _min_size, _max_size,
# and cleanup:

# override new to create a string with the call order, make this a capturing
# regex, and supply a default return value for _prep:
func _new ($class, %args) {
	return $class->SUPER::_new(name => 'test', return_at_prep => 0, has_run => '_new', %args);
}

# Match anything, though this should never be called:
method _apply ($left, $right) {
	$self->{has_run} .= ' _apply';
	return $right - $left + 1;
}

# Override apply:
method apply ($piddle) {
	$self->{has_run} .= ' apply';
	return $self->SUPER::apply($piddle);
}

# a failing prep:
method _prep ($piddle) {
	$self->SUPER::_prep($piddle);
	$self->{has_run} .= ' _prep';
	return $self->{return_at_prep};
}

# A cleanup that takes note of things:
method _cleanup () {
	$self->{has_run} .= ' _cleanup';
}

# Provide minimal min_size and max_size:
method _min_size () {
	$self->{has_run} .= ' _min_size';
	return 1;
}

method _max_size () {
	$self->{has_run} .= ' _max_size';
	return 1;
}

method _store_match ($left, $right) {
	$self->{has_run} .= ' _store_match';
	return $self->SUPER::_store_match($left, $right);
}

method _clear_stored_match () {
	$self->{has_run} .= ' _clear_stored_match';
	return $self->SUPER::_clear_stored_match;
}

package main;

#######################################################################
#                           Failed Prep - 8                           #
#######################################################################

$regex = NRE::Mock::FailedPrep->_new();
diag('Failed Prep Tests');
# Make sure new doesn't do anything fancy:
($length, $offset) = $regex->apply($data);
is($length, undef, 'Failed match returns undefined length');
is($offset, undef, 'Failed match returns undefined offset');

# Make sure the call order is correct:
@order = split /\s/, $regex->{has_run};
# Associate each function with its call-order index:
my %ran = map {$_ => 1} @order;

ok($ran{_prep}, '_prep should run');
is($ran{_apply}, undef, '_apply should not run');
is($ran{_min_size}, undef, '_min_size should not run');
is($ran{_max_size}, undef, '_min_size should not run');
ok($ran{_cleanup}, '_cleanup should run');
is($ran{_store_match}, undef, '_store_match should not run');


#######################################################################
#                         Successful Prep - 8                         #
#######################################################################

# Now make sure that if we return 1 at prep that everything works
$regex = NRE::Mock::FailedPrep->_new(return_at_prep => 1);
diag('Succeeding Prep Tests');
# Make sure new doesn't do anything fancy:
($length, $offset) = $regex->apply($data);

is($length, 1, 'Matched length should be 1');
is($offset, 0, 'Matched offset should be 0');

# Make sure the call order is correct:
@order = split /\s/, $regex->{has_run};
# Associate each function with its call-order index:
%ran = map {$_ => 1} @order;

ok($ran{_prep}, '_prep should run');
ok($ran{_apply}, '_apply should run');
ok($ran{_min_size}, '_min_size should run');
ok($ran{_max_size}, '_min_size should run');
ok($ran{_cleanup}, '_cleanup should run');
ok($ran{_store_match}, '_store_match should run');
