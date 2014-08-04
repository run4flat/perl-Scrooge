use strict;
use warnings;
use Scrooge;

package Scrooge::Quantified;
our @ISA = qw(Scrooge);
use Carp;

=head2 Scrooge::Quantified

The Scrooge::Quantified class inherits directly from Scrooge and provides
functionality for handling quantifiers, including parsing. It also matches any
input that agrees with its desired size and is the class that implements the
behavior for C</re_any>.

This class uses the C<min_quant> and C<max_quant> keys and works by setting the
C<min_size> and C<max_size> keys during the C<prep> stage. It provides its own
C<init>, C<prep>, and C<apply> methods. If you need a pattern object that
handles quantifiers but you do not care how it works, you should inheret from
this base class and override the C<apply> method.

Scrooge::Quantified provdes overrides for the following methods:

=over

=item init

Scrooge::Quantified provides an C<init> function that removes the C<quantifiers>
key from the pattern object, validates the quantifier strings, and stores them
under the C<min_quant> and C<max_quant> keys.

This method can croak for many reasons. If you do not pass in an anonymous array
with two arguments, you will get either this error:

 Quantifiers must be specified with a defined value associated with key [quantifiers]

or this error:

 Quantifiers must be supplied as a two-element anonymous array

If you specify a percentage quantifier for which the last character is not '%'
(like '5% '), you will get this sort of error:

 Looks like a mal-formed percentage quantifier: [$quantifier]

If a percentage quantifier does not have any digits in it, you will see this:

 Percentage quantifier must be a number; I got [$quantifier]

If a percentage quantifier is less than zero or greater than 100, you will see
this:

 Percentage quantifier must be >= 0; I got [$quantifier]
 Percentage quantifier must be <= 100; I got [$quantifier]

A non-percentage quantifier should be an integer, and if not you will get this
error:

 Non-percentage quantifiers must be integers; I got [$quantifier]

If you need to perform your own initialization in a derived class, you should
call this class's C<_init> method to handle the quantifier parsing for you.

=cut

use Scalar::Util qw(looks_like_number);
sub init {
	my $self = shift;
	# Parse the quantifiers:
	my ($ref) = delete $self->{quantifiers};
	# Make sure the caller supplied a quantifiers key and that it's correct:
	croak("Quantifiers must be specified with a defined value associated with key [quantifiers]")
		unless defined $ref;
	croak("Quantifiers must be supplied as a two-element anonymous array")
		unless (ref($ref) eq ref([]) and @$ref == 2);
	
	# Check that indices are integers and percentages are between 0 and 100
	foreach (@$ref) {
		if (/%/) {
			# make sure percentage is at the end:
			croak("Looks like a mal-formed percentage quantifier: [$_]")
				unless (/%$/);
			# Copy the quantifier string and strip out the percentage:
			my $to_check = $_;
			chop $to_check;
			# Make sure it's a number between 0 and 100:
			croak("Percentage quantifier must be a number; I got [$_]")
				unless looks_like_number($to_check);
			croak("Percentage quantifier must be >= 0; I got [$_]")
				if $to_check < 0;
			croak("Percentage quantifier must be <= 100; I got [$_]")
				if $to_check > 100;
		}
		# Check that non-percentage quantifiers are strictly integers:
		elsif ($_ !~ /^[+\-]?\d+$/) {
			croak("Non-percentage quantifiers must be integers; I got [$_]");
		}
	}
	
	# Put the quantifiers in self:
	$self->{min_quant} = $ref->[0];
	$self->{max_quant} = $ref->[1];
	
	return $self;
}

=item prep

This method calculates the minimum and maximum number of elements that will
match based on the current data and the quantifiers stored in C<min_quant> and
C<max_quant>. If it turns out that the minimum size is larger than the maximum
size, this method returns 0 to indicate that this pattern will never match. It
also does not set the min and max sizes in that case. That means that if you
inheret from this class, you should invoke this C<prep> method; if the
return value is zero, your own C<prep> method should also be zero (or you
should have a means for handling the min/max sizes in a sensible way), and if
the return value is 1, you should proceed with your own C<prep> work.

=cut

# Prepare the current quantifiers:
sub prep {
	my ($self, $match_info) = @_;
	
	# Compute and store the numeric values for the min and max quantifiers:
	my $N = $match_info->{data_length};
	my ($min_size, $max_size);
	my $min_quant = $self->{min_quant};
	my $max_quant = $self->{max_quant};
	
	if ($min_quant =~ s/%$//) {
		$min_size = int(($N - 1) * ($min_quant / 100.0));
	}
	elsif ($min_quant < 0) {
		$min_size = int($N + $min_quant);
		# Set to a reasonable value if min_quant was too negative:
		$min_size = 0 if $min_size < 0;
	}
	else {
		$min_size = int($min_quant);
		# Stop now if the min size is too large:
		return 0 if $min_size > $N;
	}
	if ($max_quant =~ s/%$//) {
		$max_size = int(($N - 1) * ($max_quant / 100.0));
	}
	elsif ($max_quant < 0) {
		$max_size = int($N + $max_quant);
		# Stop now if the max quantifier was too negative:
		return 0 if $max_size < 0;
	}
	else {
		$max_size = int($max_quant);
		# Set to a reasonable value if max_quant was too large:
		$max_size = $N if $max_size > $N;
	}
	
	# One final sanity check:
	return 0 if ($max_size < $min_size);
	
	# If we're good, store the sizes:
	$match_info->{min_size} = $min_size;
	$match_info->{max_size} = $max_size;
	return 1;
}

=item apply

This very simple method returns the full length as a successful match. It
does not provide any extra match details. It assumes that the pattern engine
honors the min and max sizes that were set during C<prep>.

=cut

sub apply {
	my (undef, $match_info) = @_;
	return $match_info->{length};
}

=back

=cut

package Scrooge::Sub;
our @ISA = qw(Scrooge::Quantified);
use Carp;

=head2 Scrooge::Sub

The Scrooge::Sub class is the class that underlies the L</re_sub> pattern
constructor. This is a fairly simple class that inherits from
L</Scrooge::Quantified> and expects to have a C<subref> key supplied in the call
to its constructor. Scrooge::Sub overrides the following Scrooge methods:

=over

=item init

The initialization method verifies that you did indeed provide a subroutine
under the C<subref> key. If you did not, you will get this error:

 Scrooge::Sub pattern [$name] requires a subroutine reference

or, if your pattern is not named,

 Scrooge::Sub pattern requires a subroutine reference

It also calls the initialization code for C<Scrooge::Quantified> to make sure
that the quantifiers are valid.

=cut

sub init {
	my $self = shift;
	
	# Check that they actually supplied a subref:
	if (not exists $self->{subref} or ref($self->{subref}) ne ref(sub {})) {
		my $name = $self->get_bracketed_name_string;
		croak("Scrooge::Sub pattern$name requires a subroutine reference")
	}
	
	# Perform the quantifier initialization
	$self->SUPER::init;
}

=item apply

Scrooge::Sub's C<apply> method evaluates the supplied subroutine at the
left and right offsets of current interest. See the documentation for L</re_sub>
for details about the arguments passed to the subroutine and return values. In
particular, if you return any match details, they will be included in the saved
match details if your pattern is a named pattern (and if it's not a named
pattern, you can still return extra match details though there's no point).

=cut

sub apply {
	my ($self, $match_info) = @_;
	# Apply the rule and see what we get:
	my $consumed = eval{$self->{subref}->($match_info)};
	
	# handle any exceptions:
	unless ($@ eq '') {
		my $name = $self->get_bracketed_name_string;
		die "Subroutine pattern$name died:\n$@";
	}
	
	# Make sure they didn't break any rules:
	if ($consumed > $match_info->{length}) {
		my $name = $self->get_bracketed_name_string;
		die "Subroutine pattern$name consumed more than it was allowed to consume\n";
	}
	
	# Return the result:
	return $consumed;
}

=back

=cut

