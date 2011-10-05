package NRE;
use strict;
use warnings;
use Method::Signatures;
use Carp;

=head1 NAME

PDL::Regex - a numerical regular expression engine

=cut

our $VERSION = 0.01;

=head1 VERSION

This documentation is supposed to be for version 0.01 of PDL::Regex, but
it is woefully out of date as of yet and probably won't catch up to the
module's behavior for another few versions.

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
constructors for each condition already exist (I'll discuss those in a bit)

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

=head1 METHODS

These are the user-level methods that each regex provides. Note that this
section does not discuss constructors; those are discussed below.

=over

=item apply ($data)

This method applies the regular expression object on the given piddle. If
the regular expression matches the data, you get two return values: a number
indicating the quantity of elements matched, and a number indicating the
offset at which the match starts. However, there is a minor subtlety for a
match with zero length. In that case, the number of matched elements will be
the string '0 but true'. This way, the following three expressions all Do
Something:

 if (my ($matched, $offset) = $regex->apply($data)) {
     # Do Something
 }
 
 if (my $matched = $regex->apply($data)) {
     # Do Something 
 }
 
 if ($regex->apply($data)) {
     # Do Something
 }
 
Perl lets you use the returned matched length---even the string---in
arithmetic operations without issuing a warning. However, if you plan on
printing the matched length, you should make assure a numeric value with
something like this:

 if (my $matched = $regex->apply($data)) {
     $matched += 0; # ensure $matched is numeric
     print "Matched $matched elements\n";
 }

On the other hand, if the match fails, C<apply> returns an empty list.
Generaly, this means that if you do this:

 my ($matched, $offset) = $regex->apply($data);

both C<$matched> and C<$offset> will be the undefined value, and if you use
the expression in the conditional as in the first example above, the
condition will evaluate to boolean false. The only major gotcha in this
regard is that this will B<NOT> do what you think it is supposed to do:

 my ($first_matched, $first_off, $second_matched, $second_off)
     = ($regex1->apply($data), $regex2->apply($data));

If C<$regex1> fails to match and C<$regex2> succeeds, the values for the
second regex will be stored in C<$first_matched> and C<$first_off>. So, do
not use the return values from a regular expression in a large list
assignment.

You can retreive sub-matches of the regex by naming them and using
C<get_offsets_for>.

=cut

# User-level method, not to be overridden.
method apply ($piddle) {
	# Make sure they send us a piddle (working here - document this)
	croak('Numerical regular expressions can only be applied to piddles')
		unless eval {$piddle->isa('PDL')};
	
	# Prepare the regex for execution. This may involve computing low and
	# high quantifier limits, keeping track of $piddle, and other things.
	# This can fail if $piddle does not have enough elements for the
	# quantifier, for example.
	unless ($self->_prep($piddle)) {
		$self->_cleanup;
		$self->_post_cleanup;
		return;
	}
	$self->_post_prep;
	
	my $N = $piddle->dim(0);
	my $min_diff = $self->_min_size - 1;
	my $max_diff = $self->_max_size - 1;

	# Left and right offsets, maximal right offset, and number of consumed
	# elements:
	my ($l_off, $r_off, $consumed);
	# Run through all sensible left and right offsets:
	START: for ($l_off = 0; $l_off < $N - $min_diff; $l_off++) {
		# Start with the maximal possible r_off:
		$r_off = $l_off + $max_diff;
		$r_off = $N-1 if $r_off >= $N;
		
		STOP: while ($r_off >= $l_off + $min_diff) {
			$consumed = $self->_apply($l_off, $r_off);
			if ($consumed > $r_off - $l_off + 1) {
				my $class = ref($self);
				croak("Internal error: regex of class <$class> consumed more than it was given");
			}
			# If they returned less than zero, adjust r_off and try again:
			if ($consumed < 0) {
				# At the moment, negative values of $consumed that are "too
				# large" do not cause the engine to croak. Should this be
				# changed? working here (add this to the to-do list)
				$r_off += $consumed;
				next STOP;
			}
			# We're done if we got a successful match
			if ($consumed and $consumed >= 0) {
				$self->_store_match($l_off, $r_off);
				last START;
			}
			# Move to the next starting position if the match at this
			# position failed:
			last STOP if $consumed == 0;
		}
	}
	$self->_cleanup;
	$self->_post_cleanup;
	
	# If we were successful, return the details:
	if ($consumed) {
		return $consumed unless wantarray;
		return (0 + $consumed, $l_off);
	}
	# Otherwise return an empty list:
	return;
}

=item get_offsets_for ($name)

After running a successful regex, you can use this method to query the
offsets for named regexes. This method returns a piddle containing the left
and a piddle containing the right offsets. If the named match failed, it
returns an empty list, which evaluates to false in boolean context. That
means you can do cool stuff like this:

 if (my ($left, $right) = $regex->get_offsets_for('peak')) {
     # do something here with $left and $right
 }

Note that for zero-width matches, the value of right will be one less than
the value of left. 

It can happen that the B<same> named regex shows up multiple times in a
larger regex. In that case, all such copies that succeed in a match will
add entries to the resulting C<$left> and C<$right> piddles.

=cut

method get_offsets_for ($name) {
	# Croak unless this regex has this name:
	croak("Unknown regex name $name")
		unless defined $self->{name} and $self->{name} eq $name;
	
	return $self->_get_offsets;
}

=back

=head1 Return Values

working here - this needs to be cleaned up

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

=item More than the Full Length

You sould never return more than the full length, and if you do, the regex
engine will croak saying

 Internal error: regex of class <class> consumed more than it was given

doc working here - add this to the list of errors reported.

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

=item Zero, i.e. failed match

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















=head1 Internals

All regex classes must inheret from NRE or a class derived from it. This
section of documentation discusses how you might go about doing that. You
are encouraged to override any of the methods of NRE or its derivatives,
except for the C<apply> method.

=head2 Required Methods

If your class derives directly from NRE, you must supply the following
internal methods:

=over

=item _apply

This function is called when it comes time to apply the regex to see if it
matches the current range. That arguments to the apply function are the left
and right offsets, respectively. (The piddle is not included, and you should
make sure that you've cached a reference to the piddle during the C<_prep>
phase.)

If your regex encloses another, it should call the enclosed regex's C<_apply>
function and take its return value into consideration with its own, unless
it returned 0 when you called C<_prep>. In that case, you should not call it.

working here - find and move the documentation about return values to this
position in the documentation.

If the match succeeds, you should return the number of elements matched. If
it matched, but you do not consume anything, you should return "0 but true".
If it failed, you should return the numeric value 0.

=back

=head2 Optional Methods

The base class provides a number of methods that you can override if you
wish. Here is what each of those methods are supposed to do:

=over

=item _new ($class, %args)

The role of the constructor is to create a blessed hash with any internal
data representations. Note that user-level constructors wrap around the
C<_new> function and often perform their own data validation and internal
data construction, so you can keep C<_new> pretty minimal if you like. The
default constructor simply takes the first argument as the class name and
the remaining arguments as key => value pairs (croaking if there is not an
even number of remaining arguments) and blesses the hash of key => value
pairs into the supplied class.

Between C<_new> and the user-level constructor, the object that comes out
must be capable of running its C<_prep> method.

=cut

func _new ($class, @args) {
	croak("Internal Error: args to NRE::_new must have a class name and then key => value pairs")
		unless @args % 2 == 0;
	my $self = bless {@args}, $class;
	
	# Add a stack for everything that needs to be stashed:
	$self->{"old_$_"} = [] foreach $self->_to_stash;
	
	return $self;
}

=item _prep ($piddle)

This function is called before the regular expression hammers on the supplied
piddle. If you have any piddle-specific setup to do, do it in this function.

From the standpoint of internals, you need to know two things: what this
function should prepare and what this function should return. (For a
discussion on intepreting return values from C<_prep>, see NRE::Grouped.)

If you are not deriving your class from NRE::Quantified or NRE::Grouped and
you intend for your regex to run, you must either set C<< $self->{min_size} >>
and C<< $self->{max_size} >> at this point or you must override the
related internal functions so that they operate correctly without having
values associated with those keys.

If, having examined the piddle, you know that this regex will not match, 
you should return zero. This guarantees that the following functions
will not be called on your regex during this run: C<_apply>, C<_min_size>,
C<_max_size>, and C<_store_match>. Put a little bit
differently, it is safe for any of those functions to assume that C<_prep>
has been called and was able to set up internal data that might be required
for their operation. Furthermore, if you realize in the middle of C<_prep>
that your regex cannot run, it is safe to return 0 immediately and expect
the parent regex to call C<_cleanup> for you. (working here - make sure the
documentation for NRE::Grouped details what Grouped regexes are supposed to
do with C<_prep> return values.)

working here - have the *containers* call _store_match

Your regex may still be querried afterwards for a match by
C<get_offsets_for> or C<get_slice_for>, regardless of the return value of
C<_prep>. In both of those cases, returning the undefined value,
indicating a failed match, would be the proper thing to do.

The C<_prep> method is called as the very first step in C<apply>.

=cut

# Make sure this only gets run once per call to apply:
method _prep ($piddle) {
	return 1 if $self->{is_prepping};
	$self->{is_prepping} = 1;
	
	$self->_stash() if defined $self->{piddle};
	
	# Set defaults for all of the items in the stash except min_size and
	# max_size, which must be set by the derived class's _prep
	# working here - make sure that last requirement is documented
	$self->{left_matches} = [];
	$self->{right_matches} = [];
	$self->{piddle} = $piddle;
	return 1;
}

method _to_stash () {
	return qw (piddle min_size max_size);
}

=item _stash

working here - rewrite, this realy *is* an internal function

This is what is called when you need to stash old copies of internal data.
This happens when your regex is used as a smaller part of a regex, and also
when it is called within the execution of a condition. Basically, if you 
override C<_prep> to initialize any internal data during C<_prep>, you must
override C<_stash> to back it up.

When you override this method, you must call the parent with
C<< $self->SUPER::_stash($piddle) >> in your overridden method. Otherwise,
internal data needed by the base class will not be properly backed up.

=cut

method _stash () {
	# Stash everything:
	foreach ($self->_to_stash) {
		push @{$self->{"old_$_"}}, $self->{$_};
	}
	
	# Store the match stack, if appropriate:
	if (defined $self->{name}) {
		push @{$self->{old_left_matches}}, $self->{left_matches};
		push @{$self->{old_right_matches}}, $self->{right_matches};
	}
}

method _post_prep () {
	delete $self->{is_prepping};
}

=item _min_size, _max_size

These are getters and setters for the current lengths that indicate the
minimum and maximum number of elements that your regex is capable of
matching. The base class expects these to be set during the C<_prep> phase
after afterwards consults whatever was stored there. Because of the
complicated stack management, you would be wise to stick with the base class
implementations of these functions.

working here - make sure grouped regexes properly set these during the
_prep phase.

Note that at the moment, C<_min_size> and C<_max_size> are not querried
during the actual operation of the regex. In other words, there's little
point in overriding these methods at given the current architecture of the
regex engine at the moment.

You are guaranteed that C<_prep> will have been run before these methods are
run, and they will not be run if C<_prep> returned a false value. If you
call the base class's prep, you are also guaranteed that if min_size or
max_size are keys in the object, they will be the default values.

=cut

method _min_size ($new_value?) {
	$self->{min_size} = $new_value if defined $new_value;
	return $self->{min_size};
}

method _max_size ($new_value?) {
	$self->{max_size} = $new_value if defined $new_value;
	return $self->{max_size};
}

=item _cleanup

This method is called in one of two situations: (1) if you just returned 
zero from C<_prep> and (2) after the engine is done, regardless of whether
the engine matched or not. C<_cleanup> should only be called once, but your
code needs to be flexible enough to accomodate multiple calls to C<_cleanup>
without dying.

=cut

use PDL::Lite;

method _cleanup () {
	return if $self->{is_cleaning};
	$self->{is_cleaning} = 1;

	# finalize the match stack
	$self->{final_left_matches} = PDL->pdl($self->{left_matches});
	$self->{final_right_matches} = PDL->pdl($self->{right_matches});
	
	# Unstash everything:
	$self->_unstash if defined $self->{old_piddles}->[0];
}

method _unstash () {
	# Unstash everything:
	foreach ($self->_to_stash) {
		$self->{$_} = pop @{$self->{"old_$_"}};
	}
	
	# Restore the previous match stack, if appropriate:
	if (defined $self->{name}) {
		$self->{left_matches} = pop @{$self->{old_left_matches}};
		$self->{right_matches} = pop @{$self->{old_right_matches}};
	}
}

method _post_cleanup () {
	delete $self->{is_cleaning};
}

=back

=head2 Matching

A number of functions facilitate homogeneous behavior for named regular
expressions, which are supposed to keep track of the indices that matched.
These functions do that:

=over

=item _store_match ($left_offset, $right_offset)

This is a convenience function provided by the base class that stores the
left and right offsets with the keys C<matched_left> and C<matched_right>,
respectively, but only if the regex is named.

=cut

method _store_match ($left, $right) {
	# Only store the match if this is named
	return unless exists $self->{name};
	push @{$self->{left_matches}}, $left;
	push @{$self->{right_matches}}, $right;
}

=item _clear_stored_match

Grouping regexes like
AND, OR, and SEQUENCE need to have some way of clearing a stored match when
something goes wrong (or right, in the case of OR), and they do this by
calling C<_clear_stored_match>. In the base class's behavior, this function
only runs when there is a name associated with the regex. Grouping regex
objects should probably consider clearing their children regexes, in
addition to clearing their own values.

=cut

method _clear_stored_match () {
	return 0 unless exists $self->{name};
	pop @{$self->{left_matches}};
	pop @{$self->{right_matches}};
	return 0;
}

=item get_offsets_for ($name)

This is a user-level function that ... working here

If you override this 

=item get_slice_for ($name)

Convenience wrapper around C<get_offsets_for> which returns a slice
corresponding to the matched indices. This returns the undefined value (NOT
a null piddle) if the match failed or if the match has zero width.

=item _add_name ($hashref)

This method adds this regex's name (along with a reference to itself) to the
supplid hashref. This serves two purposes: first, it gives the owner a fast
way to look up named references if either of the above accessors are called.
Second, it provides a means at construction time (as opposed to evaluation
time) to check that no two regexes share the same name. If you overload this
method, you should be sure to add your name and reference to the list (if
your regex is named) and if yours is a grouping regex, you should also check
for and add all of your childrens' names. Note that if your regex's name is
already taken, you should croak with a meaningful message, like

 Found multiple regular expressions named $name.

working here - discuss more in the group discussion

=cut

method _add_name_to ($hashref) {
	return unless exists $self->{name};
	
	my $name = $self->{name};
	# check if the name exists:
	croak("Found multiple regular expressions named $name")
		if exists $hashref->{$name} and $hashref->{$name} != $self;
	# Add self to the hashref under $name:
	$hashref->{$name} = $self;
}

=item _get_offsets

This internal function returns two piddles of this object's left and right
offsets, if the regex matched on the previous application, and an empty list
if not. This function should only be called internally by get_offsets_for,
which knows which object goes with which name.

If you attempt to call this on an unnamed regex, this will throw an error
saying:

 Called _get_offsets on regex that has no name!

You should only overload this function if you intend to alter how your
class handles its offset memory management.

=cut

method _get_offsets () {
	croak("Called _get_offsets on regex that has no name!")
		unless defined $self->{name};
	
	# Return the stored results if this regex matched:
	return ($self->{final_left_matches}, $self->{final_right_matches})
		unless $self->{final_left_matches}->isempty;
	
	# This regex didn't match, so return nothing:
	return;
}

=back

=cut

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

func _new ($class, @args) {
	# Build the new object:
	my $self = NRE::_new($class, @args);
	
	# Parse the quantifiers:
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
	
	# Put the quantifiers in self:
	$self->{min_quant} = $ref->[0];
	$self->{max_quant} = $ref->[1];
	
	return $self;
}

# Prepare the current quantifiers:
method _prep ($piddle) {
	# Call the base class's prep function:
	NRE::_prep($self, $piddle);
	
	# Compute and store the min and max quantifiers:
	my $N = $piddle->dim(0);
	my ($min_size, $max_size);
	my $min_quant = $self->{min_quant};
	my $max_quant = $self->{max_quant};
	
	if ($min_quant =~ s/%$//) {
		$min_size = int(($N - 1) * ($min_quant / 100.0));
	}
	elsif ($min_quant < 0) {
		$min_size = int($N + $min_quant);
	}
	else {
		$min_size = int($min_quant);
	}
	if ($max_quant =~ s/%$//) {
		$max_size = int(($N - 1) * ($max_quant / 100.0));
	}
	elsif ($max_quant < 0) {
		$max_size = int($N + $max_quant);
	}
	else {
		$max_size = int($max_quant);
	}
	
	# We could have a number of issues with scalar quantifiers (as opposed
	# to percentage quantifiers), that I need to check:
	if (
			   $N < $min_size			# base piddle is too small
			or $min_size > $N			# min_size too large
			or $min_size < 0			# min_quant was too negative
			or $max_size > $N			# max_size too large
			or $max_size < 0			# max_quant too negative
			or $max_size < $min_size	# invalid range
	) {
		return 0;
	}
	
	# If we're good, store the sizes:
	$self->_min_size($min_size);
	$self->_max_size($max_size);
	return 1;
}

# I don't need to override _stash or _cleanup because they already handle
# the size information. Also, I do not supply an _apply because that must be
# provided by the derived classes.

package NRE::Any;
use parent -norequire, 'NRE::Quantified';
use strict;
use warnings;
use Method::Signatures;
use Carp;

=head2 NRE::ANY

Creates a regex that matches any value.

=cut

sub NRE::ANY {
	croak("NRE::ANY takes one or two optional arguments: NRE::ANY([[name], quantifiers])")
		if @_ > 2;
	
	# Get the arguments:
	my $name = shift if @_ == 2;
	my $quantifiers = shift if @_ == 1;
	$quantifiers = [1,1] unless defined $quantifiers;
	
	# Create the subroutine regexp:
	return NRE::Any->_new(quantifiers => $quantifiers
		, defined $name ? (name => $name) : ());
}

method _apply ($left, $right) {
	return $right - $left + 1;
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
#	my $size = $right - $left + 1;
	
#	# Fail if the current length is smaller than our minimum
#	return 0 if $size < $self->_min_size;
	
	# Apply the rule and see what we get:
	my $consumed = $self->{subref}->($self->{piddle}, $left, $right);
	
#	croak("Subroutine regex consumed more than it was allowed to consume")
#		unless $consumed <= $size;
	
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
	
#	# presently woring here
#	return $self->_clear_stored_match unless $consumed;
	
	# here, $right should be $left - 1:
#	$self->_store_match($left, $right);
	
	return $consumed;
}

package NRE::Grouped;
# Defines grouped regexes, like OR, AND, and SEQUENCE
use parent -norequire, 'NRE';
use strict;
use warnings;
use Method::Signatures;
use Carp;

func _new (@args) {
	# Build the new object:
	my $self = NRE::_new(@args);
	
	croak("Grouped regexes must supply a key [regexes]")
		unless defined $self->{regexes};
	
	croak("You must give me at least one regex in your group")
		unless @{$self->{regexes}} > 0;
	
	# Check the regexes and add their names:
	$self->{names} = {};
	foreach (@{$self->{regexes}}) {
		croak("Invalid regex") unless eval {$_->isa('NRE')};
		$_->_add_name_to($self->{names});
	}
	
	# Adding self to the list of names, if self is named, to simplify the
	# logic later:
	$self->{names}->{$self->{name}} = $self if defined $self->{name};
	
	return $self;
}

# Derivatives must supply their own _apply

method _to_stash () {
	return qw(regexes_to_apply positive_matches), $self->SUPER::_to_stash;
}

# _prep will call _prep on all its children and keep track of those that
# return true values. Success or failure is based upon the inherited method
# _prep_success.
method _prep ($piddle) {
	# Call the base class's prep function:
	NRE::_prep($self, $piddle);
	
	# Call the prep function for each of them, keeping track of all those
	# that succeed:
	my @succeeded;
	foreach (@{$self->{regexes}}) {
		push @succeeded, $_ if $_->_prep($piddle);
	}
	
	# Store the regexes to apply. If _prep_success returns zero, we do not
	# need to call cleanup: that will be called by our parent:
	$self->{regexes_to_apply} = \@succeeded;
	return 0 unless $self->_prep_success;
	
	# Cache the minimum and maximum number of elements to match:
	$self->_minmax;
	$self->_max_size($piddle->dim(0)) if $self->_max_size > $piddle->dim(0);
	# Check those values for sanity:
	if ($self->_max_size < $self->_min_size
			or $self->_min_size > $piddle->dim(0)) {
		return 0;
	}
	
	# working here - ensure to add to use this
	$self->{positive_matches} = [];
	
	# If we're here, then all went well, so return as much:
	return 1;
}

# The default success happens when we plan to apply *all* the regexes
method _prep_success () {
	return @{$self->{regexes}} == @{$self->{regexes_to_apply}};
}

method _cleanup () {
	return if $self->{is_cleaning};
	
	# Call the cleanup method for *all* child regexes:
	foreach (@{$self->{regexes}}) {
		$_->_cleanup;
	}
	
	# Call the base class's cleanup function:
	NRE::_cleanup($self);
}

# Needs to call children's post_prep
method _post_prep () {
	$self->SUPER::_post_prep;
	foreach my $regex (@{$self->{regexes_to_apply}}) {
		$regex->_post_prep;
	}
}

# Post cleanup is innocuous, so call it on all the regexes:
method _post_cleanup () {
	$self->SUPER::_post_cleanup;
	foreach (@{$self->{regexes}}) {
		$_->_post_cleanup;
	}
}

# Clear stored match assumes that all the regexes matched, so this will
# need to be overridden for OR:
method _clear_stored_match() {
	# Call the parent's method:
	$self->SUPER::_clear_stored_match;
	$self->_clear_matched_regexes;
	# Always return zero:
	return 0;
}

method _save_as_matched ($left, $right, @regexes) {
	push @{$self->{positive_matches}}, @regexes;
	$_->_store_match($left, $right) foreach @regexes;
}

method _clear_matched_regexes () {
	# Call all the positively matched regexes' clear function:
	foreach my $regex (@{$self->{positive_matches}}) {
		$regex->_clear_stored_match;
	}
}

method get_offsets_for ($name) {
	# This is a user-level function. Croak if the name does not exist.
	croak("Unknown regex name $name") unless exists $self->{names}->{$name};
	
	return $self->{names}->{$name}->_get_offsets;
}

# This is only called by regexes that *hold* this one, in the process of
# building their own name tables. Add this and all children to the hashref.
method _add_name_to ($hashref) {
	# Go through each named value in this group's collection of names:
	while( my ($name, $ref) = each %{$self->{names}}) {
		croak("Found multiple regular expressions named $name")
			if defined $hashref->{$name} and $hashref->{$name} != $ref;
		
		$hashref->{$name} = $ref;
	}
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
	$self->_min_size($full_min);
	$self->_max_size($full_max);
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
	foreach my $regex (@regexes) {
		my $consumed = $regex->_apply($left, $right);
		
		# If it matches, be sure to clear out previous stored matches call
		# the _store_match on this regex, and store it:
		if ($consumed) {
			$self->_clear_matched_regexes;
			$self->_save_as_matched($left, $right, $regex);
			return $consumed;
		}
	}
	return 0;
}

# working here - clear stored match

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
		return 0 unless $consumed;
		
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
	
	# If we've reached here, we have a positive match. Have all the
	# sub-sub-regexes store it. I do this outside the loop to avoid
	# unnecessary storage and match operations.
	$self->_save_as_matched($left, $consumed_length + $left - 1, @regexes);
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
	$self->_min_size($full_min);
	$self->_max_size($full_max);
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
	return $consumed;
}

method _seq_apply ($left, $right, @regexes) {
	my $regex = shift @regexes;
	my $piddle = $self->{piddle};
	
	# Handle edge case of this being the only regex:
	if (@regexes == 0) {
		my $consumed = $regex->_apply($left, $right);
		$self->_save_as_matched($left, $left + $consumed - 1, $regex)
			if $consumed;
		return $consumed;
	}
	
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
		# Store the left match (the right one was already stored):
		$self->_save_as_matched($left, $left + $size - 1, $regex);
		
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
	$self->_min_size($full_min);
	$self->_max_size($full_max);
}

sub NRE::SEQUENCE {
	# If the first argument is an object, assume no name:
	return NRE::Sequence->_new(regexes => \@_) if ref $_[0];
	# Otherwise assume that the first argument is a name:
	my $name = shift;
	return NRE::Sequence->_new(name => $name, regexes => \@_)
}

# THE magic value that indicates this module compiled correctly:
1;

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

=head1 TODO

These are items that are very important or even critical to getting the
regular expression engine to operate properly.

It seems that the underlying issue is that a regex object 

=over

=item Multiple copies of the same regex

It can easily happen that, while building a regex structure, I include a
previously constructed regex object multiple times. This should work just
fine as long as (1) the regex is not named and (2) the regex does not hold
any critical information internally. It seems reasonable to assume that a
complicated regex could use some sort of caching strategy, and if that's the
case, how do we handle it? Or, do we simply leave it to the programmer of
the complicated regex to watch out for such situations with some tricky code
in the C<_prep> function?

I believe that multiple copies of the same regex (and an implementation of
grouping quantifiers that would depend upon this) can be solved by doing
the following:

First, keep a stack of matched offests. Matches should only be be run in
sequence, so if a match fails, it should be able to pop off the last element
of the stack.

Second, keep the stack under a seperate key from the final output results.
This way, C<_cleanup> can copy the current stack to the output results and
clear off the stack, leaving any out scope ready to work.

Third, when named matches are requested, return two arrays of left and right
offsets rather than two integers. Actually, we can be a bit better here: if
the stack has only a single entry, then return the integers. Otherwise
return array refs. Or, even better: return piddles with the offsets!

On the other hand, if slices are requested... let's just drop support for
slices.

=item Regexes within Rules

Even more likely and problematic than the above problem is the possibility
that a particular regex object is used within a regex as well as B<within
the condition of neighboring regex>. This is very much a problem since a
regex used within the condition of another will B<not> be name-clash
detected and it will fiddle with internal data, including the current piddle
of interest.

Initially, I thought it would be adequate to implement a stack system on
C<_prep> and C<_cleanup>. However, named regexes need to be able to return
their offsets after C<_cleanup> is called, so these must B<not> be
cleaned-up. To solve this problem, I need to determine some means for the
regex to realize that it has switched contexts, and then stash or unstash
the internal information like the match offsets and the piddle (and anything
else that's important.)

=item Concise Syntax Ideas

A potential concise syntax might look like this:

 $regex = qnre{
    # Comments and whitespace are allowed
    
    # If there is more than one regex in a row, the grouping
    # is assumed to be a SEQUENCE group.
    
    # ---( Basics )---
    # Perl scalars and lists are properly interpolated:
    $my_regex_object
    @my_regex_objects
    
    # barewords are assumed to be regex constructors
    # and are called with the given args
    reg1(args)
    
    # The interior of an argument list is pased *exactly* as is to the
    # constructor:
    reg2( value => $quantitiy, %other_args )
    
    # square bracket notation indicates the min
    # and max length that a regex can match
    reg1(args)[quantifiers]
    
    # ---( Prefixes )---
    # Barewords are called as-is unless you specify an auto-prefix:
    PDL::Regex::OneD::
    
    # Now these constructors have that prefix added so:
    reg1(args)
    # is interpreted as PDL::Regex::OneD::reg1(args)
    
    # You can explicitly resolve a constructor like so:
    PDL::Regex::Extra::reg3(args)
    
    # To restore the original prefix, simply use two colons:
    ::
    
    # ---( Quantifiers )---
    # You can add square brackets immediately after a regex's args to
    # indicate the min and max length. This set's reg2 to match between
    # 1 and 50 elements:
    reg2(args)[1, 50]
    # This matches betwen 1% and 50% of the data set's length:
    reg2(args)[1%, 50%]
    # If the dataset is N elements long, this matches between 0.5 * N
    # and N - 10 elements:
    reg3(args)[50%, -10]
    # Args are not required:
    reg3[20%, -4]
    # These two statements are equivalent:
    reg3[50%, 100%]
    reg3[50%, -0]
    
    # ---( Grouping )---
    # Grouping is designated with a symbol and angle brackets:
    &< ... regexes ... >       # AND group
    |< ... >                   # OR group
    %< ... >                   # XOR group
    $< ... >                   # SEQUENCE group
    
    # Prefixing is lexically scoped and inherets from outside prefix
    My::Prefix::      # Set the current prefix
    reg1              # this is My::Prefix::reg1
    $<
       reg4           # this is My::Prefix::reg4
       ::             # set no-prefix
       reg1           # this is just reg1
       reg2           # this is just reg2
    >
    reg3              # this is My::Prefix::reg3
    
    
    # ---( Repeat counts )---
    # In addition to setting quantifiers, you can also set repeat counts.
    # Repeat count comes before a regex:
    *reg1(args)             # zero-or-more copies of reg1
    ?reg2                   # zero-or-one copies of reg2
    +reg3[10%, 50%]         # one-or-more copies of reg3, each of which
                            #   should consume between 10% and 50% of the
                            #   length of the dataset
    5:reg1(args)          # repeat exactly 5 times
    [4, 6]:reg4           # repeat reg4 between 4 and 6 times
    [4, ]:reg4            # repeat reg4 4 or more times
    [, 4]:reg4            # repeat reg4 zero to 4 times
    
    
    # ---( Naming and Capturing )---
    # You can name any normal regex by adding .name immediately after the
    # constructor name, before any arguments or quantifiers:
    reg2.name
    reg4.name(args)
    reg5.name[5, 20%]
    
    # You can name any grouped regex by inserting the name between the
    # symbol and the angle brackets:
    $.my_sequence< ... >
    |.my_or< ... >
    # Spaces are allowed:
    & . named < ... >
    
    # You can name a repetition by putting the name before the colon:
    5.name:reg2
    
    # You can name both the repetition and the regex, but they must have
    # different names:
    [4,8].name:reg2.name2
    
    # Once named, you can insert a previous named regex like so:
    \name
    
    
    # ---( Clarifications )---
    # Note, this statement is not formatted clearly:
    regex(args)[repeat, count] 
        :regex2(args)
    # It means this:
    regex(args)
    [repeat, count]:regex2(args)
    
 };

I would use Devel::Declare to convert this into a set of nested
constructors.

=head1 IDEAS

This is the place where I put my ideas that I would like to implement, but
which are not yet implemented and which are not critical to the sensible
operation of the regular expression engine.

=over

=item Grouping quantifiers

It would be nice to be able to combine quantifiers and groups. A major issue
in this would be figuring out how to handle named captures for such a
situation.

=item OPTIMIZE Grouping

Include some sort of OPTIMIZE grouping that attempts to partition the data
in an optimal fashion using some sort of scoring mechanism?

 # Find the optimal division between an exponential drop
 # and a linear fit:
 my $regex = NRE::OPTIMIZE($exponential_drop, $linear)

=back

=head1 SEE ALSO

Interesting article on finding time series that "look like" other time
series:

http://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.133.6186&rep=rep1&type=pdf



