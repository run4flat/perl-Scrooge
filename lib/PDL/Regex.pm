package NRE;
use strict;
use warnings;
use Method::Signatures;
use Carp;

=head1 NEW IDEA

Include some sort of OPTIMIZE grouping that attempts to partition the data
in an optimal fashion using some sort of scoring mechanism?

 # Find the optimal division between an exponential drop
 # and a linear fit:
 my $regex = NRE::OPTIMIZE($exponential_drop, $linear)

=head1 to do:

Implement a stack system on _prep and _cleanup so that
individual regexes (especially those built on Groups) don't blow up if they
are used recursively. (As for being used multiple times in the same regex,
that is a problem, too, and it also needs to be solved somehow. Perhaps I
can create some sort of register function, called when the full regex adds
a sub-regex, which allows the regex object to be aware of itself.

=head1 NAME

PDL::Regex - a numerical regular expression engine

=head1 SYNOPSIS

 use PDL::Regex;
 
 # Build the regular expression object first:
 my $positive_re = NRE::SUB(sub {
     # Supplied args are the piddle, the left slice offset,
     # and the right slice offset:
     my ($piddle, $left, $right) = @_;
     
     # A simple check for positivity. Notice that
     # I return the difference of the offsets PLUS 1,
     # because that's the number of elements this regex
     # consumes.
     return ($right - $left + 1)
         if all $piddle->slice("$left:$right") > 0;
 });
 
 # Find the number of (contiguous) elements that match that regex:
 my $data = sequence(20);
 my ($matched, $offset) = $re->apply($data);
 print "Matched $matched elements, starting from $offset\n";

=head1 DESCRIPTION

PDL::Regex creates a set of classes that let you construct numerical regular
expression objects that you can apply to a piddle. Because the patterns
against which you might match are limitless, this module provides a means
for easily creating your own conditions and the glue necessary to put them
together in complex ways. It does not offer a concise syntax, but that is on
the way, no doubt.

Let's begin by considering a couple of regular expressions in Perl.

 do_something()      if $string =~ /(ab)|(cd)/;
 do_something_else() if $string =~ /(a?b+)|(c*\d{3,})/;

The first expression does something if the string matches either 'a'
followed by 'b', or if it matches 'c' followed by 'd'. The second expression
does something else if the string matches zero or one 'a' followed by one or
more 'b', or if it matches zero or more 'c' followed by at least three
digits. The second regular expression differs from the first because it
makes use of quantifiers and because it uses a character class (the C<\d>
matches many characters).

The PDL::Regex equivalents of these take up quite a bit more space to
construct. Here is how to build a numerical regular expression that checks
for a positive number followed by a local maximum, or a negative number
followed by a local minimum. I'll assume that the regular expression
construcctors for each condition already exist (I'll discuss those in a bit)

 my $regex = NRE::OR(
     NRE::SEQUENCE( positive_re(), $local_max_re() ),
     NRE::SEQUENCE( negative_re(), $local_min_re() )
 );


=head1 Examples

Here is a regular expression that checks for a value that is positive and
which is a local maximum, but which is flanked by at least one negative
number on both sides:

 my $is_local_max = NRE::SUB( [1,1],  # quantifiers, exactly one
     sub {
         my ($piddle, $left, $right) = @_;
         
         # Since this only takes one value, right == left
         my $index = $left;
         
         # The first or last element of the piddle cannot qualify
         # as local maxima for purposes of this regex:
         return 0 if $index == 0 or $index == $piddle->dim(0) - 1;
         
         return 1 if $piddle->at($index - 1) < $piddle->at($index)
             and $piddle->at($index + 1) < $piddle->at($index);
         
         return 0;
  });
 
 my $is_negative = NRE::SUB( [1,'100%'],
     sub {
         my ($piddle, $left, $right) = @_;
         
         # This cannot match if the first value is positive:
         return 0 if $piddle->at($left) >= 0;
         
         # Is the whole range negative?
         return $right - $left + 1
             if all ($piddle->slice("$left:$right") < 0);
         
         # At this point, we know that the first element
         # is negative, but part of the range is positive.
         # Find the first non-negative value and return its
         # offset, which is identical to the number of negative
         # elements to the left of it:
         return which($piddle >= 0)->at(0);
 });
 
 # Build up the sequence:
 my $regex = NRE::SEQUENCE(
     $is_negative, $is_local_max, $is_negative
 );
 
 # Match it against some data:
 if ($regex->apply($data)) {
     # Do something
 }

=head1 Return Values

=head2 When calling apply

=head2 When writing a condition

In short, if the condition matches for the given length, you should return
the number of elements matched, which is C<$right - $left + 1>. If it
does not match for this range but B<might> match for a shorter range (if
C<$right> were moved a little bit to the left), return -1. If it cannot
match starting at C<$left>, return undef. Those are the basics. However,
other return values are allowed and using them can significantly improve the
performance of your regex.

Here is a rundown of what to return when:

=over

=item Full Length

Return the full length, C<$right - $left + 1>, if the condition matches
against the full length.

=item Less than the Full Length

If your condition does not match against C<< $piddle->slice("$left:$right") >>
but it is easy to check against shorter lengths, i.e. 
C<< $piddle->slice("$left:$less_than_right") >>, you can return the number
of elements that it matches. In this case, the amount consumed would be
C<< $less_than_right - $left + 1 >>.

Note that you should only do this if it is easy to check shorter lengths.
If examining every possible value of C<$right> is expensive, then consider
returning a negative value, discussed below.

=item Zero But True

You can positively return a match of zero length under two circumstances:
matching zero elements with a "zero or more" quantifier, or matching a
zero-width assertion. In that case, you must return the string "0 but true",
which is a special string in Perl.

For example, if your condition looks for sequences that are
less than 5 and C<< $piddle->at($left) >> is 7, it is not possible for this
condition to match. However, if your quantifiers allow for zero or more
matching elements, you can legitimately say that the match was successful
and it matched zero elements. Note that if your quantifiers do not allow
a match of zero length, you should probably return the numeric value of 0,
instead.

Zero-width assertions are a different sort of match of zero elements. In
numerical regular expressions, this could
be a condition on the slope between two values, for instance. In that case,
your regex does not match either of the values, but it matche in-between
them. Look-ahead or look-behind assertions are also zero-width assertions
with which you may be familiar from standard Perl regular expressions.

=item Zero, i.e. faile match

Return the numberic value of 0 when you know that your condition cannot match for this or any
shorter range, B<including a zero-length match>. If you have concluded that
the condition cannot match the current length, but it may be able to match a
shorter length, you should return a negative value instead of zero. Also, if
your match is allowed to have a length of zero, you should return the string
"0 but true" instead.

Let's consider the condition from the paragraph on Zero But True. If your
condition looks for sequences that are less than 5 and
C<< $piddle->at($left) >> is 7, and if you know that your quantifiers will
not allow a match of zero length, you should return a numeric 0 to indicate
that it is not possible for this condition to match.

Remember: if all you can say is
that the condition does not match for the range C<$left:$right>, but it
might match for the same value for C<$left> and a smaller value for
C<$right>, you should return a negative value instead of zero.

=item Negative Values

As I have already discussed, your condition may involve expensive
calculations, so rather than check each sub-piddle starting from C<$left>
and reducing C<$right> until you find a match, you can simply return -1.
That tells the regex engine that the current values of C<$left> and
C<$right> do not match the condition, but smaller values of C<$right> might
work. Generally speaking, returning zero is much stronger than returning -1,
and it is safer to return -1 when the match fails. It is also far more
efficient to return zero if you are certain that the match will fail for any
value of C<$right>.

However, you can return more than just -1. For example, if your condition
fails for C<$right> as well as C<$right - 1>, but beyond that it is
difficult to calculate, you can return -2. That tells the regular expression
engine to try a shorter range starting from left, and in particular that the
shorter range should be at least two elements shorter than the current
range.

=back

=head1 NOTES

Using this module will look a litte bit different from classic regular
expressions for many reasons:

=over

=item Numerical arrays, not strings

We are dealing with sequences of numbers, not sequences of characters. This
leads to some significant differences. With character-based regular
expressions, we are looking for specific characters or collections of
characters. With numerical data, we will rarely look for specific values;
instead we will look for sequences of data that have certain properties.

=item Different kinds of clustering

With string regular expressions, it is not very common to match a string
against patternA *and* patternB. Usually one pattern is a strict subset of
the other. This is not necessarily the case with numerical regular
expressions. For example, you may want to match against data that is both
positive and which has a negative slope. As such, this numerical regular
expression library lets you specify how you want collections of regular
expressions to be matched: A OR B OR C, A AND B AND C, A THEN B THEN C, etc.

Perl gets around this by assuming A THEN B THEN C, and using the infix OR
operator. I could do the same and supply an infix AND operator, but then I'd
have to create a concise syntax... see the next point.

=item No concise syntax

In Perl, you construct your regular expressions with a very concise string.
Perl then interprets the string and generates a regular expression object
from that string. This module is the first of its kind, as far as the author
is aware, so there is no clear idea of what would constitute a useful or
smart notation. Furthermore, it is also clear that end users will have all
sorts of matching criteria that I could never hope to anticipate. Rather
than try to impose an untested regular expression notation, this module
simply lets you construct the regular expression object directly.

=back

=head2 apply

Runs the regular expression object. It returns a value indicating the number
of values matched. A regular expression could, ostensible, match zero
elements, in which case the return value is "0 but true", which numerically
evaluates to 0 but logically evaluates to true.

=head1 Internals

All regex classes must inheret from NRE and must supply the following
functions:

=over

=item _prep

This function is called before the regular expression hammers on the supplied
piddle. If you have any setup or one-time evaluations to do, do them now.

Furthermore, if you know from the outset that the match will fail (because
the piddle is too long, or you have a positional condition that you can
easily check), you can return zero. If you do so, your particular regex will
never be applied. The C<_cleanup> method will, however, be called.

If your regex encloses another, it should call it's C<_prep> function
and take its return value into consideration with its own. If the enclosed 
regex returns 0, you must not execute it's C<_apply> or C<_check_size>
methods. You must call C<_cleanup> on your enclosed regex at least once,
though multiple calls to C<_cleanup> is allowed.

=item _apply

This function is called when it comes time to apply the regex to see if it
matches the current sub-piddle of interest. That sub-piddle is stored in
C<$a> and the full piddle is stored in C<$b>. You may inspect these and you
will be able to modify them, but you should not modify them unless you know
exactly what you're doing.

If the match succeeds, you should return the number of elements matched. If
it matched, but you do not consume anything, you should return "0 but true".
If it failed, you should return the numeric value 0.

If your regex encloses another, it should call the enclosed regex's C<_apply>
function and take its return value into consideration with its own, unless
it returned 0 when you called C<_prep>. In that case, you should not call it.

=item _cleanup

This method is called after the engine is done, regardless of whether it
matched or not, and regardless of whether it even ran. The C<_cleanup> may
be called multiple times, so be sure that you track that somehow.

=item _check_size ($new_size)

This function is called when the number of elements consumed by a regex must
be decreased. This only applies to quantified regexes, but since grouped
regexes can contain quantified regexes, group regexes have to know how to
take them. In general, this function is handled by the two absract classes
C<NRE::Quantified> and C<NRE::Grouped>, so if you inheret from them, you do
not need to worry about this.

If you are creating a new regex type that does not inheret from either of
the two abstract base classes, then you must modify whatever record keeping
you have of your internal state, and how that might change if you were asked
to decrease the number of elements you consumed. Your return value should
indicate whether or not you succeeded (for example, you could fail if you
were asked to consume less but you already consumed zero).

If your regex encloses another, you will probably need to call this on it,
unless your regex doees something magical. However, you must not call
C<_check_size> if the regex's C<_prep> function returned zero.

=back

=cut

# User-level method (calls low-level _apply method with full piddle as 'sub-piddle':
method apply ($piddle) {
	print "Applying regex\n" if $NRE::Verbose;
	# Prepare the regex for execution. This may involve computing low and
	# high quantifier limits, keeping track of $piddle, and other things.
	# This can fail if $piddle does not have enough elements for the
	# quantifier, for example.
	unless ($self->_prep($piddle)) {
		$self->_cleanup;
		return 0;
	}
	my $N = $piddle->dim(0);
	my $min_diff = $self->_min_size - 1;
	my $max_diff = $self->_max_size - 1;

	# Left and right offsets, maximal right offset, and number of consumed
	# elements:
	my ($l_off, $r_off, $max_r_off, $consumed);
	# Run through all sensible left and right offsets:
	START: for ($l_off = 0; $l_off < $N - 1 - $min_diff; $l_off++) {
		$max_r_off = $l_off + $max_diff;
		$max_r_off = $N-1 if $max_r_off >= $N;
		STOP: for ($r_off = $max_r_off; $r_off >= $l_off + $min_diff; $r_off--) {
			print "working with range $l_off:$r_off\n" if $NRE::Verbose;
			$consumed = $self->_apply($l_off, $r_off);
			last START if $consumed and $consumed >= 0;
		}
	}
	$self->_cleanup;
	
	return ($consumed, $l_off) if $consumed;
	return 0;
}

# Keepin' it simple:
func _new ($class, %args) {
	return bless \%args, $class;
}

method _min_size () {
	return $self->{min_size};
}

method _max_size () {
	return $self->{max_size};
}

method _check_size ($new_size) {
	return $self->_min_size <= $new_size && $new_size <= $self->_max_size;
}

method _prep ($piddle) {
	$self->_clear_stored_match;
	$self->{piddle} = $piddle;
	return 1;
}

method _cleanup () {
	delete $self->{min_size};
	delete $self->{max_size};
}

method _clear_stored_match () {
	return 0 unless exists $self->{name};
	delete $self->{matched_left};
	delete $self->{matched_right};
	return 0;
}

method _store_match ($left, $right) {
	# Only store the match if this is named
	return unless exists $self->{name};
	$self->{matched_left} = $left;
	$self->{matched_right} = $right;
}

=head2 get_offsets_for

Method to retrieve the left and right offsets from a successful named 
matched. Returns left and right if the named match succeeded, undef
otherwise. Note that for zero-width matches, the value of right will be one
less than the value of left. Here's an example of how to use it:

 if (my ($left, $right) = $regex->get_offsets_for('peak')) {
     # do something here with $left and $right
 }

=cut

method get_offsets_for ($name) {
	# Check if this regex is named and if its name matches the request:
	return ($self->{matched_left}, $self->{matched_right})
		if exists $self->{name} and $self->{name} eq $name;
	# This regex doesn't have anything useful, so return nothing:
	return;
}

=head2 get_slice_for

Convenience wrapper around C<get_offsets_for> which returns a slice
corresponding to the matched indices. This returns the undefined value (NOT
a null piddle) if the match failed or if the match has zero width.

=cut

method get_slice_for ($name) {
	if (my ($left, $right) = $self->get_offsets_for($name)) {
		# Can't return a slice if it has zero width:
		return undef if $right < $left;
		# Return the slice if it's OK:
		return $self->{piddle}->slice($left . ':' . $right);
	}
	
	# Otherwise return the undefined value:
	return undef;
}

package NRE::Quantified;
use parent -norequire, 'NRE';
use strict;
use warnings;
use Method::Signatures;
use Carp;

=head1 NRE::Quantified

The Quantified abstract base class inherets from the NRE abstract base class
and provides functionality for handling quantifiers, including parsing the
quantifier argument. If you need a regex object that handles quantifiers but
you do not care how it works, you should inheret from this base class and
override the C<_apply> method.

=cut

func _new ($class, %args) {
	# Build the new object:
	my $self = bless \%args, $class;
	
	print "Creating new $class\n" if $NRE::Verbose;
	
	# Parse the quantifiers:
	$self->_parse_quantifiers;
	
	# Make sure we have valid quantifiers; either both exist or neither:
	if (not exists $self->{low_quant} and exists $self->{high_quant}
		or exists $self->{low_quant} and not exists $self->{high_quant}) {
		croak("Internal error: either both or neither high and low quantifiers must be specified");
	}
	
	return $self;
}

method _parse_quantifiers () {
	my ($ref) = delete $self->{quantifiers};
	# Make sure the caller supplied a quantifiers key and that it's correct:
	croak("Quantifiers must be specified a defined value associated with key [quantifiers]")
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
			$to_check =~ s/%$//;
			# Make sure it's a number between 0 and 100:
			croak("Percentage quantifier must be a number; I got [$_]")
				unless $to_check =~ /\d/;
			croak("Percentage quantifier must be >= 0; I got [$_]")
				unless 0 <= $to_check;
			croak("Percentage quantifier must be <= 100; I got [$_]")
				unless $to_check <= 100;
		}
		# Check that non-percentage quantifiers are strictly integers:
		elsif ($_ !~ /^-?\d$/) {
			croak("Non-percentage quantifiers must be integers; I got [$_]");
		}
	}
	
	print "Got quantifiers as $ref->[0] and $ref->[1]\n" if $NRE::Verbose;
	
	# Put the quantifiers in self:
	$self->{min_quant} = $ref->[0];
	$self->{max_quant} = $ref->[1];
}

# Prepare the current quantifiers:
method _prep ($piddle) {
	# Call the base class's prep function:
	NRE::_prep($self, $piddle);
	
	# Compute and store the low and high quantifiers:
	my $N = $piddle->dim(0);
	foreach (qw(min max)) {
		my $quantifier = $self->{$_ . "_quant"};
		my $label = $_ . "_size";
		
		if ($quantifier =~ s/%$//) {
			$self->{$label} = int(($N - 1) * ($quantifier / 100.0));
		}
		elsif ($quantifier < 0) {
			$self->{$label} = int($N + $quantifier);
		}
		else {
			$self->{$label} = int($quantifier);
		}
	}
	
	# We could have a number of issues with scalar quantifiers (as opposed
	# to percentage quantifiers), that I need to check:
	if (
			   $N < $self->{min_size}		# base piddle is too small
			or $self->{min_size} > $N		# min_size too large
			or $self->{min_size} < 0		# min_quant was too negative
			or $self->{max_size} > $N		# max_size too large
			or $self->{max_size} < 0		# max_quant too negative
			or $self->{max_size}			# invalid
					< $self->{min_size}	#    range
	) {
		delete $self->{max_size};
		delete $self->{min_size};
		return 0;
	}
	
	return 1;
}

# No _apply, that must be supplied by the derived classes. The inheretted
# cleanup needs to be ammended:
method _cleanup () {
	# Call the base class's cleanup function:
	NRE::_cleanup($self, $piddle);
	# Remove the min and max sizes:
	delete $self->{min_size};
	delete $self->{max_size};
}

package NRE::Sub;
use parent -norequire, 'NRE::Quantified';
use strict;
use warnings;
use Method::Signatures;
use Carp;


=head2 NRE::SUB

This evaluates the supplied subroutine on the current subset of data. The
three arguments supplied to the function are (1) the full piddle under
consideration, (2) the left index offset under consideration, and (3) the
right index offset. If the match succeeds, return the number of matched
values. If the match succeeds but it consumed zero values (i.e. a zero-width
assertion), return the string "0 but true", which is a magical value in Perl
that evaluates to true in boolean context, which is numerically zero in
numeric context, and which does not gripe when converted from a string value
to a numeric value, even when you've activated warnings.

=cut


# This builds a subroutine regexp object:
sub NRE::SUB {
	croak("NRE::SUB takes one, two, or three arguments: NRE::SUB([[name], quantifiers], subref)")
		if @_ == 0 or @_ > 3;
	
	# Get the arguments:
	my $name = shift if @_ == 3;
	my $quantifiers = shift if @_ == 2;
	my $subref = shift;
	
	# Check that they actually supplied a subref:
	croak("NRE::SUB requires a subroutine reference")
		unless ref($subref) eq ref(sub {});
	
	$quantifiers = [1,1] unless defined $quantifiers;
	
	# Create the subroutine regexp:
	return NRE::Sub->_new(quantifiers => $quantifiers, subref => $subref
		, defined $name ? (name => $name) : ());
}

method _apply ($left, $right) {
	# Get the current length that we are using:
	my $size = $right - $left + 1;
	
	# Fail if the current length is smaller than our minimum
	return $self->_clear_stored_match if $size < $self->{min_size};
	
	# Apply the rule and see what we get:
	my $consumed = $self->{subref}->($self->{piddle}, $left, $right);
	
	croak("Subroutine regex consumed more than it was allowed to consume")
		unless $consumed <= $size;
	
	# Next check for negative return values as these mean "Try a length
	# shorter than the current one."
	if ($consumed < 0) {
		# Make sure the shorter length would still fall within the
		# acceptable bounds:
		return $self->_clear_stored_match
			if $size + $consumed < $self->{min_size};
		
		# Looks good, return the recommended shortening:
		return $consumed;
	}
	
	# A nonnegative return value may still be less than $size. If that is
	# the case, or if the return value is a numeric zero, return a failure.
	return $self->_clear_stored_match
		if not $consumed or $consumed < $self->{min_size};
	
	# Looks like we have a bonefied match. Store and return it:
	$self->_store_match($left, $left + $consumed - 1);
	return $consumed;
}

package NRE::ZeroWidthAssertion;
use parent -norequire, 'NRE::Quantified';
use strict;
use warnings;
use Method::Signatures;
use Carp;

sub NRE::ZWA {
	# If two arguments, assume the first is a name and the second is a
	# subroutine reference:
	croak("NRE::ZWA takes one or two arguments: NRE::ZWA([name], subref)")
		if @_ == 0 or @_ > 2;
	# Pull off the name if it's supplied:
	my $name = shift if @_ == 2;
	# Get and check the subref:
	my $subref = shift;
	croak("NRE::ZWA requires a subroutine reference")
		unless ref($subref) eq ref(sub{});
	
	# Return the constructed zero-width assertion:
	my $self = NRE::ZeroWidthAssertion->_new(quantifiers => [0,0],
		subref => $subref, defined $name ? (name => $name) : ());
	
}

method _apply ($left, $right) {
	croak("Internal error: $right is no less that $left in call to NRE::ZeroWidthAssertion::_apply")
		unless $right < $left;
	
	my $consumed = $self->{subref}->($self->{piddle}, $left, $right);
	croak("Zero-width assertions must consume zero elements")
		unless $consumed == 0;
	
	# presently woring here
	return $self->_clear_stored_match unless $consumed;
	
	# here, $right should be $left - 1:
	$self->_store_match($left, $right);
	
	return $consumed;
}

package NRE::Grouped;
# Defines grouped regexes, like OR, AND, and SEQUENCE
use parent -norequire, 'NRE';
use strict;
use warnings;
use Method::Signatures;
use Carp;

func _new ($class, %args) {
	# Build the new object:
	my $self = bless \%args, $class;
	
	croak("Grouped regexes must supply a key [regexes]")
		unless defined $self->{regexes};
	
	croak("You must give me at least one regex in your group")
		unless @{$self->{regexes}} > 0;
	
	# Check the regexes:
	foreach (@{$self->{regexes}}) {
		my $good = eval {$_->isa('NRE')};
		croak("Invalid regex") unless $good;
	}
	
	return $self;
}

# Derivatives must supply their own _apply

# _prep will call _prep on all its children and keep track of those that
# return true values. Success or failure is based upon the inherited method
# _prep_success.
method _prep ($piddle) {
	# Call the base class's prep function:
	NRE::_prep($self, $piddle);
	
	# Call the prep function for each of them, keeping track of whether or
	# not we fail.
	my @succeeded;
	foreach (@{$self->{regexes}}) {
		push @succeeded, $_ if $_->_prep($piddle);
	}
	
	# Store the regexes to apply and trigger cleanup if it's no good:
	$self->{regexes_to_apply} = \@succeeded;
	if (not $self->_prep_success) {
		$self->_cleanup;
		return 0;
	}
	
	# Cache the minimum and maximum number of elements to match:
	$self->_minmax;
	$self->{max_size} = $piddle->dim(0)
		if $self->{max_size} > $piddle->dim(0);
	# Check those values for sanity:
	if ($self->{max_size} < $self->{min_size}
			or $self->{min_size} > $piddle->dim(0)) {
		$self->_cleanup;
		return 0;
	}
	
	# If we're here, then all went well, so return as much:
	return 1;
}

# The default success happens when we plan to apply *all* the regexes
method _prep_success () {
	return @{$self->{regexes}} == @{$self->{regexes_to_apply}};
}

method _cleanup () {
	# Call the base class's cleanup function:
	NRE::_cleanup($self);
	
	# Call the cleanup method for each child regex:
	foreach (@{$self->{regexes}}) {
		$_->_cleanup;
	}
	# do *not* remove the regexes_to_apply since we'll use it in named
	# retrieval:
	# delete $self->{regexes_to_apply};
}

method _clear_stored_match() {
	# Call the parent's method:
	$self->SUPER::_clear_stored_match;
	# Call all the grouped regexes' clear function:
	foreach my $regex (@{$self->{regexes_to_apply}}) {
		$regex->_clear_stored_match;
	}
	# Always return zero:
	return 0;
}

method get_offsets_for ($name) {
	# Return this group's indices if it matches the request:
	if (my ($left, $right) = $self->SUPER::get_offsets_for($name)) {
		return ($left, $right);
	}
	
	# Check every sub-regex.
	foreach my $regex (@{$self->{regexes_to_apply}}) {
		if (my ($left, $right) = $regex->get_offsets_for($name)) {
			return ($left, $right);
		}
	}
	
	# Apparently we didn't find it:
	return;
}

=head2 NRE::OR

This takes a collection of regular expression objects and evaluates all of
them until it finds one that succeeds. This does not take any quantifiers.

=cut

package NRE::Or;
use parent -norequire, 'NRE::Grouped';
use strict;
use warnings;
use Method::Signatures;
use Carp;

# Called by the _prep method; sets the internal minimum and maximum match
# sizes.
method _minmax () {
	my ($full_min, $full_max);
	
	# Compute the min as the least minimum, and max as the greatest maximum:
	foreach my $regex (@{$self->{regexes_to_apply}}) {
		my $min = $regex->_min_size;
		my $max = $regex->_max_size;
		$full_min = $min if not defined $full_min or $full_min > $min;
		$full_max = $max if not defined $full_max or $full_max < $max;
	}
	$self->{min_size} = $full_min;
	$self->{max_size} = $full_max;
}

# Must override the default _prep_success method. If we have *any* regexes
# that will run, that is considered a success.
method _prep_success () {
	return @{$self->{regexes_to_apply}} > 0;
}

# Run all the regexes (that said they wanted to run). Return the first
# success that we find:
method _apply ($left, $right) {
	my @regexes = @{$self->{regexes_to_apply}};
	for (my $i = 0; $i < @regexes; $i++) {
		my $consumed = $regexes[$i]->_apply($left, $right);
		
		# If it matches, be sure to store the match and mark all the rest as
		# non-matching:
		if ($consumed) {
			$self->_store_match($left, $right);
			for ($i++; $i < @regexes; $i++) {
				$regexes[$i]->_clear_stored_match;
			}
			return $consumed;
		}
	}
	return 0;
}

func NRE::OR (@regexes) {
	return NRE::Or->_new(regexes => \@regexes);
}

=head2 NRE::AND

This takes a collection of regular expression objects and evaluates all of
them, returning true if all succeed. This does not take any quantifiers.

=cut

package NRE::And;
use parent -norequire, 'NRE::Grouped';
use strict;
use warnings;
use Method::Signatures;
use Carp;

# For example, suppose I have a sine wave, and I want to match against
# values that are negative and values that have a negative slope. This will
# say that the AND matched the longest length, in which all of the values
# have a negative value, but not all have a negative slope.
#
# I believe this has to do with how I interpret the return lengths. If the
# returned length is less than the imposed length, then the regex is saying,
# "I don't match on that full length, but I do match on this shorter
# length." The job of AND is to make sure that *all* regexes match on the
# *same length*.
#
# That means that I need to track the consumed value of each regex. When two
# consume different lengths, I need to re-check the regex that returned the
# longer length. Furthermore, although the regexes are *allowed* to return
# lengths shorter than the given range, but they are not required to do
# that. Which brings to mind a new kind of return value:
#
# Return value    means
#  full length    matches the provided lenth
#  > 0            matches, but less than the provided length
#  0 but true     matches zero (zero-width assertion)
#  0              fails to match
#  -1             fails to match *at this length*, try shorter length
#
# The last return value, -1, indicates, "This is an expensive or complicated
# operation. I do not want to check all possible lengths between 0 and the
# provided range. Please (oh regexp engine) decrement the range and try
# again."
#
# Note that you will never get -1 returned when calling the user-level
# C<apply> function. That is only an internal 

# Return false if any of them fail, return the max consumed if all succeed.
method _apply ($left, $right) {
	my $consumed_length = $right - $left + 1;
	my @regexes = @{$self->{regexes_to_apply}};
	for (my $i = 0; $i < @regexes; $i++) {
		my $consumed = $regexes[$i]->_apply($left, $right);
		# Return failure immediately:
		return $self->_clear_stored_match unless $consumed;
		
		# If it didn't fail, see if we need to adjust the goal posts:
		if ($consumed < $consumed_length) {
			# Negative consumption means "adjust backwards":
			$consumed += $consumed_length if $consumed < 0;
			
			# Adjust the right offset and start over:
			$right = $consumed + $left - 1;
			$i = 0;
			redo;
		}
	}
	
	# If we've reached here, we have a positive match. Store and return it:
	$self->_store_match($left, $consumed_length + $left - 1);
	return $consumed_length;
}

# Called by the _prep method; stores minimum and maximum match sizes in an
# internal cache:
method _minmax () {
	my ($full_min, $full_max);
	
	# Compute the min as the greatest minimum, and max as the least maximum:
	foreach my $regex (@{$self->{regexes_to_apply}}) {
		my $min = $regex->_min_size;
		my $max = $regex->_max_size;
		$full_min = $min if not defined $full_min or $full_min < $min;
		$full_max = $max if not defined $full_max or $full_max > $max;
	}
	$self->{min_size} = $full_min;
	$self->{max_size} = $full_max;
}

sub NRE::AND {
	# If the first argument is an object, assume no name:
	return NRE::And->_new(regexes => \@_) if ref $_[0];
	# Otherwise assume that the first argument is a name:
	my $name = shift;
	return NRE::And->_new(name => $name, regexes => \@_)
}

=head2 NRE::SEQUENCE

Applies a sequence of regular expressions in the order supplied. Obviously
this needs elaboration, but I'll ignore that for now. :-)

This operates recursively thu:

 1) If the (i-1)th regex succeeded, attempt to apply the ith regex at its
    full quantifier range. If that fails, decrement the range until it it
    succeeds. If that fails, consider it a failure of the (i-1th) regex at
    its current range. If it succeeds, move to the next regex.
 2) If the 1th regex fails, the match fails.
 3) If the Nth regex succeeds, return success.

=cut

package NRE::Sequence;
use parent -norequire, 'NRE::Grouped';
use strict;
use warnings;
use Method::Signatures;
use Carp;

# Return false if any of them fail, return the max consumed if all succeed.
method _apply ($left, $right) {
	my $consumed
		= $self->_seq_apply($left, $right, @{$self->{regexes_to_apply}});
	# Handle the stored matches based upon the success or failure of the
	# sequence:
	if ($consumed) {
		$self->_store_match($left, $left + $consumed - 1);
	}
	else {
		$self->_clear_stored_match;
	}
	return $consumed;
}

method _seq_apply ($left, $right, @regexes) {
	my $regex = shift @regexes;
	my $piddle = $self->{piddle};
	
	# Handle edge case of this being the only regex:
	return $regex->_apply($left, $right) if @regexes == 0;
	
	# Determine the largest possible size based on the requirements of the
	# remaining regexes:
	my $max_consumable = $right - $left + 1;
	$max_consumable -= $_->_min_size foreach (@regexes);
	
	# Fail if the maximum consumable size is smaller than this regex's
	# minimum requirement. working here: this condition may never occurr:
	my $min_size = $self->_min_size;
	return 0 if $max_consumable < $min_size;
	
	# Set up for the loop:
	my $max_offset = $max_consumable - 1 + $left;
	my $min_offset = $min_size - 1 + $left;
	my ($left_consumed, $right_consumed) = (0, 0);
	my $full_size = $right - $left + 1;
	
	SIZE: for (my $size = $max_consumable; $size > $min_size; $size--) {
		# Apply this regex to this length:
		$left_consumed = $self->_apply($left, $left + $size - 1);
		# Fail immediately if we get a numeric zero:
		return 0 unless $left_consumed;
		# If we got a negative number, update the size and try again:
		if ($left_consumed < 0) {
			# Check that the new size is valid:
			$size += $left_consumed;
			return 0 if $size < $min_size;
			# Try again at the new size:
			redo SIZE;
		}
		
		# Positive return values can be less than $size, but we should
		# update $size to compensate:
		$size = $left_consumed;
		
		# If we are here, we know that the current regex matched starting at
		# left with a size of $size. Now make sure that the remaining regexes
		# match:
		$right_consumed = 0;
		my $curr_right = $right;
		do {
			# Shrink the current right edge:
			$curr_right += $right_consumed;
			# Try the regex:
			$right_consumed = $self->_seq_apply($left + $size, $curr_right, @regexes);
		} while ($right_consumed < 0);
		
		# At this point, we know that the right regex either matched at the
		# current value of $curr_right with a width of $right_consumed, or
		# that it failed. If it failed, start over with the left regex:
		next OFFSET unless $right_consumed;
		
		# If we are here, then it succeeded and we have our return values.
		# Be sure to return "0 but true" if that was what was returned:
		return $left_consumed if $left_consumed + $right_consumed == 0;
		return $left_consumed + $right_consumed;
	}
	
	# We can only be here if the combined regexes failed to match:
	return 0;
}

# Called by the _prep method, sets the internal minimum and maximum sizes:
method _minmax () {
	my ($full_min, $full_max) = (0, 0);
	
	# Compute the min and max as the sum of the mins and maxes
	foreach my $regex (@{$self->{regexes_to_apply}}) {
		$full_min += $regex->_min_size;
		$full_max += $regex->_max_size;
	}
	$self->{min_size} = $full_min;
	$self->{max_size} = $full_max;
}

sub NRE::SEQUENCE {
	# If the first argument is an object, assume no name:
	return NRE::Sequence->_new(regexes => \@_) if ref $_[0];
	# Otherwise assume that the first argument is a name:
	my $name = shift;
	return NRE::Sequence->_new(name => $name, regexes => \@_)
}


# Unit tests to follow:
return 1 if caller;

package main;
use PDL;
$NRE::Verbose = 1;
 # Build the regular expression object first:
 my $positive_re = NRE::SUB(sub {
     # Supplied args are the piddle, the left slice offset,
     # and the right slice offset:
     my ($piddle, $left, $right) = @_;
     # A simple check for positivity:
     return ($right - $left + 1)
         if all $piddle->slice("$left:$right") > 0;
 });
 
 # A faster check for positivity:
 my $positive_re_fast = NRE::SUB(sub {
     # Supplied args are the piddle, the left slice offset,
     # and the right slice offset:
     my ($piddle, $left, $right) = @_;
     
     # This should not fail if called as a is *not* a zero-width assertion:
     
     
     # Ensure that the first element is positive:
     return 0 if $piddle->at($left) > 0;
     
     my $sub_piddle = $piddle->slice("$left:$right");
     # See if there are any negative values at all:
     if (any $sub_piddle <= 0) {
         # Find the first zero crossing:
         my $switch_offset = which($sub_piddle < 0)->min;
         # The offset of the first zero crossing
         # corresponds with the number of matched values
         return $switch_offset;
     }
     # If no negative values, then the whole thing matches:
     return $right - $left;
 });
 
 # Find the number of (contiguous) elements that match the regex:
 my $data = sequence(20);
 my ($matched, $offset) = $positive_re->apply($data);
 print "Matched $matched elements, starting from $offset\n";

=head1 Concise Syntax Ideas

A potential concise syntax might look like this:

 $regex = qnre{
    Optional::Package::Name           # package name
    reg1(args)[quantifiers]           # default cluster is a sequence
    reg2:named(args)[quantifiers]     # naming (capturing) a regex
    &<reg3(args)[quantifiers] reg4()> # AND group
    |< whatever >                     # OR group
    %< whatever >                     # XOR group
    $< whatever >                     # SEQUENCE group
    &to_retrieve< whatever >          # a named (captured) AND group
    reg5:othername                    # another captured regex
    $< New::Package                   # groups can specify their own scope
       $reg1                          # these regexes are defined
       $reg2                          #   in New::Package, not
    >                                 #   Optional::Package::Name
 };

If the first token looks like a package, then it is assumed to be the
package in which all the regex constructors are defined. If no package is
specified, the current package is assumed. After that, all tokens that look
like standard identifiers are assumed to be constructors (in the specified
package) that take the optional specified arguments and optional
quantifiers. Angle brackets denote clusters of one sort or another, and the
default clustering is a SEQUENCE cluster.

Anything can be captured by preceeding it with @name. If the eventual match
includes the capture, it can be retrieved with

 my ($left, $right) = $regex->get_capture('name');

which returns the left and right offsets of the captured region, or the
undefined values if the capture's regex did not succeed. To check if a
capture succeeded, simply use

 if ($regex->captured('name')) {
     # do somethingd
 }

=head1 SEE ALSO

Interesting article on finding time series that "look like" other time
series:

http://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.133.6186&rep=rep1&type=pdf

