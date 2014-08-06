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
	$self->SUPER::init;
	
	# Parse the quantifiers:
	my ($ref) = delete $self->{quantifiers};
	
	# Make sure the caller supplied a quantifiers key and that it's correct:
	croak("Quantifiers must be specified with a defined value associated with key [quantifiers]")
		unless defined $ref;
	croak("Quantifiers must be supplied as a two-element anonymous array")
		unless (ref($ref) eq ref([]) and @$ref == 2);
	
	# Be sure that the quantifiers parse
	Scrooge::parse_position(1, $_) foreach (@$ref);
	
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
	
	# Bail out if inherited method fails
	return 0 unless $self->SUPER::prep($match_info);
	
	# Compute and store the numeric values for the min and max quantifiers:
	my $N = $match_info->{data_length};
	
	my $min_size = Scrooge::parse_position($N, $self->{min_quant});
	my $max_size = Scrooge::parse_position($N, $self->{max_quant});
	
	# Evaluate the null situations
	return 0 if $min_size > $N;
	return 0 if $max_size < 0;
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
	
	# Apply the rule and see what we get, defaulting to a match length of
	# 0 if nothing (or zero) is returned
	my $consumed = eval{$self->{subref}->($match_info)} || 0;
	
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

package Scrooge::Repeat;
our @ISA = qw(Scrooge::Quantified);
use Carp;

=head2 Scrooge::Repeat

The Scrooge::Repeat class encloses another pattern and allows it to
repeat, in sequence. Scrooge::Repeat provides a way to specify the number of
allowed (or required) repetitions, and is itself Scrooge::Quantified. This
means you can specify the minimum and maximum lengths that the aglomeration
of repeated patterns must fill. Unlike Scrooge::Quantified, Scrooge::Repeat
has default quantifiers, and they are C<0, '100%'>.

You indiate the number of repetitions by providing a value for the
C<repeat> key. Scalar and string arguments are supported, are two-element
array refs. There is also a hashref form, used due to its likeness to the
Perl regex quantifier limits.

 my $other_pat = ...;
 my $pat = Scrooge::Repeat->new(
     subpattern => $other_pat,
     repeat => 5,          # only 5 repetitions
     repeat => "5",        #   ditto
     repeat => [5 => 5],   #   ditto
     repeat => {5,5},      #   ditto
     repeat => '*',        # zero or more
     repeat => '0,',       #   ditto
     repeat => [0, undef], #   ditto
     repeat => {0, undef}, #   ditto
     repeat => ',',        #   ditto, but use '*' instead of ','
     repeat => '+',        # one or more
     repeat => [1, undef], #   ditto
     repeat => {1, undef}, #   ditto
     repeat => '1,',       #   ditto
     repeat => '5,',       # five or more
     repeat => [5, undef], #   ditto
     repeat => [5=>undef], #   ditto
     repeat => [5],        #   CROAKS
     repeat => [0 => 5],   # up to 5
     repeat => [0.1 => 5], #   ditto (rounds)
     repeat => [0 => 5.2], #   ditto (rounds)
     repeat => [0, 5],     #   ditto
     repeat => {0,5},      #   ditto
     repeat => ',5',       #   ditto
     repeat => [undef, 5], #   ditto (but why would you?)
     repeat => {undef, 5}, #   ditto but warns uninitialized
     repeat => [undef=>5], # CROAKS     (undef is parsed by
     repeat => {undef=>5}, #   ditto     Perl as a string)
 );

Scrooge::Repeat sets up its behavior by overriding the following methods:

=over

=item init

Ensures that you provide an enclosing pattern to repeat; if not, the
constructor fails saying

 Scrooge::Repeat expects a subpattern

If you provide a subpattern that is not a subclass of Scrooge, it will
croak saying

 Subpattern for Scrooge::Repeat must be a Scrooge object

It then validates your repeat count using L</parse_repeat>,
assigning the parsed quantifiers to C<min_rep> and C<max_rep>.

=cut

use Safe::Isa;
sub init {
	my $self = shift;
	
	# Set sensible default quantifiers
	$self->{quantifiers} = [0, '100%'] if not exists $self->{quantifiers};
	
	# Call inherited method
	$self->SUPER::init;
	
	# Validate the subpattern
	croak('Scrooge::Repeat expects a subpattern')
		unless exists $self->{subpattern};
	croak('Subpattern for Scrooge::Repeat must be a Scrooge object')
		unless $self->{subpattern}->$_isa('Scrooge');
	
	# Validate and compute the repeat limits
	($self->{min_rep}, $self->{max_rep}) = $self->parse_repeat($self->{repeat});
}

=item Scrooge::Repeat::parse_repeat

Parses a repeat spec and returns a two-element list of the min and max
repeat quantities. This is a class method, which means you can override
repeat parsing in subclasses on the one hand, and on the other hand you can
call this function outside the context of a Scrooge::Repeat object by saying

 my ($min, $max) = Scrooge::Repeat->parse_repeat($rep);

The return values will be the minimum and maximum repeat counts. The minimum
count will always be an integer, greater than or equal to zero, while the
maximum repeat count will either be a non-negative integer or C<undef>,
which means "unlimited".

Your repeat count could be invalid for a number of reason, and may lead to
one of the following errors:

=over

=item Unable to parse scalar repeat of <string>

You provided a scalar repeat count, but I was not able to parse
it. Valid scalar repeat counts include the string C<+>, the string C<*>,
and (non-negative) integers.

=item Arrayref repeats must contain two elements

Arrayref repeats can only contain two elements (one or both of which can be
the undefined value). This may be relaxed some day if I get around to
implementing a lexical warning system.

=item Hashref repeats must have a single key/value pair

You provided a hashref for the repeat count which was either empty or
which contained more than one key/value pair.

=item Scrooge::Repeat::parse_repeat does not know how to parse <type>

parse_repeat only knows how to parse a scalar, an arrayref, or a hashref. If
you give something else, it does not know what to do and issues this
exception.

=item Repeat must be a number

=item Repeat must be non-negative

When using an arrayref or hashref, the repeats ought to be positive
integers, though any positive number will be accepted and truncated to the
nearest integer. If you provide something that is not a number, you will get
this error.

=back

=cut

use Scalar::Util qw(looks_like_number);

sub parse_repeat {
	my ($class, $rep) = @_;
	
	# Default value
	return (0, undef) if not defined $rep;
	
	# Scalar inputs
	if(ref($rep) eq ref('scalar')) {
		return (1, undef) if $rep eq '+';
		return (0, undef) if $rep eq '*';
		return ($rep, $rep) if $rep =~ /^\d+$/;
		if ($rep =~ /^(\d*),(\d*)$/) {
			my ($min, $max) = ($1, $2);
			$min = 0 if $min eq '';
			$max = undef if $max eq '';
			return ($min, $max);
		}
		croak("Unable to parse scalar repeat of $rep");
	}
	
	# hashref and arrayref inputs; pull out the min/max pair
	my @minmax;
	if (ref($rep) eq ref([])) {
		croak('Arrayref repeats must contain two elements') if @$rep != 2;
		@minmax = @$rep;
	}
	elsif (ref($rep) eq ref({})) {
		croak('Hashref repeats must have a single key/value pair')
			if keys(%$rep) != 1;
		@minmax = %$rep;
	}
	else {
		croak('Scrooge::Repeat::parse_repeat does not know how to parse '
			. ref($rep));
	}
	
	# Verify that we have good numbers and convert to integers (or leave
	# undefined)
	for (@minmax) {
		if (defined $_) {
			croak('Repeat must be a number') unless looks_like_number($_);
			croak('Repeat must be non-negative') if $_ < 0;
			$_ = int($_);
		}
	}
	$minmax[0] ||= 0;
	return (@minmax);
}

=item prep

Prepares the enclosed pattern, and calculates the anticipated min/max
consumption based on the enclosed pattern's min/max as well as the
repetition limits.

=cut

sub prep {
	my ($self, $match_info) = @_;
	return 0 unless $self->SUPER::prep($match_info);
	
	# Create the subpattern's match_info template
	my $subpattern = $self->{subpattern};
	my $subpattern_info = { %$match_info };
	$match_info->{subpattern_info_template} = $subpattern_info;
	
	# Return immediately if the subpattern fails to prep
	return 0 unless $subpattern->prep($subpattern_info);
	
	# calculate the minimum and maximum size based on the subpattern's sizes
	# and the repetition counts. Note a max_rep value of undefined means
	# unlimited, which requires a little bit of care.
	my $minimum_size = $subpattern_info->{min_size} * $self->{min_rep};
	my $maximum_size;
	if (defined $self->{max_rep}) {
		$maximum_size = $subpattern_info->{max_size} * $self->{max_rep};
	}
	elsif ($subpattern_info->{max_size} == 0) {
		# if subpattern's max is zero, this max will also be a zero
		$maximum_size = 0
	}
	else {
		# unlimited matches on nonzero subpattern match size:
		$maximum_size = $match_info->{max_size};
	}
	
	# Return immediately if the repetitions won't fit
	return 0 if $minimum_size > $match_info->{max_size};
	return 0 if $maximum_size < $match_info->{min_size};
	
	# tighten our min and max size bounds based on our calculations
	$match_info->{min_size} = $minimum_size
		if $minimum_size > $match_info->{min_size};
	$match_info->{max_size} = $maximum_size
		if $maximum_size < $match_info->{max_size};
	
	# Make sure we have somewhere to store our positive matches
	$match_info->{positive_matches} = [];
	
	return 1;
}

=item apply

Attempts to sequentially apply the subpattern for the specified number of
repetitions.

=cut

sub apply {
	my ($self, $match_info) = @_;
	my $left = $match_info->{left};
	my $amount_remaining = $match_info->{length};
	my $subpattern = $self->{subpattern};
	
	# Figure out a max rep that'll work for the for loop
	my $max_rep = $self->{max_rep};
	$max_rep = 'inf' + 0 unless defined $max_rep;
	
	# Try to repeat the match until we hit our maximum number of repetitions.
	# We'll make sure we've surpassed the minimum after we've exited the
	# loop.
	REPETITION: for (my $rep = 0; $rep < $max_rep; $rep++) {
		
		# Make a copy of the subpattern's info
		my $info = { %{$match_info->{subpattern_info_template}} };
		
		# Figure out how much this subpattern will try
		my $curr_max_len = $amount_remaining;
		$curr_max_len = $info->{max_size} if $info->{max_size} < $curr_max_len;
		my $consumed;
		
		RIGHT_BOUND: {
			# Set the left, right, and length
			$info->{left} = $left;
			$info->{right} = $left + $curr_max_len - 1;
			$info->{length} = $curr_max_len;
			
			# Done if the subpattern wants more than we have remaining
			last REPETITION if $info->{min_size} > $curr_max_len;
			
			# Apply the pattern:
			$consumed = eval{ $subpattern->apply($info) } || 0;
			
			# Check for exceptions:
			if ($@ ne '') {
				my $name = $self->get_bracketed_name_string;
				my $subname = $subpattern->get_bracketed_name_string;
				die "In re_or pattern$name, subpattern$subname failed:\n$@"; 
			}
			
			# Make sure that the pattern didn't consume more than it was supposed
			# to consume:
			if ($consumed > $info->{length}) {
				my $name = $self->get_bracketed_name_string;
				my $subname = $subpattern->get_bracketed_name_string;
				die "In Scrooge::Repeat pattern$name, subpattern$subname consumed $consumed\n"
					. "but it was only allowed to consume $info->{length}\n"; 
			}
			
			# Check for a negative return value, which means 'try again at a
			# shorter length'
			if ($consumed < 0) {
				$curr_max_len += $consumed;
				redo RIGHT_BOUND;
			}
		}
		
		# Quit the repetition loop if we didn't match
		last REPETITION unless $consumed;
		
		# Final bookkeeping for a successful match
		push @{$match_info->{positive_matches}}, $info;
		$info->{length} = $consumed + 0;
		$info->{right} = $left + $consumed - 1;
		$amount_remaining -= $consumed;
		$left += $consumed;
	}
	
	# If we failed to consume the minimum number of repetitions, then
	# return zero.
	return 0 if @{$match_info->{positive_matches}} < $self->{min_rep};
	
	# If we have zero repetitions, return true (presumably if we've reached
	# here, then $self->{min_rep} is zero, so this is OK).
	return '0 but true' if @{$match_info->{positive_matches}} == 0;
	
	# Calculate and return the total amount consumed
	my $consumed = $match_info->{positive_matches}[-1]{right}
		- $match_info->{left} + 1;
	return $consumed || '0 but true';
}

=item cleanup

=cut

sub cleanup {
	my ($self, $top_match_info, $match_info) = @_;
	
	# Call our superclass's cleanup
	$self->SUPER::cleanup($top_match_info, $match_info);
	my $subpattern = $self->{subpattern};
	
	# Call the cleanup method on the template, then for *each* successful
	# repetition, holding off on dying until the very end.
	my @errors;
	my $top_match = undef;
	for my $info ($match_info->{subpattern_info_template},
		@{$match_info->{positive_matches}}
	) {
		eval { $subpattern->cleanup($top_match, $info) };
		# top_match is undefined on the first (template) round, which is
		# useful for resource cleanup. Thereafter, all cleanups are for
		# successful matches, so we need to have a meaningful top_match_info
		$top_match = $top_match_info;
		push @errors, $@ if $@ ne '';
	}
	
	# Remove the subpattern info template
	delete $match_info->{subpattern_info_template};
	
	# Rethrow if we caught any exceptions:
	if (@errors == 1) {
		die(@errors);
	}
	elsif (@errors > 1) {
		die(join(('='x20) . "\n", 'Multiple Errors', @errors));
	}
	
}

=back

=cut

1;

