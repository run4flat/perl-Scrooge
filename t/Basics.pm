# Basics.pm
#
# A collection of basic patterns for testing purposes. These patterns let
# you test the base class, Scrooge, with no dependence on the derived
# patterns. This is good because it lets you to test the engine and the
# Grouping patterns without depending on the operation of the Quantitative
# patterns.
#
# Tests for *these* patterns (which ensure that they work as advertised)
# can be found in t/02-Basics.t
#
# Unless otherwise stated, to create a new pattern of any of these types,
# say something like this:
#
#     my $pattern = classname->new;


use strict;
use warnings;
use Scrooge;

###########################################################################
#                           Scrooge::Test::Fail                           #
###########################################################################
# Always fails during the apply stage.

package Scrooge::Test::Fail;
our @ISA = qw(Scrooge);

sub apply { 0 }

###########################################################################
#                        Scrooge::Test::Fail::Prep                        #
###########################################################################
# Always fails during the prep stage.

package Scrooge::Test::Fail::Prep;
our @ISA = qw(Scrooge);

sub prep { 0 }
sub apply { 0 }

############################################################################
#                            Scrooge::Test::All                            #
############################################################################
# Matches everything that it is given.

package Scrooge::Test::All;
our @ISA = qw(Scrooge);

sub apply {
	my (undef, $match_info) = @_;
	return $match_info->{length};
}


############################################################################
#                        Scrooge::Test::ShouldCroak                        #
############################################################################
# Always returns more than it is given, so it should always elicit a croak
# from the engine.
package Scrooge::Test::ShouldCroak;
our @ISA = qw(Scrooge);

sub apply {
	my (undef, $match_info) = @_;
	return $match_info->{length} + 1;
}


############################################################################
#                           Scrooge::Test::Croak                           #
############################################################################
# Always croaks during the apply phase
package Scrooge::Test::Croak;
our @ISA = qw(Scrooge);

sub apply {
	die "This regex always croaks\n";
}


#############################################################################
#                            Scrooge::Test::Even                            #
#############################################################################
# Matches only even lengths:

package Scrooge::Test::Even;
our @ISA = qw(Scrooge);

sub apply {
	my (undef, $match_info) = @_;
	my $length = $match_info->{length};
	# Match for even lengths
	return $length if $length % 2 == 0;
	# Fail for odd length, return correction of -1
	return -1;
}


############################################################################
#                          Scrooge::Test::Exactly                          #
############################################################################
# Matches exactly the number of elements that you specify
#
# To create one of these patterns, say:
#
#     my $pattern = Scrooge::Test::Exactly->new(N => 5);
#
# You can also create it without specifying N (defaults to 1):
# 
#     my $pattern = Scrooge::Test::Exactly->new();
#
# You can change the number of items by modifying the N key of the pattern:
#
#     $pattern->{N} = 20;
#

package Scrooge::Test::Exactly;
our @ISA = qw(Scrooge);

sub init {
	my $self = shift;
	$self->{N} = 1 unless exists $self->{N};
}

sub prep {
	my ($self, $match_info) = @_;
	$match_info->{min_size} = $match_info->{max_size} = $self->{N};
	1;
}

sub apply { return shift->{N} }

############################################################################
#                           Scrooge::Test::Range                           #
############################################################################
# Matches anything within a range of lengths. To create one of these,
# specify min_size and max_size in the constructor:
#
#     my $pattern = Scrooge::Test::Range->new(min_size => 1, max_size => 5);
#
# You can also call it without specifying any sizes, in which case it
# defaults to 1, 1. You can change the size by setting $regex->{min_size} and
# $regex->{max_size} directly. However, the class will not double-check values
# for you, you must make sure that max_size > min_size.
#
#     $pattern->{min_size} = 4;
#     $pattern->{max_size} = 15;
# 

package Scrooge::Test::Range;
our @ISA = qw(Scrooge);

sub init {
	my $self = shift;
	$self->{min_size} = 1 unless exists $self->{min_size};
	$self->{max_size} = 1 unless exists $self->{max_size};
}

sub prep {
	my ($self, $match_info) = @_;
	$match_info->{min_size} = $self->{min_size};
	$match_info->{max_size} = $self->{max_size};
	1;
}

sub apply {
	my ($self, $match_info) = @_;
	return $match_info->{length};
}

############################################################################
#                      Scrooge::Test::Exactly::Offset                      #
############################################################################
# Subclass of Scrooge::Test::Exactly that matches only when the left
# position is at a specified offset. You can specify the offset in the
# constructor:
#
#     my $pattern = Scrooge::Test::Exactly::Offset->new(offset => 5);
#
# or you can work with the default value of 0. To change the offset, simply
# change the offset key:
#
#     $pattern->{offset} = 10;
#
package Scrooge::Test::Exactly::Offset;
our @ISA = (qw(Scrooge::Test::Exactly));

sub init {
	my $self = shift;
	$self->SUPER::init;
	$self->{offset} = 0 if not defined $self->{offset};
}

sub apply {
	my ($self, $match_info) = @_;
	
	return 0 unless $match_info->{left} == $self->{offset};
	return $self->{N};
}

############################################################################
#                         Scrooge::Test::OffsetZWA                         #
############################################################################
# Zero-width assertion that matches only at the specified location, which
# defaults to zero. You can specify the offset in the constructor:
#
#     my $pattern = Scrooge::Test::OffsetZWA->new(offset => 5);
#
# To change the offset, simply change the offset key:
#
#     $pattern->{offset} = 10;
#
package Scrooge::Test::OffsetZWA;
our @ISA = qw(Scrooge);

sub init {
	my $self = shift;
	$self->{offset} = 0 if not defined $self->{offset};
}

sub prep {
	my ($self, $match_info) = @_;
	$match_info->{min_size} = 0;
	$match_info->{max_size} = 0;
	1;
}

sub apply {
	my ($self, $match_info) = @_;
	
	return 0 unless $match_info->{left} == $self->{offset};
	return '0 but true';
}

############################################################################
#                          Scrooge::Test::Printer                          #
############################################################################
# Zero-width pattern used for debugging. This pattern simply prints the
# location at which it is called, making it useful for tracking the progress
# of the engine and grouping patterns. This is not presently used in the
# test suite.

package Scrooge::Test::Printer;
our @ISA = qw(Scrooge);

sub prep {
	my ($self, $match_info) = @_;
	$match_info->{min_size} = 0;
	$match_info->{max_size} = 0;
}

sub apply {
	my ($self, $match_info) = @_;
	Test::More::diag("Looking at position $match_info->{left}\n");
	return '0 but true';
}

1;
