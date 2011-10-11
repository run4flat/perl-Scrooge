=head1 Basics Test Suite Classes

This file is part of the test suite. It provides a collection of simple
regular expression classes for testing all manner of the regular expression
funcionality. It also gives basic types for testing the Grouping regular
expression classes that do not depend upon the Quantified class.

=cut

# Basics.pm
#
# A collection of basic classes for testing purposes. These classes let you
# test the base class, PDL::Regex, with no dependence on the derived classes
# in Regex.pm. This is good because it allows you to test the engine and the
# Grouping regexes without depending on the operation of the Quantitative
# regexes.
#
# Tests for *these* classes (which ensure that they work as advertised)
# can be found in -Basics.t

use PDL::Regex;

##########################################################################
#                         PDL::Regex::Test::Fail                         #
##########################################################################

# A class that always fails during the apply stage. To create an object of
# this class, you simply use:
#
#     my $regex = PDL::Regex::Test::Fail->new;
#

package PDL::Regex::Test::Fail;
use strict;
use warnings;
our @ISA = qw(PDL::Regex);

sub _init {
	my $self = shift;
	$self->{min_size} = 1 if not defined $self->{min_size};
	$self->{max_size} = 1 if not defined $self->{max_size};
}

sub _apply { 0 }

##########################################################################
#                      PDL::Regex::Test::Fail::Prep                      #
##########################################################################

# A class that always fails during the prep stage. To create an object of
# this class, use this:
#
#     my $regex = PDL::Regex::Test::Fail::Prep->new;
#

package PDL::Regex::Test::Fail::Prep;
use strict;
use warnings;
our @ISA = qw(PDL::Regex);

sub _prep { 0 }
sub _apply { 0 }

###########################################################################
#                          PDL::Regex::Test::All                          #
###########################################################################

# A class that always matches everything that it is given. To create an
# object of this class, use this:
#
#     my $regex = PDL::Regex::Test::All->new;
#

package PDL::Regex::Test::All;
use strict;
use warnings;
our @ISA = qw(PDL::Regex);

sub _prep {
	my $self = shift;
	$self->{min_size} = 0;
	$self->{max_size} = $self->{piddle}->nelem;
}

sub _apply {
	my (undef, $left, $right) = @_;
	return '0 but true' if $right < $left;
	return $right - $left + 1;
}


###########################################################################
#                      PDL::Regex::Test::ShouldCroak                      #
###########################################################################

# This creates a class that always returns more than it is given, so it
# should always elicit a croak from the engine:
package PDL::Regex::Test::ShouldCroak;
use strict;
use warnings;
our @ISA = qw(PDL::Regex::Test::All);

sub _apply {
	my (undef, $left, $right) = @_;
	return $right - $left + 2;
}


###########################################################################
#                         PDL::Regex::Test::Croak                         #
###########################################################################

# This creates a class that always croaks during the apply phase:
package PDL::Regex::Test::Croak;
use strict;
use warnings;
our @ISA = qw(PDL::Regex::Test::All);

sub _apply {
	die "This regex always croaks\n";
}


############################################################################
#                          PDL::Regex::Test::Even                          #
############################################################################

# A subclass of Test::All that matches only even lengths:
package PDL::Regex::Test::Even;
use strict;
use warnings;
our @ISA = (qw(PDL::Regex::Test::All));

sub _apply {
	my (undef, $left, $right) = @_;
	# Match for length of zero:
	return '0 but true' if $right < $left;
	# Fail for odd length, return correction of -1
	return -1 if (($left - $right + 1) % 2 == 1);
	# Otherwise we have an even length, so match:
	return $right - $left + 1;
}


###########################################################################
#                        PDL::Regex::Test::Exactly                        #
###########################################################################

# Successfully matches exactly the number of elements that you specify

package PDL::Regex::Test::Exactly;
use strict;
use warnings;
our @ISA = qw(PDL::Regex);

# To create an object of this class, you can call it as:
#
#     my $regex = PDL::Regex::Test::Exactly->new(N => 5);
#
# You can also call it without specifying N (defaults to 1):
# 
#     my $regex = PDL::Regex::Test::Exactly->new();
#
# You can change the number of items to exactly match:
#
#     $regex->set_N(20);
#
sub _init {
	my $self = shift;
	my $N = delete $self->{N};
	$N = 1 if not defined $N;
	$self->min_size($N);
	$self->max_size($N);
}

sub set_N {
	my ($self, $N) = @_;
	$self->min_size($N);
	$self->max_size($N);
}

sub _apply {
	my $self = shift;
	return $self->min_size;
}

###########################################################################
#                         PDL::Regex::Test::Range                         #
###########################################################################

# Successfully matches anything within a range of lengths.
# To use, specify min_size and max_size in the constructor:
# 
#     my $regex = PDL::Regex::Test::Range->new(min_size => 1, max_size => 5);
# 
# You can also call it without specifying any sizes, in which case it
# defaults to 1, 1. You can change the size by calling min_size and max_size
# directly. However, the class will not double-check values for you, you
# must make sure that max_size > min_size.
# 
#     $regex->min_size(4);
#     $regex->max_size(15);
# 

package PDL::Regex::Test::Range;
use strict;
use warnings;
our @ISA = qw(PDL::Regex);

sub _init {
	my $self = shift;
	$self->{min_size} = 1 if not defined $self->{min_size};
	$self->{max_size} = 1 if not defined $self->{max_size};
}

sub _apply {
	my ($self, $left, $right) = @_;
	return $right - $left + 1;
}

###########################################################################
#                    PDL::Regex::Test::Exactly::Offset                    #
###########################################################################

# Subclass of Test::Exactly that matches only when left is at a specified
# offset.
package PDL::Regex::Test::Exactly::Offset;
use strict;
use warnings;
our @ISA = (qw(PDL::Regex::Test::Exactly));

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


1;
