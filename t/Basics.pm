=head1 Basics Test Suite Classes

This file is part of the test suite. It provides a collection of simple
regular expression classes for testing all manner of the regular expression
funcionality. It also gives basic types for testing the Grouping regular
expression classes that do not depend upon the Quantified class.

=cut

# Basics.pm
#
# A collection of basic classes for testing purposes. These classes let you
# test the base class, Scrooge, with no dependence on the derived classes
# in Regex.pm. This is good because it allows you to test the engine and the
# Grouping regexes without depending on the operation of the Quantitative
# regexes.
#
# Tests for *these* classes (which ensure that they work as advertised)
# can be found in -Basics.t

use Scrooge;

###########################################################################
#                           Scrooge::Test::Fail                           #
###########################################################################

# A class that always fails during the apply stage. To create an object of
# this class, you simply use:
#
#     my $regex = Scrooge::Test::Fail->new;
#

package Scrooge::Test::Fail;
use strict;
use warnings;
our @ISA = qw(Scrooge);

sub min_size { 1 }
sub max_size { 1 }
sub _apply { 0 }

###########################################################################
#                        Scrooge::Test::Fail::Prep                        #
###########################################################################

# A class that always fails during the prep stage. To create an object of
# this class, use this:
#
#     my $regex = Scrooge::Test::Fail::Prep->new;
#

package Scrooge::Test::Fail::Prep;
use strict;
use warnings;
our @ISA = qw(Scrooge);

sub _prep_data { 0 }
sub _prep_invocation { 0 }
sub _apply { 0 }

############################################################################
#                            Scrooge::Test::All                            #
############################################################################

# A class that always matches everything that it is given. To create an
# object of this class, use this:
#
#     my $regex = Scrooge::Test::All->new;
#

package Scrooge::Test::All;
use strict;
use warnings;
our @ISA = qw(Scrooge);
__PACKAGE__->coerce_as_data_property('max_size');

sub _prep_data {
	my $self = shift;
	$self->min_size(0);
	$self->max_size(Scrooge::data_length($self->data));
	return 1;
}

sub _apply {
	my (undef, $left, $right) = @_;
	return '0 but true' if $right < $left;
	return $right - $left + 1;
}


############################################################################
#                        Scrooge::Test::ShouldCroak                        #
############################################################################

# This creates a class that always returns more than it is given, so it
# should always elicit a croak from the engine:
package Scrooge::Test::ShouldCroak;
use strict;
use warnings;
our @ISA = qw(Scrooge::Test::All);

sub _apply {
	my (undef, $left, $right) = @_;
	return $right - $left + 2;
}


############################################################################
#                           Scrooge::Test::Croak                           #
############################################################################

# This creates a class that always croaks during the apply phase:
package Scrooge::Test::Croak;
use strict;
use warnings;
our @ISA = qw(Scrooge::Test::All);

sub _apply {
	die "This regex always croaks\n";
}


#############################################################################
#                            Scrooge::Test::Even                            #
#############################################################################

# A subclass of Test::All that matches only even lengths:
package Scrooge::Test::Even;
use strict;
use warnings;
our @ISA = (qw(Scrooge::Test::All));

sub _apply {
	my (undef, $left, $right) = @_;
	# Match for length of zero:
	return '0 but true' if $right < $left;
	# Fail for odd length, return correction of -1
	return -1 if (($left - $right + 1) % 2 == 1);
	# Otherwise we have an even length, so match:
	return $right - $left + 1;
}


############################################################################
#                          Scrooge::Test::Exactly                          #
############################################################################

# Successfully matches exactly the number of elements that you specify

package Scrooge::Test::Exactly;
use strict;
use warnings;
our @ISA = qw(Scrooge);

# To create an object of this class, you can call it as:
#
#     my $regex = Scrooge::Test::Exactly->new(N => 5);
#
# You can also call it without specifying N (defaults to 1):
# 
#     my $regex = Scrooge::Test::Exactly->new();
#
# You can change the number of items to exactly match:
#
#     $regex->set_N(20);
#
sub _init {
	my $self = shift;
	$self->{N} = 1 unless exists $self->{N};
}

sub set_N {
	my ($self, $N) = @_;
	$self->{N} = $N;
}

sub min_size { return $_[0]->{N} }
sub max_size { return $_[0]->{N} }
sub _apply   { return $_[0]->{N} }

############################################################################
#                           Scrooge::Test::Range                           #
############################################################################

# Successfully matches anything within a range of lengths.
# To use, specify min_size and max_size in the constructor:
# 
#     my $regex = Scrooge::Test::Range->new(min_size => 1, max_size => 5);
# 
# You can also call it without specifying any sizes, in which case it
# defaults to 1, 1. You can change the size by setting $regex->{min_size} and
# $regex->{max_size} directly. However, the class will not double-check values
# for you, you must make sure that max_size > min_size.
# 
#     $regex->min_size(4);
#     $regex->max_size(15);
# 

package Scrooge::Test::Range;
use strict;
use warnings;
our @ISA = qw(Scrooge);

sub _init {
	my $self = shift;
	$self->min_size(1) unless defined $self->min_size;
	$self->max_size(1) unless defined $self->max_size;
}

#sub min_size {
#	return $_[0]->{min_size} unless @_ > 1;
#	$_[0]->{min_size} = $_[1];
#}
#
#sub max_size {
#	return $_[0]->{max_size} unless @_ > 1;
#	$_[0]->{max_size} = $_[1];
#}

sub _apply {
	my ($self, $left, $right) = @_;
	return $right - $left + 1;
}

############################################################################
#                      Scrooge::Test::Exactly::Offset                      #
############################################################################

# Subclass of Test::Exactly that matches only when left is at a specified
# offset. You can set the offset ussing the set_offset method:
# 
#     $regex->set_offset(10); 
#
package Scrooge::Test::Exactly::Offset;
use strict;
use warnings;
our @ISA = (qw(Scrooge::Test::Exactly));

sub _init {
	my $self = shift;
	$self->SUPER::_init;
	$self->{offset} = 0 if not defined $self->{offset};
}

sub set_offset {
	my ($self, $offset) = @_;
	$self->{offset} = $offset;
}

sub _apply {
	my ($self, $left, $right) = @_;
	
	return 0 unless $left == $self->{offset};
	return $self->SUPER::_apply($left, $right);
}

############################################################################
#                          Scrooge::Test::Printer                          #
############################################################################

# Useful for knowning the position of the current matching. Not presently used
# in the test suite; used for debugging.

package Scrooge::Test::Printer;
use strict;
use warnings;
our @ISA = qw(Scrooge);

sub min_size { 0 }
sub max_size { 0 }

sub _apply {
	my ($self, $left) = @_;
	Test::More::diag("Looking at $left\n");
	return '0 but true';
}

1;
