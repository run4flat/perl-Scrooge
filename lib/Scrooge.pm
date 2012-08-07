package Scrooge;
use strict;
use warnings;
use Carp;
use Exporter;
use PDL;

# working here - check the latest switch to 'details' instead of left+right
# and modify MSER to pass details back as part of the results. Modify the
# test suite to make use of these details. Also update the testing of the
# order of operations since the call structure may have changed a fair
# amount.

our @ISA = qw(Exporter);

our @EXPORT = qw(re_or re_and re_seq re_sub re_any
		 re_zwa re_anchor_begin re_anchor_end 
		 re_named_seq re_named_and re_named_or);

=head1 NAME

Scrooge - a greedy pattern engine for arbitrary objects, like PDLs

=cut

our $VERSION = 0.01;

=head1 VERSION

This documentation is supposed to be for version 0.01 of Scrooge.

=head1 SYNOPSIS

 use Scrooge;
 
 # Build the pattern object first. This one
 # matches positive values and assumes it is working with
 # piddles.
 my $positive_re = re_sub(sub {
     # Supplied args (for re_sub, specifically) are the
     # object (in this case assumed to be a piddle), the
     # left slice offset, and the right slice offset:
     my ($piddle, $left, $right) = @_;
     
     # A simple check for positivity. Notice that
     # I return the difference of the offsets PLUS 1,
     # because that's the number of elements this pattern
     # consumes.
     return ($right - $left + 1)
         if all $piddle->slice("$left:$right") > 0;
 });
 
 # Find the number of (contiguous) elements that match that pattern:
 my $data = sequence(20);
 my ($matched, $offset) = $re->apply($data);
 print "Matched $matched elements, starting from $offset\n";
 
 # ... after you've built a few patterns ...
 
 # Matches pattern a, b, or c:
 my ($matched, $offset)
     = re_or( $re_a, $re_b, $re_c )->apply($data);
 
 # Matches pattern a, b, and c:
 my ($matched, $offset)
     = re_and ( $re_a, $re_b, $re_c )->apply($data);
 
 # Matches first, then second, then anything, then third
 my ($matched, $offset)
     = re_seq ( $re_first, $re_second, re_any, $re_third )
               ->apply($data);

=head1 DESCRIPTION

Scrooge creates a set of classes that let you construct greedy pattern objects
that you can apply to a container object such as an anonymous array or a piddle.
Because the patterns you might match are limitless, and the sort of container
you might want to match is also limitless, this module provides a means for
easily creating your own patterns and the glue necessary to put them together
in complex ways. It does not offer a concise syntax, but it provides the
back-end machinery to support such a concise syntax for various data containers
and applications.

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

The Scrooge equivalents of these take up quite a bit more space to
construct. Here is how to build a pattern that checks for a positive number
followed by a local maximum, or a negative number followed by a local minimum.

 use Scrooge::PDL;
 my $pattern = re_or(
     re_seq( re_greater_than(0), re_local_max ),
     re_seq( re_less_than(0), re_local_min )
 );

You would then apply that pattern to some data like so:

 do_something() if $pattern->apply($data);

The Scrooge pattern matching library can be conceptually structured into three
tiers. The top-level tier is a set of functions that help you quickly build
patterns and contain functions such as C<re_seq> and C<re_any>. The mid-level
tier is the set of classes that actually implement that functionality such as
C<Scrooge::Any>, C<Scrooge::Quantified>, and C<Scrooge::And>, along
with how to create your own classes. The bottom-level tier is the Scrooge base
class and its internal workings as a pattern matching engine. The documentation
that follows progresses from top to bottom.

=head1 BUILDING PATTERNS

From the standpoint of basic pattern building, there are two important types of
patterns: atom patterns and grouping patterns. Atom patterns specify a
characteristic that you want to match in your series; grouping patterns give you
the means to assemble collections of atoms into complex groups.

As a simple example, let's examine a hypothetical situation. You are dealt a
series of cards and you want to examine the actual order of the deal:

 my $deck = My::Deck->new;
 $deck->shuffle;
 my @hand = $deck->deal(7);

We now have an array containing seven cards. C<$hand[0]> is the first card
dealt and C<$hand[6]> is the last card dealt. What sorts of patterns can we ask?
Let's begin by building a pattern that matches a sequence of cards from the same
suit. We do this by creating our very own hand-crafted atom using the C<re_sub>
function, which expects a subroutine reference that will be run to determine if
the atom should match or not.

 my $same_suit_re = re_sub(
   # In the two-argument form, the first argument
   # is the min and max length that this pattern
   # will match. Here, we indicate that this
   # pattern can match one card, and can match up
   # to the whole hand:
   [1, '100%'], 
   # Following the quantifiers is the anonymous
   # subroutine that is run to figure out if the
   # pattern matches at the given locations.
   sub {
     # The arguments are the data to analyze (which
     # will be an anonymous array with our cards, when
     # it's eventually run), and the current left and
     # right array offsets of interest.
     my ($data, $left_offset, $right_offset) = @_;
     
     # Get the suit of the card at the left offset.
     my $suit = $data->[$left_offset]->suit;
     
     # See how many cards match that suit, starting
     # from the next card:
     my $N_matched = 1;
     $N_matched++
       while $left_offset + $N_matched < $right_offset
         and $data->[$left_offset + $N_matched]->suit eq $suit;
     
     # At this pont, we have the number of cards with
     # the same suit, starting from $left_offset.
     return $N_matched;
   }
 );

Equipped with our atom, we can now apply it to our hand:

 my $N_matched = $same_suit_re->apply(\@hand);
 print "The suit of the first card in our hand is ",
   $hand[0]->suit, " and the first $N_matched cards ",
   " in our hand have that suit\n";

But, what if we wanted to know number of cards of the same suit at the end of
the hand? To do that, we need to supply some sort of anchor.

XXX working here

Atoms describe characteristics of your data, which means that they are specific
to the container and data that you use. In contrast, groupings simply operate
with other patterns, and work across data containers.

=head1 Examples

Here is a pattern that checks for a value that is positive and
which is a local maximum, but which is flanked by at least one negative
number on both sides. All of these assume that the data container is a piddle.

 my $is_local_max = re_sub( [1,1],  # quantifiers, exactly one
     sub {
         my ($piddle, $left, $right) = @_;
         
         # Since this only takes one value, right == left
         my $index = $left;
         
         # The first or last element of the piddle cannot qualify
         # as local maxima for purposes of this pattern:
         return 0 if $index == 0 or $index == $piddle->dim(0) - 1;
         
         return 1 if $piddle->at($index - 1) < $piddle->at($index)
             and $piddle->at($index + 1) < $piddle->at($index);
         
         return 0;
  });
 
 my $is_negative = re_sub( [1,'100%'],
     sub {
         my ($piddle, $left, $right) = @_;
         
         # This cannot match if the first value is positive:
         return 0 if $piddle->at($left) >= 0;
         
         my $sub_piddle = $piddle->slice("$left:$right");
         
         # Is the whole range negative?
         return $right - $left + 1 if all ($sub_piddle < 0);
         
         # At this point, we know that the first element
         # is negative, but part of the range is positive.
         # Find the first non-negative value and return its
         # offset, which is identical to the number of negative
         # elements to the left of it:
         return which($sub_piddle >= 0)->at(0);
 });
 
 # Build up the sequence:
 my $pattern = re_seq(
     $is_negative, $is_local_max, $is_negative
 );
 
 # Match it against some data:
 if ($pattern->apply($data)) {
     # Do something
 }

=head1 METHODS

These are the user-level methods that each pattern provides. Note that this
section does not discuss subclassing or constructors; those are discussed below.
In other words, if you have pattern objects and you want to use them this is the
public API that you can use.

=over

=item apply ($data)

This method applies the pattern object on the given container. The
return value is a bit complicated to explain, but in general it Does What You
Mean. In boolean context, it returns a truth value indicating whether the pattern
matched or not. In scalar context, it returns a scalar indicating the number of
elements that matched if something matched, and undef otherwise. In particular,
if the pattern matched zero elements, it returns the string "0 but true", which
evaluates to zero in numeric context, but true in boolean context. Finally, in
list context, if the pattern fails you get an empty list, and if it succeeds you
get two numbers indicating the number of matched elements and the offset
(without any of that zero-but-true business to worry about).

To put it all together, the following three expressions all Do Something when
your pattern matches:

 if (my ($matched, $offset) = $pattern->apply($data)) {
     # Do Something
 }
 
 if (my $matched = $pattern->apply($data)) {
     # Do Something 
 }
 
 if ($pattern->apply($data)) {
     # Do Something
 }
 
Perl lets you use the returned matched length---even the string---in
arithmetic operations without issuing a warning. (Perl normally issues a
warning when you try to do arithmetic with a string, but it grants an
exception for the string "0 but true".) However, if you plan on
printing the matched length, you should assure a numeric value with either of
these two approaches:

 if (my $matched = $pattern->apply($data)) {
     $matched += 0; # ensure $matched is numeric
     print "Matched $matched elements\n";
 }

or

 if (my ($matched) = $pattern->apply($data)) {
     print "Matched $matched elements\n";
 }

Note that if your pattern matches, you will get the empty list, so, if this fails:

 my ($matched, $offset) = $pattern->apply($data);

both C<$matched> and C<$offset> will be the undefined value, and if you use
the expression in the conditional as in the first example above, the
condition will evaluate to boolean false. The only major gotcha in this
regard is that Perl's list flatting means this will B<NOT> do what you think it
is supposed to do:

 my ($first_matched, $first_off, $second_matched, $second_off)
     = ($pattern1->apply($data), $pattern2->apply($data));

If C<$pattern1> fails to match and C<$pattern2> succeeds, the values for the
second pattern will be stored in C<$first_matched> and C<$first_off>. So, do
not use the return values from a pattern in a large list
assignment like this.

working here - discuss known types and how unknown types throw errors (or should
they silently fail instead? I think not.)

If you only want to know where a sub-pattern matches, you can name that sub-pattern
and retrieve sub-match results using C<get_offsets_for>, as discussed below.

=cut

# User-level method, not to be overridden.
sub apply {
	croak('Scrooge::apply is a one-argument method')
		unless @_ == 2;
	my ($self, $data) = @_;
	
	# Prepare the pattern for execution. This may involve computing low and
	# high quantifier limits, keeping track of $data, stashing
	# intermediate data if this is a nested pattern, and many other things.
	# The actual prep method can fail, so look out for that.
	$self->is_prepping;
	my $prep_results = eval{$self->prep($data)};
	my @croak_messages;
	push @croak_messages, $@ if $@ ne '';
	unless ($prep_results) {
		# update to cleanup state:
		$self->is_cleaning;
		eval { $self->cleanup };
		push @croak_messages, $@ if $@ ne '';
		
		# Croak if there was an exception during prep or cleanup:
		if (@croak_messages) {
			die "Pattern encountered trouble:\n" . 
				join("\n !!!! and !!!!\n", @croak_messages);
		}
		
		# Otherwise, just return an empty match:
		return;
	}
	
	# Note change in local state:
	$self->is_applying;
	
	# Get the data's length
	my $N = data_length($data);
	croak("Could not get length of the supplied data")
		if not defined $N or $N eq '';
	my $min_diff = $self->min_size - 1;
	my $max_diff = $self->max_size - 1;

	# Left and right offsets, maximal right offset, and number of consumed
	# elements:
	my ($l_off, $r_off, $consumed, %details);
	
	# Wrap all of this in an eval block to make sure croaks and other deaths
	# do not prevent cleanup:
	eval {
		# Run through all sensible left and right offsets:
		START: for ($l_off = 0; $l_off < $N - $min_diff; $l_off++) {
			# Start with the maximal possible r_off:
			$r_off = $l_off + $max_diff;
			$r_off = $N-1 if $r_off >= $N;
			
			STOP: while ($r_off >= $l_off + $min_diff) {
				($consumed, %details) = $self->_apply($l_off, $r_off);
				if ($consumed > $r_off - $l_off + 1) {
					my $class = ref($self);
					my $name = $self->get_bracketed_name_string;
					croak("Internal error: pattern$name of class <$class> consumed $consumed,\n"
						. "but it was only allowed to consume " . ($r_off - $l_off + 1));
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
					$self->store_match({left => $l_off, right => $r_off, %details});
					last START;
				}
				# Move to the next starting position if the match at this
				# position failed:
				last STOP if $consumed == 0;
			}
		}
	};
	# Back-up $@:
	push @croak_messages, $@ if $@ ne '';
	
	# Run cleanup, backing up any error messages:
	$self->is_cleaning;
	eval {$self->cleanup};
	push @croak_messages, $@ if $@ ne '';
	
	# Croak if there was an exception during prep or cleanup:
	if (@croak_messages) {
		die "Pattern encountered trouble:\n" . 
			join("\n !!!! and !!!!\n", @croak_messages);
	}
	
	# If we were successful, return the details:
	if ($consumed) {
		return $consumed unless wantarray;
		return (0 + $consumed, $l_off);
	}
	# Otherwise return an empty list:
	return;
}

=item get_details_for ($name)

After running a successful pattern, you can use this method to query the match
details for named patterns. This method returns an anonymous hash containing
the left and right offsets along with any other details that the pattern
decided to return to you. (For example, a pattern could return the average
value of the matched data since that information might be useful, and it
was part of the calculation.)

Actually, you can have the same pattern appear multiple times within a larger
pattern. In that case, the return value will be a list of hashes,
each of which contains the pertinent details. So if this named pattern appears
five times but only matches twice, you will get a list of two hashes with
the details.

The returned results also depend upon the calling context. If you ask for
the match details in scalar context, only the first such hash will be
returned, or undef if there were no matches. In list context, you get a list
of all the hashes, or an empty list of there were not matches. As such, the
following expressions Do What You Mean:

 if (my @details = $pattern->get_details_for('constant')) {
     for my $match_details (@details) {
         # unpack the left and right boundaries of the match:
         my %match_hash = %$match_details;
         my ($left, $right) = @match_details{'left', 'right'};
         # ...
     }
 }
 
 for my $details ($pattern->get_details_for('constant')) {
     print "Found a constant region between $details->{left} "
		. "and $details->{right} with average value "
		. "$details->{average}\n";
 }
 
 if (my $first_details = $pattern->get_details_for('constant')) {
     print "The first constant region had an average of "
		. "$details->{average}\n";
 }

Note that for zero-width matches that succeed, the value of right will be one
less than the value of left.

Finally, note that you can call this method on container patterns such as
C<re_and>, C<re_or>, and C<re_seq> to get the information for named sub-patterns
within the containers.

=cut

sub get_details_for {
	croak('Scrooge::get_details_for is a one-argument method')
		unless @_ == 2;
	my ($self, $name) = @_;
	
	# Croak if this pattern is not named:
	croak("This pattern was not told to capture anything!")
		unless defined $self->{name};
	
	# Croak if this pattern has a different name (shouldn't happen, but let's
	# be gentle to our users):
	croak("This pattern is named $self->{name}, not $name.")
		unless $self->{name} eq $name;
	
	# Be sure to propogate calling context. Note that these return an empty
	# list or an undefined value in their respective contexts if not items
	# matched 
	return ($self->get_details) if wantarray;	# list context
	return $self->get_details;					# scalar context
}

=item get_details

Returns the match details for the current pattern, as described under
C<get_details_for>. The difference between this method and the previous one is
that (1) if this pattern was not named, it simply returns the undefined value
rather than croaking and (2) this method will not search sub-patterns for
container patterns such as C<re_and>, C<re_or>, and C<re_seq> since it has no
name with which to search.

=cut

# This returns the details stored by this pattern. Note that this does not
# croak as it assumes you know what you're doing calling this method
# directly.
sub get_details {
	croak('Scrooge::get_details is a method that takes no arguments')
		unless @_ == 1;
	my ($self) = @_;
	
	# Return undef or the empty list if nothing matched
	return unless defined $self->{final_details};
	
	# Return the collection of match details in list context
	return @{$self->{final_details}} if wantarray;
	
	# Return the first match details in scalar context
	return $self->{final_details}->[0];
}

=back

=head1 Return Values

This needs to be moved down below the sections that describe specific classes
(like C<re_any>). Ah well, must be fixed later.

working here

=head2 When writing a condition

In short, if the condition matches for the given length, you should return
the number of elements matched, which is C<$right - $left + 1>. If it
does not match for this range but B<might> match for a shorter range (if
C<$right> were moved a little bit to the left), return -1. If it cannot
match starting at C<$left>, return numeric zero. Those are the basics. However,
other return values are allowed and using them can significantly improve the
performance of your pattern.

Here is a rundown of what to return when:

=over

=item More than the Full Length

You should never return more than the full length, and if you do, the pattern
engine will croak saying

 Internal error: pattern of class <class> consumed more than it was given

doc working here - add this to the list of errors reported.

=item Full Length

Return the full length, C<$right - $left + 1>, if the condition matches
against the full length.

=item Less than the Full Length

If your condition does not match against the entire object range but it is easy
to check against shorter lengths, you can return the number of elements that it
matches. In terms of Perl arrays, if the match fails against the slice
C<@data[$left .. $right]> but it's easy to find some C<$less_than_right> for
which the match succeeds (against C<@data[$left .. $less_than_right]>), then
you can return the legnth of that match, which would be
C<$less_than_right - $left + 1>.

Note that you should only do this if it is easy to check shorter lengths.
Some algorithms require that you evaluate every value of C<$less_than_right>, in
which case it costs nothing to simply return the longest C<$less_than_right>
that matches. If examining every possible value of C<$less_than_right> is
expensive, then consider returning a negative value, discussed below.

=item Zero But True

You can positively return a match of zero length under two circumstances:
matching zero elements with a "zero or more" quantifier, or matching a
zero-width assertion. In that case, you must return the string "0 but true",
which is a special string in Perl.

For example, if your condition looks for sequences that are
less than 5 and C<$data[$left]> is 7, it is not possible for this
condition to match. However, if your quantifiers allow for zero or more
matching elements, you can legitimately say that the match was successful
and it matched zero elements. Note that if your quantifiers do not allow
a match of zero length, you should probably return the numeric value of 0,
instead.

Zero-width assertions are a different sort of match of zero elements. In
numerical patterns, this could be a condition on the slope between
two values, or a threshold crossing between two values, for instance. In those
cases, your pattern does not match either of the values, but it matches in-between
them. Look-ahead or look-behind assertions are also zero-width assertions
with which you may be familiar from standard Perl regular expressions.

=item Zero, i.e. failed match

Return the numeric value of 0 when you know that your condition cannot match for
this or any shorter range, B<including a zero-length match>. If you have
concluded that the condition cannot match the current length, but it may be able
to match a shorter length, you should return a negative value instead of zero.
Also, if your match is allowed to have a length of zero, you should return the
string "0 but true" instead.

Let's consider the condition from the paragraph on Zero But True. If your
condition looks for sequences that are less than 5 and C<$data[$left]> is 7, and
if you know that your quantifiers will not allow a match of zero length, you
should return a numeric 0 to indicate that it is not possible for this condition
to match.

Remember: if all you can say is that the condition does not match for the range
C<$left. to C<$right>, but it might match for the same value for C<$left> and a
smaller value for C<$right>, you should return a negative value instead of zero.

=item Negative Values

As I have already discussed, your condition may involve expensive
calculations, so rather than check each sub-slice starting from C<$left>
and reducing C<$right> until you find a match, you can simply return -1.
That tells the pattern engine that the current values of C<$left> and
C<$right> do not match the condition, but smaller values of C<$right> might
work. Generally speaking, returning zero is much stronger than returning -1,
and it is safer to return -1 when the match fails. It is also far more
efficient to return zero if you are certain that the match will fail for any
value of C<$right>.

However, you can return more than just -1. For example, if your condition
fails for C<$right> as well as C<$right - 1>, but beyond that it is
difficult to calculate, you can return -2. That tells the pattern
engine to try a shorter range starting from left, and in particular that the
shorter range should be at least two elements shorter than the current
range.

You might ask, why not just B<evaluate> the condition at the lesser value? The
reason to avoid this is because this pattern may be part of a combined C<re_or>
pattern, for example. You might have a pattern such as C<re_or ($first, $second)>.
Suppose C<$first> fails at C<$right> but will succeed at C<$right - 1>, and
C<$second> fails at C<$right> but will succeed at C<$right - 2>. It would be
inefficient for C<$second> to evaluate its truth condition at C<$right - 2>
since the result will never be used.

=back




=head1 Creating your own Pattern Class

The heierarchy of numerical patterns have two basic flavors:
Quantified patterns and Grouped patterns. If you are
trying to write a rule to apply to data, you are almost certainly interested
in creating a new Quantified pattern. That's also the easier one
of the two to create, so I'll discuss subclassing that first.

To subclass C<Scrooge::Quantified> (argh... not finished, but see the
next section as it discusses most of this anyway).


=head1 Internals

All pattern classes must inheret from C<Scrooge> or a class derived from
it. This section of documentation discusses how you might go about doing
that. You are encouraged to override any of the methods of C<Scrooge> or
its derivatives, except for the C<apply> method.

=head2 Required Methods

If your class derives directly from Scrooge, Scrooge::Quantified, or
Scrooge::Grouped, you must supply the C<_apply> internal method. However,
you can override other methods as you see fit. The only methods you should
not override are the Internal methods documented at the end of this section.

=over

=item _apply

This function is called when it comes time to apply the pattern to see if it
matches the current range. That arguments to the apply function are the left
and right offsets, respectively. (The data is not included, and you should
make sure that you've cached a reference to the container during the C<_prep>
phase.)

If your pattern encloses another, it should call the enclosed pattern's C<_apply>
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

=item new ($class, %args)

The role of the constructor is to create a blessed hash with any internal
data representations.

From the standpoint of sub-classing, you should not override this method. It
performs quite a bit of initialization for stack management that you will
not want to deal with. Overrider C<_init> instead, which is called as a
method at the end of C<new>.

Note also that user-level constructors tend to wrap around the C<new>
function and often perform their own data validation and internal
data construction, so that is another place to put construction code.

This method croaks if, after the class name, there is not an
even number of remaining arguments since it blesses the hash of key => value
pairs into the supplied class.

Between C<new>, C<_init>, and the user-level constructor, the object that
comes out must be capable of running its C<prep> method.

=cut

sub new {
	my $class = shift;
	croak("Internal Error: args to Scrooge::new must have a class name and then key => value pairs")
		unless @_ % 2 == 0;
	my $self = bless {@_}, $class;
	
	# Set the default state so that stashing works correctly:
	$self->{state} = 'not running';
	
	# Initialize the class:
	$self->_init;
	
	return $self;
}

=item _init

working here - document this method

=cut

# Default init does nothing:
sub _init {
	croak('Scrooge::_init is a method that takes no arguments')
		unless @_ == 1;
}
=item prep ($data)

This function is called before the pattern hammers on the supplied
data. If you have any data-specific setup to do, do it in this function.

From the standpoint of internals, you need to know two things: what this
function should prepare and what this function should return. (For a
discussion on intepreting return values from C<_prep>, see Scrooge::Grouped.)

If you are not deriving your class from Scrooge::Quantified or Scrooge::Grouped and
you intend for your pattern to run, you must either set C<< $self->{min_size} >>
and C<< $self->{max_size} >> at this point or you must override the
related internal functions so that they operate correctly without having
values associated with those keys.

If, having examined the data, you know that this pattern will not match, 
you should return zero. This guarantees that the following functions
will not be called on your pattern during this run: C<_apply>, C<_min_size>,
C<_max_size>, and C<_store_match>. Put a little bit
differently, it is safe for any of those functions to assume that C<_prep>
has been called and was able to set up internal data that might be required
for their operation. Furthermore, if you realize in the middle of C<_prep>
that your pattern cannot run, it is safe to return 0 immediately and expect
the parent pattern to call C<_cleanup> for you. (working here - make sure the
documentation for Scrooge::Grouped details what Grouped patterns are supposed to
do with C<_prep> return values.)

Your pattern may still be querried afterwards for a match by
C<get_details_for> or C<get_details>, regardless of the return value of
C<_prep>. In both of those cases, returning the undefined value,
indicating a failed match, would be the proper thing to do.

The C<_prep> method is called as the very first step in C<apply>.



=cut



# The first phase. Back up the old state and clear the current state. The
# state is required to be 'not running' before the pattern starts, and it
# is required to have a defined value during all three user-directable
# phases.
# Do *not* set the state to prepping; that is part of prep's short-
# circuiting.
sub is_prepping {
	croak('Scrooge::is_prepping is a method that takes no arguments')
		unless @_ == 1;
	my $self = shift;
	if ($self->{state}) {
		push @{$self->{old_state}}, $self->{state};
		delete $self->{state};
	}
}

sub is_applying {
	$_[0]->{state} = 'apply';
}

# As with is_prepping, do *not* set the state since cleaning's short-
# circuiting depends on this being clear:
sub is_cleaning {
	delete $_[0]->{state};
}

# Make sure this only gets run once per call to apply:
sub prep {
	croak('Scrooge::prep is a one-argument method')
		unless @_ == 2;
	my ($self, $data) = @_;
	
	return 1 if $self->{state};
	$self->{state} = 'prepping';
	
	# Stash everything. Note that under repeated invocations of a pattern, there
	# may be values that we traditionally stash that have lingered from the
	# previous invocation.
	# I would like to remove those values, but that causes troubles. :-(
#	my @to_stash = $self->_to_stash;
	if (defined $self->{data}) {
		push @{$self->{"old_$_"}}, $self->{$_} foreach $self->_to_stash;
#			@to_stash;
	}
	else {
		#delete $self->{$_} foreach @to_stash;
	}
	
	# working here - make sure to document that min_size and max_size must
	# be set by the derived class's _prep method
	$self->{data} = $data;
	
	return $self->_prep($data);
}

# Default _prep simply returns true, meaning a successful prep:
sub _prep {	return 1 }

=item _to_stash

Stashing is a means of storing the pattern's internal state in the middle of a
match. This will happen in the following series of events. First, you create a
stand-alone pattern, say, C<my $complex_pattern>. Then you build a grouped
pattern (such as a sequence) that includes C<$complex pattern> as well as a
subroutine pattern. Finally, within that subroutine pattern, you C<apply> the same
C<$complex_pattern> to a sub-slice of the data. In that case, C<$complex_pattern>
will have internal data from the outer grouped pattern that needs to be stored
so that the internal pattern match can run and return its values.

Even if you didn't follow what I just explained, the point is that Scrooge will
handle the saving and restoring your pattern's internal data at the right times
so that everything works without any intervention on your part. To get this to
work, all you need to do is tell Scrooge which keys to back-up. To do this, you
overload the C<_to_stash> method with something like this:

 sub _to_stash {
     return 'velocity', 'acceleration', $self->SUPER::_to_stash;
 }

This will ensure that if you or your users try to do that crazy call-from-inside
thing that I described above, the internal values of the pattern's engine, along
with the keys C<velocity> and C<acceleration>, will be exactly what you asked
them to be.

What should you have stashed? You should stash anything that you expect to
remain unchanged. For example, anything that you compute once during the _prep
stage and expect to remain unchanged is exactly the sort of thing that should
be stashed. The default keys that are stashed include C<data>, C<min_size>,
C<max_size>, and C<match_details>.

=cut

# The internal keys with values that we want to protect in case of
# recursive usage:
sub _to_stash {
	croak('Scrooge::_to_stash is a method that takes no arguments')
		unless @_ == 1;
	return qw (data min_size max_size match_details);
}

=item _min_size, _max_size

These are getters and setters for the current lengths that indicate the
minimum and maximum number of elements that your pattern is capable of
matching. The base class expects these to be set during the C<_prep> phase
after afterwards consults whatever was stored there. Because of the
complicated stack management, you would be wise to stick with the base class
implementations of these functions.

working here - make sure grouped patterns properly set these during the
_prep phase.

Note that at the moment, C<_min_size> and C<_max_size> are not querried
during the actual operation of the pattern, only at the beginning. In other
words, overriding these methods so that their return value changes throughout
the course of the pattern match (with a hope of reporting a more precise value,
perhaps) will not work.

You are guaranteed that C<_prep> will have been run before these methods are
run, and they will not be run if C<_prep> returned a false value. If you
call the base class's prep, you are also guaranteed that if min_size or
max_size are keys in the object, they will be the default values.

=cut

sub min_size {
	return $_[0]->{min_size} if @_ == 1;
	return $_[0]->{min_size} = $_[1] if @_ == 2;
	croak('Scrooge::min_size is an accessor method');
}

sub max_size {
	return $_[0]->{max_size} if @_ == 1;
	return $_[0]->{max_size} = $_[1] if @_ == 2;
	croak('Scrooge::max_size is an accessor method');
}

=item _cleanup

This method is called in one of two situations: (1) if you just returned 
zero from C<_prep> and (2) after the engine is done, regardless of whether
the engine matched or not. C<_cleanup> should only be called once, but your
code needs to be flexible enough to accomodate multiple calls to C<_cleanup>
without dying.

=cut

sub cleanup {
	croak('Scrooge::cleanup is a method that takes no arguments')
		unless @_ == 1;
	my $self = shift;
	
	# self's state is *always* deleted just before cleanup is called, so if
	# it has any true value, then the cleanup phase for this object has
	# already been called:
	return if $self->{state};
	$self->{state} = 'cleaning';

	# finalize the match stack
	$self->{final_details} = delete $self->{match_details};
	
#	# We're about to call the sub-class's cleanup method. If, for some
#	# stupid reason, the sub-class's cleanup uses a pattern, then we have
#	# to guard against call-stack issues. We do that by noting the size of
#	# the current partial_state stack before we call.
#	my $partial_state_stack_size = scalar(@{$self->{old_partial_state}});
	# Call sub-class's cleanup method:
	eval { $self->_cleanup() };
	my $err_string = $@;
#	# If the partial state stack has changed size, then it's because the
#	# _cleanup method called a numerical pattern that contained this pattern.
#	# Sounds ridiculous, but under very contrived circumstances, it can
#	# happen without deep recursion. If it happened, restore *this* pattern's
#	# partial state (is_cleaning) and remove the old state from the stack:
#	if ($partial_state_stack_size != scalar(@{$self->{old_partial_state}})) {
#		$self->{is_cleaning} = 1;
#		my $old_state = pop @{$self->{old_partial_state}};
#		croak("OH NO!!!! The old partial state MUST be is_cleaning, but it's not! INTERNAL ERROR!")
#			unless $old_state eq 'is_cleaning';
#	}
	
	# Remove this copy of the $data since its presence is used in prep
	# to know if needs to stash or not.
	delete $self->{data};
	
	# Unstash everything:
	if (defined $self->{old_data}->[0]) {
		$self->{$_} = pop @{$self->{"old_$_"}} foreach $self->_to_stash;
		
#		# Restore the previous match stack, if appropriate:
#		$self->{match_details} = pop @{$self->{old_match_details}}
#			if defined $self->{name};
#		
#		# Set-up the old is_prepping state, if that was the last state.
#		# Note that the is_cleaning is handled by the calling context, which
#		# happens about 20 linues up, so I do *not* handle that here:
#		if ($self->{old_partial_state}->[-1] and
#				$self->{old_partial_state}->[-1] eq 'is_prepping') {
#			$self->{is_prepping} = 1;
#			pop @{$self->{old_partial_state}};
#		}
	}
	
	# ALWAYS unstash the previous state, which is always guaranteed to have
	# a meaningful value:
	$self->{state} = pop @{$self->{old_state}};
	
	# Finally, check the error state from the sub-class's cleanup:
	die $err_string if $err_string ne '';
}

# Default _cleanup does nothing
sub _cleanup { }

=back

=head2 Matching

A number of functions facilitate homogeneous behavior for named regular
expressions, which are supposed to keep track of the indices that matched.
These functions do that:

=over

=item store_match ({detail => hash})

This is a function provided by the base class that stores the details under
the C<match_details> key if the pattern is named.

=cut

sub store_match {
	croak('Scrooge::store_match is a one-argument method')
		unless @_ == 2;
	my ($self, $details) = @_;
	
	# Only store the match if this is named
	return unless exists $self->{name};
	push @{$self->{match_details}}, $details;
}

=item clear_stored_match

Grouping patterns like re_and and re_seq need to have some way of
clearing a stored match when something goes wrong, and they do this by
calling C<clear_stored_match>. In the base class's behavior, this function
only runs when there is a name associated with the pattern. Grouping pattern
objects should clear their children patterns, in addition to clearing their
own values.

=cut

sub clear_stored_match {
	croak('Scrooge::_stored_match is a method that takes no arguments')
		unless @_ == 1;
	my $self = shift;
	
	return 0 unless exists $self->{name};
	pop @{$self->{match_details}};
	return 0;
}

=item add_name_to ($hashref)

This method adds this pattern's name (along with a reference to itself) to the
supplied hashref. This serves two purposes: first, it gives the owner a fast
way to look up named references if either of the above accessors are called.
Second, it provides a means at construction time (as opposed to evaluation
time) to check that no two patterns share the same name. If you overload this
method, you should be sure to add your name and reference to the list (if
your pattern is named) and if yours is a grouping pattern, you should also check
for and add all of your childrens' names. Note that if your pattern's name is
already taken, you should croak with a meaningful message, like

 Found multiple patterns named $name.

working here - discuss more in the group discussion; also, should I weaken these
references?

=cut

sub add_name_to {
	croak('Scrooge::add_name_to is a one-argument method')
		unless @_ == 2;
	my ($self, $hashref) = @_;
	return unless exists $self->{name};
	
	my $name = $self->{name};
	# check if the name exists:
	croak("Found multiple patterns named $name")
		if exists $hashref->{$name} and $hashref->{$name} != $self;
	# Add self to the hashref under $name:
	$hashref->{$name} = $self;
}

=item _get_bracketed_name_string

This returns a string to be used in error messages. It should return an
empty string if the pattern does not have a name, or ' [name]' if it does
have a name. You shouldn't override this except for debugging purposes.

=cut

sub get_bracketed_name_string {
	croak('Scrooge::get_bracketed_name_string is a method that takes no arguments')
		unless @_ == 1;
	my $self = shift;
	if (defined $self->{name}) {
		return ' [' . $self->{name} . ']';
	}
	return '';
}

=back

=head2 Scrooge::data_length

Scrooge is designed to operate on any data container you wish to throw at
it. However, it needs to know how to get the length of the information in your
container. It does this with the generic function C<Scrooge::data_length>. To
get the length of any known container, you would use the following command:

 my $length = Scrooge::data_length($data);

But how, you ask, does C<Scrooge::data_length> know how to calculate the length
of my container? That's easy! Each container that wants to interact with Scrooge
simply adds a subroutine reference to a table of length subroutines called
C<%Scrooge::length_method_table>, where the key is the class name.

For example, after doing this:

 $Scrooge::length_method_table{'My::Class::Name'} = sub {
     # Returns the length of its first argument.
     return $_[0]->length;
 };

if C<$object> is an object of class C<My::Class::Name>, you can simply use
C<Scrooge::data_length($object)> to get the length of C<$object>.

This is the only requirement that Scrooge has if you wish to use your class as
a container for Scrooge patterns.

Note to self: This should almost certainly be documented elsewhere, perhaps even
in a separate document geared towards data container authors.

=cut

our %length_method_table = (
	''			=> sub { return length $_[0] },
	(ref [])	=> sub { return scalar(@{$_[0]}) },
	PDL			=> sub { return $_[0]->dim(0) },
	(ref {})	=> sub {
			my $hashref = shift;
			return $hashref->{length} if exists $hashref->{length};
			# Didn't supply a length key? I hope the length of the first
			# "value" in the hashref makes sense!
			my @values = values %$hashref;
			return Scrooge::data_length($values[0]);
		},
);

sub data_length {
	my $data = shift;
	return $length_method_table{ref $data}->($data)
		if exists $length_method_table{ref $data};
	croak('Scrooge was unable to determine the length of your data, which is of class '
		. ref($data));
}

package Scrooge::Quantified;
use parent -norequire, 'Scrooge';
use strict;
use warnings;
use Carp;

=head1 Scrooge::Quantified

The Quantified abstract base class inherets from the Scrooge abstract base class
and provides functionality for handling quantifiers, including parsing the
quantifier argument. If you need a pattern object that handles quantifiers but
you do not care how it works, you should inheret from this base class and
override the C<_apply> method.

=cut

sub _init {
	my $self = shift;
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
			chop $to_check;
			# Make sure it's a number between 0 and 100:
			croak("Percentage quantifier must be a number; I got [$_]")
				unless $to_check =~ /\d/;
			croak("Percentage quantifier must be >= 0; I got [$_]")
				unless 0 <= $to_check;
			croak("Percentage quantifier must be <= 100; I got [$_]")
				unless $to_check <= 100;
		}
		# Check that non-percentage quantifiers are strictly integers:
		elsif ($_ !~ /^-?\d+$/) {
			croak("Non-percentage quantifiers must be integers; I got [$_]");
		}
	}
	
	# Put the quantifiers in self:
	$self->{min_quant} = $ref->[0];
	$self->{max_quant} = $ref->[1];
	
	return $self;
}

# Default minimum length is zero:
sub _min_length { 0 }

# Prepare the current quantifiers:
sub _prep {
	my ($self, $data) = @_;
	# Compute and store the numeric values for the min and max quantifiers:
	my $N = Scrooge::data_length($data);
	my ($min_size, $max_size);
	my $min_quant = $self->{min_quant};
	my $max_quant = $self->{max_quant};
	
	if ($min_quant =~ s/%$//) {
		$min_size = int(($N - 1) * ($min_quant / 100.0));
	}
	elsif ($min_quant < 0) {
		$min_size = int($N + $min_quant);
		# Set to a reasonable value if min_quant was too negative:
		$min_size = 0 if $min_size < $self->_min_length;
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
		return 0 if $max_size < $self->_min_length;
	}
	else {
		$max_size = int($max_quant);
		# Set to a reasonable value if max_quant was too large:
		$max_size = $N if $max_size > $N;
	}
	
	# One final sanity check:
	return 0 if ($max_size < $min_size);
	
	# If we're good, store the sizes:
	$self->min_size($min_size);
	$self->max_size($max_size);
	return 1;
}

# I don't need to override _stash or _cleanup because they already handle
# the size information. Also, I do not supply an _apply because that must be
# provided by the derived classes.

package Scrooge::Any;
use parent -norequire, 'Scrooge::Quantified';
use strict;
use warnings;
use Carp;

=head2 re_any

Creates a pattern that matches any value.

=cut

sub Scrooge::re_any {
	croak("Scrooge::re_any takes one or two optional arguments: re_any([[name], quantifiers])")
		if @_ > 2;
	
	# Get the arguments:
	my $name = shift if @_ == 2;
	my $quantifiers = shift if @_ == 1;
	$quantifiers = [1,1] unless defined $quantifiers;
	
	# Create the subroutine pattern:
	return Scrooge::Any->new(quantifiers => $quantifiers
		, defined $name ? (name => $name) : ());
}

# apply (the non-overrideable method) will store the saved values:
sub _apply {
	my (undef, $left, $right) = @_;
	return $right - $left + 1;
}

package Scrooge::Sub;
use parent -norequire, 'Scrooge::Quantified';
use strict;
use warnings;
use Carp;

=head2 re_sub

This evaluates the supplied subroutine on the current subset of data. The
three arguments supplied to the function are (1) original data container under
consideration, (2) the left index offset under consideration, and (3) the
right index offset. If the match succeeds, return the number of matched
values. If the match succeeds but it consumed zero values (i.e. a zero-width
assertion), return the string "0 but true", which is a magical value in Perl
that evaluates to true in boolean context, which is numerically zero in
numeric context, and which does not gripe when converted from a string value
to a numeric value, even when you've activated warnings.

=cut


# This builds a subroutine pattern object:
sub Scrooge::re_sub {
	croak("re_sub takes one, two, or three arguments: re_sub([[name], quantifiers], subref)")
		if @_ == 0 or @_ > 3;
	
	# Get the arguments:
	my $name = shift if @_ == 3;
	my $quantifiers = shift if @_ == 2;
	my $subref = shift;
	
	# Check that they actually supplied a subref:
	croak("re_sub requires a subroutine reference")
		unless ref($subref) eq ref(sub {});
	
	$quantifiers = [1,1] unless defined $quantifiers;
	
	# Create the subroutine pattern:
	return Scrooge::Sub->new(quantifiers => $quantifiers, subref => $subref
		, defined $name ? (name => $name) : ());
}

sub _apply {
	my ($self, $left, $right) = @_;
	# Apply the rule and see what we get:
	my ($consumed, %details) = eval{$self->{subref}->($self->{data}, $left, $right)};
	
	# handle any exceptions:
	unless ($@ eq '') {
		my $name = $self->get_bracketed_name_string;
		die "Subroutine pattern$name died:\n$@";
	}
	
	# Make sure they didn't break any rules:
	if ($consumed > $right - $left + 1) {
		my $name = $self->get_bracketed_name_string;
		die "Subroutine pattern$name consumed more than it was allowed to consume\n";
	}
	
	# Return the result:
	return ($consumed, %details);
}

# Abstract base class for zero-width assertions
package Scrooge::ZWA;
our @ISA = ('Scrooge');
use strict;
use warnings;
use Carp;

=pod

behavior for C<parse_location>

Here's a table describing the different locations for a 20-element array.

 string       offset  notes
 0            0
 1            1
 1 + 1        2
 -1           19
 5 - 10       -5      This will never match
 10%          10
 10% + 20%    6
 50% + 3      13
 100% + 5     25      This will never match
 10% - 5      -3      This will never match
 12% + 3.4    6       Rounded from 5.8
 14% + 3.4    6       Rounded from 6.2

Positive numbers - use an offset at that location
percentage - use an offset of length / 100 * $pct
percentage with arithmetic - normal numeric evaluation
negative numbers - if the string can be exactly interpreted as a negative
number, it is taken as a negative offset from the full length. Otherwise, the
negative value is taken as-is, and it will never match.

=cut

# Parses a location string and return an offset for a given piece of data.
sub parse_location{
        my ($data, $location_string) = @_;
        
        # Get the max index in a cross-container form
        my $max_index = Scrooge::data_length($data);
        my $pct = $max_index/100;
        
        my $original_location_string = $location_string;
        
        $location_string =~ s/(\d)\s*\%/$1 * \$pct/;
        
        my $location = eval($location_string);
        croak("parse_location had trouble with location_string $original_location_string")
                if $@ ne '';
        
        # handle negative offsets
        if ($location < 0) {
        	no warnings 'numeric';
        	$location += $max_index if $location == $location_string;
        }
        
        # Round the result if it's not an integer
        return int($location + 0.5) if $location != int($location);
        # otherwise just return the location
        return $location;
}

sub min_size { 0 }
sub max_size { 0 }

# Matches beginning of the data
package Scrooge::ZWA::Begin;
our @ISA = ('Scrooge::ZWA');
use strict;
use warnings;
use Carp;

sub Scrooge::re_anchor_begin {
	croak("re_anchor_begin takes zero or one argument") if @_ > 1;
	
	return Scrooge::ZWA::Begin->new(name => $_[0]) if @_ > 0;
	return Scrooge::ZWA::Begin->new;
}

sub _apply {
	my ($self, $left, $right) = @_;
	unless ($right < $left) {
		my $name = $self->get_bracketed_name_string;
		croak("Internal error in calling re_anchor_begin pattern$name: $right is not "
			. "less that $left");
	}
	
	return '0 but true' if $left == 0;
	return 0;
}

package Scrooge::ZWA::End;
our @ISA = ('Scrooge::ZWA');
use strict;
use warnings;
use Carp;

sub Scrooge::re_anchor_end {
	croak("re_anchor_end takes zero or one argument") if @_ > 1;
	
	return Scrooge::ZWA::End->new(name => $_[0]) if @_ > 0;
	return Scrooge::ZWA::End->new;
}

sub _apply {
	my ($self, $left, $right) = @_;
	unless ($right < $left) {
		my $name = $self->get_bracketed_name_string;
		croak("Internal error in calling re_anchor_end pattern$name: $right is not "
			. "less that $left");
	}
	
	return '0 but true' if $left == Scrooge::data_length($self->{data});
	return 0;
}

package Scrooge::ZWA::Sub;
our @ISA = ('Scrooge::ZWA');
use strict;
use warnings;
use Carp;

sub Scrooge::re_zwa {
	# If two arguments, assume the first is a name and the second is a
	# subroutine reference:
	croak("re_zwa takes one or two arguments: re_zwa([name], subref)")
		if @_ == 0 or @_ > 2;
	# Pull off the name if it's supplied:
	my $name = shift if @_ == 2;
	# Get and check the subref:
	my $subref = shift;
	croak("re_zwa requires a subroutine reference")
		unless ref($subref) eq ref(sub{});
	
	# Return the constructed zero-width assertion:
	my $self = Scrooge::ZeroWidthAssertion->new(subref => $subref
		, defined $name ? (name => $name) : ());
	
}

sub _apply {
	my ($self, $left, $right) = @_;
	unless ($right < $left) {
		my $name = $self->get_bracketed_name_string;
		croak("Internal error in calling re_zwa pattern$name: $right is not "
			. "less that $left");
	}
	
	# Evaluate their subroutine:
	my ($consumed, %details)
		= eval{$self->{subref}->($self->{data}, $left, $right)};
	
	# Handle any exceptions
	if ($@ ne '') {
		my $name = $self->get_bracketed_name_string;
		die "re_zwa pattern$name died:\n$@\n";
	}
	
	# Make sure they only consumed zero elements:
	unless ($consumed == 0) {
		my $name = $self->get_bracketed_name_string;
		die("Zero-width assertion$name consumed more than zero elements\n");
	}
	
	# Return the result:
	return ($consumed, %details);
}

package Scrooge::Grouped;
# Defines grouped patterns, like re_or, re_and, and re_seq
use parent -norequire, 'Scrooge';
use strict;
use warnings;
use Carp;

sub _init {
	my $self = shift;
	croak("Grouped patterns must supply a key [patterns]")
		unless defined $self->{patterns};
	
	croak("You must give me at least one pattern in your group")
		unless @{$self->{patterns}} > 0;
	
	# Create the list of names, starting with self's name. Adding self
	# simplifies the logic later.
	$self->{names} = {};
	$self->{names}->{$self->{name}} = $self if defined $self->{name};
	
	# Check each of the child patterns and add their names:
	foreach (@{$self->{patterns}}) {
		croak("Invalid pattern") unless eval {$_->isa('Scrooge')};
		$_->add_name_to($self->{names});
	}
	
	return $self;
}

# Derivatives must supply their own _apply

# Some state information that will need to be stashed:
sub _to_stash {
	my $self = shift;
	return qw(patterns_to_apply positive_matches), $self->SUPER::_to_stash;
}

sub prep_all {
	my ($self, $data) = @_;
	
	# Call the prep function for each of them, keeping track of all those
	# that succeed. Notice that I capture errors and continue because every
	# single pattern needs to run its prep method in order for it to be 
	# safe for it to call its cleanup method.
	my @succeeded;
	my @errors;
	foreach (@{$self->{patterns}}) {
		my $successful_prep = eval { $_->prep($data) };
		push @errors, $@ if $@ ne '';
		if ($successful_prep) {
			# Make sure the min size is not too large:
			push (@succeeded, $_)
				unless $_->min_size > Scrooge::data_length($data);
		}
	}
	
	# Rethrow if we caught any exceptions:
	if (@errors == 1) {
		die(@errors);
	}
	elsif (@errors > 1) {
		die(join(('='x20) . "\n", 'Multiple Errors', @errors));
	}
	
	return @succeeded;
}

# _prep will call _prep on all its children and keep track of those that
# return true values. Success or failure is based upon the inherited method
# _prep_success.
sub _prep {
	my ($self, $data) = @_;
	
	my @succeeded = $self->prep_all($data);
	
	# Store the patterns to apply. If _prep_success returns zero, we do not
	# need to call cleanup: that will be called by our parent:
	$self->{patterns_to_apply} = \@succeeded;
	return 0 unless $self->_prep_success;
	
	# Cache the minimum and maximum number of elements to match:
	$self->_minmax;
	my $data_size = Scrooge::data_length($data);
	$self->max_size($data_size) if $self->max_size > $data_size;
	# Check those values for sanity:
	if ($self->max_size < $self->min_size or $self->min_size > $data_size) {
		return 0;
	}

	# If we're here, then all went well, so return as much:
	return 1;
}

# The default success happens when we plan to apply *all* the patterns
sub _prep_success {
	my $self = shift;
	return @{$self->{patterns}} == @{$self->{patterns_to_apply}};
}

sub _cleanup {
	my $self = shift;
	# Call the cleanup method for *all* child patterns:
	my @errors;
	foreach (@{$self->{patterns}}) {
		eval {$_->cleanup};
		push @errors, $@ if $@ ne '';
	}
	
	# Rethrow if we caught any exceptions:
	if (@errors == 1) {
		die(@errors);
	}
	elsif (@errors > 1) {
		die(join(('='x20) . "\n", 'Multiple Errors', @errors));
	}
}


# State functions need to be called on all children.
sub is_prepping {
	my $self = shift;
	$self->SUPER::is_prepping;
	foreach my $pattern (@{$self->{patterns}}) {
		$pattern->is_prepping;
	}
}

sub is_applying {
	my $self = shift;
	$self->SUPER::is_applying;
	foreach my $pattern (@{$self->{patterns}}) {
		$pattern->is_applying;
	}
}

# As with is_prepping, do *not* set the state since cleaning's short-
# circuiting depends on this being clear:
sub is_cleaning {
	my $self = shift;
	$self->SUPER::is_cleaning;
	foreach my $pattern (@{$self->{patterns}}) {
		$pattern->is_cleaning;
	}
}

# Clear stored match assumes that all the patterns matched, so this will
# need to be overridden for re_or:
sub clear_stored_match {
	my $self = shift;
	# Call the parent's method:
	$self->SUPER::clear_stored_match;
	
	# Call all the positively matched patterns' clear function:
	foreach my $pattern (@{$self->{positive_matches}}) {
		$pattern->clear_stored_match;
	}
	
	# Always return zero:
	return 0;
}

sub push_match {
	croak('Scrooge::Grouped::push_match is a method that expects two arguments')
		unless @_ == 3;
	my ($self, $pattern, $details) = @_;
	push @{$self->{positive_matches}}, $pattern;
	$pattern->store_match($details);
}

# This should only be called when we know that something is on the
# positive_matches stack. recursive check this
sub pop_match {
	my $self = shift;
	$self->{positive_matches}->[-1]->clear_stored_match;
	pop @{$self->{positive_matches}};
}

sub get_details_for {
	my ($self, $name) = @_;
	# This is a user-level function. Croak if the name does not exist.
	croak("Unknown pattern name $name") unless exists $self->{names}->{$name};
	
	# Propogate the callin context:
	return ($self->{names}->{$name}->get_details) if wantarray;
	return $self->{names}->{$name}->get_details;
}

# This is only called by patterns that *hold* this one, in the process of
# building their own name tables. Add this and all children to the hashref.
# Structures like ABA should pass this, but recursive structures will go
# into deep recursion.
# recursive check this
sub add_name_to {
	my ($self, $hashref) = @_;
	# Go through each named value in this group's collection of names:
	while( my ($name, $ref) = each %{$self->{names}}) {
		croak("Found multiple patterns named $name")
			if defined $hashref->{$name} and $hashref->{$name} != $ref;
		
		$hashref->{$name} = $ref;
	}
}



=head2 re_or

This takes a collection of pattern objects and evaluates all of
them until it finds one that succeeds. This does not take any quantifiers.

=cut

package Scrooge::Or;
use parent -norequire, 'Scrooge::Grouped';
use strict;
use warnings;
use Carp;

# Called by the _prep method; sets the internal minimum and maximum match
# sizes.
# recursive check this
sub _minmax {
	my $self = shift;
	my ($full_min, $full_max);
	
	# Compute the min as the least minimum, and max as the greatest maximum:
	foreach my $pattern (@{$self->{patterns_to_apply}}) {
		my $min = $pattern->min_size;
		my $max = $pattern->max_size;
		$full_min = $min if not defined $full_min or $full_min > $min;
		$full_max = $max if not defined $full_max or $full_max < $max;
	}
	$self->min_size($full_min);
	$self->max_size($full_max);
}

# Must override the default _prep_success method. If we have *any* patterns
# that will run, that is considered a success.
sub _prep_success {
	return @{$_[0]->{patterns_to_apply}} > 0;
}

# This only needs to clear out the current matching pattern:
# recursive check this
sub clear_stored_match {
	my $self = shift;
	# Call the Scrooge's method:
	Scrooge::clear_stored_match($self);
	
	# Only pop off the latest match:
	$self->pop_match;
	
	# Always return zero:
	return 0;
}

# Run all the patterns (that said they wanted to run). Return the first
# success that we find:
sub _apply {
	my ($self, $left, $right) = @_;
	my @patterns = @{$self->{patterns_to_apply}};
	my $max_size = $right - $left + 1;
	my $min_r = $left + $self->min_size - 1;
	my $i = 0;
	PATTERN: for (my $i = 0; $i < @patterns; $i++) {
		my $pattern = $patterns[$i];
		
		# skip if it wants too many:
		next if $pattern->min_size > $max_size;
		
		# Determine the minimum allowed right offset
		my $min_r = $left + $pattern->min_size - 1;
		
		# Start from the maximum allowed right offset and work our way down:
		my $r = $left + $pattern->max_size - 1;
		$r = $right if $r > $right;
		
		RIGHT_OFFSET: while($r >= $min_r) {
			# Apply the pattern:
			my ($consumed, %details) = eval{$pattern->_apply($left, $r)};
			
			# Check for exceptions:
			if ($@ ne '') {
				my $name = $self->get_bracketed_name_string;
				my $child_name = $pattern->get_bracketed_name_string;
				die "In re_or pattern$name, ${i}th pattern$child_name failed:\n$@"; 
			}
			
			# Make sure that the pattern didn't consume more than it was supposed
			# to consume:
			if ($consumed > $r - $left + 1) {
				my $name = $self->get_bracketed_name_string;
				my $child_name = $pattern->get_bracketed_name_string;
				die "In re_or pattern$name, ${i}th pattern$child_name consumed $consumed\n"
					. "but it was only allowed to consume " . ($r - $left + 1) . "\n"; 
			}
			
			# Check for a negative return value, which means 'try again at a
			# shorter length'
			if ($consumed < 0) {
				$r += $consumed;
				redo RIGHT_OFFSET;
			}
			
			# Save the results and return if we have a good match:
			if ($consumed) {
				$self->push_match($pattern => {left =>$left, %details
										, right => $left + $consumed - 1});
				return $consumed;
			}
			
			# At this point, the only option remaining is that the pattern
			# returned zero, which means the match will fail at this value
			# of left, so move to the next pattern:
			next PATTERN;
		}
	}
	return 0;
}

sub Scrooge::re_or {
	# If the first argument is an object, assume no name:
	return Scrooge::Or->new(patterns => \@_) if ref $_[0];
	# Otherwise assume that the first argument is a name:
	my $name = shift;
	return Scrooge::Or->new(name => $name, patterns => \@_);
}

=head2 re_and

This takes a collection of pattern objects and evaluates all of
them, returning true if all succeed. This does not take any quantifiers.

=cut

package Scrooge::And;
use parent -norequire, 'Scrooge::Grouped';
use strict;
use warnings;
use Carp;

# Return false if any of them fail or if they disagree on the matched length
sub _apply {
	my ($self, $left, $right) = @_;
	my $consumed_length = $right - $left + 1;
	my @to_store;
	my @patterns = @{$self->{patterns_to_apply}};
	for (my $i = 0; $i < @patterns; $i++) {
		my ($consumed, %details) = eval{$patterns[$i]->_apply($left, $right)};
		
		# Croak problems if found:
		if($@ ne '') {
			my $name = $self->get_bracketed_name_string;
			my $child_name = $patterns[$i]->get_bracketed_name_string;
			# Clear the stored matches before dying, just in case:
			$self->pop_match for (1..$i);
			# Make sure i starts counting from 1 in death note:
			$i++;
			die "In re_and pattern$name, ${i}th pattern$child_name failed:\n$@"; 
		}
		
		# Return failure immediately:
		if (not $consumed) {
			# Clear the stored matches before failing:
			$self->pop_match for (1..$i);
			return 0;
		}
		
		# Croak if the pattern consumed more than it was given:
		if ($consumed > $consumed_length) {
			my $name = $self->get_bracketed_name_string;
			my $child_name = $patterns[$i]->get_bracketed_name_string;
			# Clear the stored matches before dying, just in case:
			$self->pop_match for (1..$i);
			# Make sure i starts counting from 1 in death note:
			$i++;
			die "In re_and pattern$name, ${i}th pattern$child_name consumed $consumed\n"
				. "but it was only allowed to consume $consumed_length\n";
		}
		
		# If it didn't fail, see if we need to adjust the goal posts:
		if ($consumed < $consumed_length) {
			# Negative consumption means "adjust backwards":
			$consumed_length += $consumed if $consumed < 0;
			$consumed_length = $consumed if $consumed >= 0;
			
			# We're either about to quit or about to start over, so clear
			# the stored matches:
			$self->pop_match for (1..$i);
			
			# Fail if the new length would be too small:
			return 0 if $consumed_length < $self->min_size;
			
			# Adjust the right offset and start over:
			$right = $consumed_length + $left - 1;
			$i = 0;
			redo;
		}
		
		# Otherwise, we have a successful match, so add it:
		$self->push_match($patterns[$i], {left => $left, %details
							, right => $consumed_length + $left - 1});
		
	}
	
	# If we've reached here, we have a positive match!
	return $consumed_length;
}

# Called by the _prep method; stores minimum and maximum match sizes in an
# internal cache:
sub _minmax {
	my $self = shift;
	my ($full_min, $full_max);
	
	# Compute the min as the greatest minimum, and max as the least maximum:
	foreach my $pattern (@{$self->{patterns_to_apply}}) {
		my $min = $pattern->min_size;
		my $max = $pattern->max_size;
		$full_min = $min if not defined $full_min or $full_min < $min;
		$full_max = $max if not defined $full_max or $full_max > $max;
	}
	$self->min_size($full_min);
	$self->max_size($full_max);
}

sub Scrooge::re_and {
	# If the first argument is an object, assume no name:
	return Scrooge::And->new(patterns => \@_) if ref $_[0];
	# Otherwise assume that the first argument is a name:
	my $name = shift;
	return Scrooge::And->new(name => $name, patterns => \@_);
}

=head2 re_seq

Applies a sequence of patterns in the order supplied. Obviously
this needs elaboration, but I'll ignore that for now. :-)

This operates recursively thu:

 1) If the (i-1)th pattern succeeded, attempt to apply the ith pattern at its
    full quantifier range. If that fails, decrement the range until it it
    succeeds. If that fails, consider it a failure of the (i-1th) pattern at
    its current range. If it succeeds, move to the next pattern.
 2) If the ith pattern fails, the match fails.
 3) If the Nth pattern succeeds, return success.

=cut

package Scrooge::Sequence;
use parent -norequire, 'Scrooge::Grouped';
use strict;
use warnings;
use Carp;

# make sure that temp_matches is stashed:
sub _to_stash {
	return 'temp_matches', $_[0]->SUPER::_to_stash;
}

sub _init {
	my $self = shift;
	$self->SUPER::_init();
	$self->{temp_matches} = {};
}

=pod

working here - problems with recursion

Consider this recursive pattern:

  $recursive_seq = re_seq(A, $recursive_seq);

This won't pass add_name_to if either A or the sequence is named, and
if neither are named, it will recurse infinitely and never return. Now,
this problem is better solved with a repetition, but I bet a recursive
sequence pattern could be useful in some context, somewhere. Also, it
would fall into a recursive loop figuring out the max or min lengths. :-(

However, consider this pattern:

 my ($seq_pattern, $and_pattern);
 $seq_pattern = re_seq(A, $and_pattern);
 $and_pattern = re_and(B, $seq_pattern);
 
 # which is equivalent to 
 $seq_pattern = re_seq(A, re_and(B, $seq_pattern));

To the best of my knowledge, this sequence can never terminate successfully.
On the other hand, this one can terminate successfully:

 $seq_pattern = re_seq(A, re_or(B, $seq_pattern));

but that is equivalent to the following repetition pattern:

 $pattern = re_seq( REPEAT(A), B);

However, this pattern cannot be written like that:

 $pattern = re_seq(A re_or(B, $pattern), A);

That finds nested numerical signatures, much like the followin quasi-string
pattern:

 $pattern = re_seq(
     /\(/,          # opening paren
     /[^()]*/,      # anything which is not paretheses
     REPEAT([0,1],  # zero or one
         $pattern),   #     nested parentheses
     /[^()]*/,      # anything which is not paretheses
     /\)/           # closing paren
 );

So, by allowing for nested patterns, I allow for the possibility of recursive
descent parsing, which is not allowed under normal regexes. However, the
current engine does a poor job of this becuase it's not possible to look up
the 'left paren' in this example. For example, if you matched any sort of
nested bracketed expression, you couldn't check the left-hand bracket to
make sure the closing bracket matched.

This is unfortunate. At the moment, sequential matches only store the
results when it's clear that we have a successful match, which I do to
minimize excessive storage and deletion. In order to allow for something
like this (which I would like to be able to do), I would need to store the
state of the match immediately, and I'd need to make it retrievable during
the execution of the later rules.

=cut	

sub _apply {
	my ($self, $left, $right) = @_;
	return $self->seq_apply($left, $right, @{$self->{patterns_to_apply}});
}

sub seq_apply {
	my ($self, $left, $right, @patterns) = @_;
	my $pattern = shift @patterns;
	my $data = $self->{data};
	
	# Handle edge case of this being the only pattern:
	if (@patterns == 0) {
		# Make sure we don't send any more or any less than the pattern said
		# it was willing to handle:
		my $size = $right - $left + 1;
		return 0 if $size < $pattern->min_size;
		
		# Adjust the right edge if the size is too large:
		$size = $pattern->max_size if $size > $pattern->max_size;
		$right = $left + $size - 1;
		
		my ($consumed, %details) = eval{$pattern->_apply($left, $right)};
		
		# If the pattern croaked, emit a death:
		if ($@ ne '') {
			my $i = scalar @{$self->{patterns_to_apply}};
			my $name = $self->get_bracketed_name_string;
			my $child_name = $pattern->get_bracketed_name_string;
			die "In re_seq pattern$name, ${i}th pattern$child_name failed:\n$@"; 
		}
		
		# Croak if the pattern consumed more than it was given:
		if ($consumed > $size) {
			my $name = $self->get_bracketed_name_string;
			my $child_name = $pattern->get_bracketed_name_string;
			# Make sure i starts counting from 1 in death note:
			my $i = scalar @{$self->{patterns_to_apply}};
			die "In re_seq pattern$name, ${i}th pattern$child_name consumed $consumed\n"
				. "but it was only allowed to consume $size\n";
		}
		
		# Save the match if the match succeeded (i.e. '0 but true', or a
		# positive number):
		$self->push_match($pattern, {left => $left, %details,
				right => $left + $consumed - 1})
			if $consumed and $consumed >= 0;
		
		return $consumed;
	}
	
	# Determine the largest possible size based on the requirements of the
	# remaining patterns:
	my $max_consumable = $right - $left + 1;
	$max_consumable -= $_->min_size foreach (@patterns);
	
	# Fail if the maximum consumable size is smaller than this pattern's
	# minimum requirement. working here: this condition may never occurr:
	my $min_size = $pattern->min_size;
	return 0 if $max_consumable < $min_size;

	# Set up for the loop:
	my $max_offset = $max_consumable - 1 + $left;
	my $min_offset = $min_size - 1 + $left;
	my ($left_consumed, $right_consumed) = (0, 0);
	my $full_size = $right - $left + 1;
	my %details;
	
	# Start at the maximum possible size:
	
	LEFT_SIZE: for (my $size = $max_consumable; $size >= $min_size; $size--) {
		# Apply this pattern to this length:
		($left_consumed, %details) = eval{$pattern->_apply($left, $left + $size - 1)};
		# Croak immediately if we encountered a problem:
		if ($@ ne '') {
			my $i = scalar @{$self->{patterns_to_apply}} - scalar(@patterns);
			my $name = $self->get_bracketed_name_string;
			my $child_name = $pattern->get_bracketed_name_string;
			die "In re_seq pattern$name, ${i}th pattern$child_name failed:\n$@"; 
		}
		
		# Fail immediately if we get a numeric zero:
		return 0 unless $left_consumed;
		
		# Croak if the pattern consumed more than it was given:
		if ($left_consumed > $size) {
			my $name = $self->get_bracketed_name_string;
			my $child_name = $pattern->get_bracketed_name_string;
			# Make sure i starts counting from 1 in death note:
			my $i = scalar @{$self->{patterns_to_apply}} - scalar(@patterns);
			die "In re_seq pattern$name, ${i}th pattern$child_name consumed $left_consumed\n"
				. "but it was only allowed to consume $size\n";
		}
		
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
		
		# If we are here, we know that the current pattern matched starting at
		# left with a size of $size. Store that and then make sure that the
		# remaining patterns match:
		$self->push_match($pattern, {left => $left, %details,
				right => $left + $size - 1});
		
		$right_consumed = 0;
		my $curr_right = $right;
		eval {
			do {
				# Shrink the current right edge:
				$curr_right += $right_consumed;
				# Try the pattern:
				$right_consumed = $self->seq_apply($left + $size, $curr_right, @patterns);
			} while ($right_consumed < 0);
		};
		
		# Rethrow any problems after cleaning up the match stack:
		if ($@ ne '') {
			$self->pop_match;
			die $@;
		}
		
		# At this point, we know that the right pattern either matched at the
		# current value of $curr_right with a width of $right_consumed, or
		# that it failed. If it failed, clear the left pattern's match and
		# try again at a shorter size:
		if (!$right_consumed) {
			$self->pop_match;
			next LEFT_SIZE;
		}
		
		# If we are here, then it succeeded and we have our return values.
		# Be sure to return "0 but true" if that was what was returned:
		return $left_consumed if $left_consumed + $right_consumed == 0;
		return $left_consumed + $right_consumed;
	}
	
	# We can only be here if the combined patterns failed to match:
	return 0;
}

# Called by the _prep method, sets the internal minimum and maximum sizes:
# recursive check this
sub _minmax {
	my $self = shift;
	my ($full_min, $full_max) = (0, 0);
	
	# Compute the min and max as the sum of the mins and maxes
	foreach my $pattern (@{$self->{patterns_to_apply}}) {
		$full_min += $pattern->min_size;
		$full_max += $pattern->max_size;
	}
	$self->min_size($full_min);
	$self->max_size($full_max);
}

sub Scrooge::re_seq {
	# If the first argument is an object, assume no name:
	return Scrooge::Sequence->new(patterns => \@_) if ref $_[0];
	# Otherwise assume that the first argument is a name:
	my $name = shift;
	return Scrooge::Sequence->new(name => $name, patterns => \@_)
}

# Base class for situations involving more than one data set.
package Scrooge::Role::Subdata;
use strict;
use warnings;
use Carp;

# Should only need to override _prep_all
sub prep_all {
	my ($self, $data) = @_;
	
	# Call the prep function for each of them, keeping track of all those
	# that succeed. Notice that I capture errors and continue because every
	# single pattern needs to run its prep method in order for it to be 
	# safe for it to call its cleanup method.
	my @succeeded;
	my @patterns = @{ $self->{ patterns }};
	my @subset_names = @{ $self->{ subset_names }};
	my @errors;
	for my $i (0..$#patterns) {
		if( not exists $data-> { $subset_names[$i] }) {
			push @errors, "Subset name $subset_names[$i] not found";
		}
		my $successful_prep = eval { $patterns[$i]->prep($data-> { $subset_names[$i] }) };
		push @errors, $@ if $@ ne '';
		if ($successful_prep) {
			# Make sure the min size is not too large:
			push (@succeeded, $patterns[$i])
				unless $patterns[$i]->min_size > Scrooge::data_length($data);
		}
	}
	
	# Rethrow if we caught any exceptions:
	if (@errors == 1) {
		die(@errors);
	}
	elsif (@errors > 1) {
		die(join(('='x20) . "\n", 'Multiple Errors', @errors));
	}
	
	return @succeeded;
}

sub _verify{
	my $self = shift;
	# Make sure user supplied subset_names
	croak("Subset patterns must supply subset_names")
		unless defined $self-> { subset_names };
	# number of subset_names == number of patterns
	croak("Number of subset names must equal the number of patterns")
		unless @{ $self-> { subset_names }} == @{ $self-> { patterns }};
}

package Scrooge::Subdata::Sequence;
use strict;
use warnings;

our @ISA = qw(Scrooge::Sequence);

*prep_all = \&Scrooge::Role::Subdata::prep_all;

sub _init {
	my $self = shift;
	$self->SUPER::_init;
	Scrooge::Role::Subdata::_verify($self);
}

sub Scrooge::re_named_seq {
	# If @_ % 2 == 1, a name was supplied, if @_ % 2 == 0, a name wasn't supplied
	my @name_args;
	@name_args = (name => shift @_) if @_ % 2 == 1;
	
	# Create a hash to store subset_names and patterns
	my %subsets = @_;
	
	return Scrooge::Subdata::Sequence->new(		   @name_args, 
					   patterns     => [values %subsets] , 
					   subset_names => [keys %subsets]
				);
}

package Scrooge::Subdata::And;
use strict;
use warnings;

our @ISA = qw(Scrooge::And);

*prep_all = \&Scrooge::Role::Subdata::prep_all;

sub _init {
	my $self = shift;
	$self->SUPER::_init;
	Scrooge::Role::Subdata::_verify($self);
}

sub Scrooge::re_named_and {
	my @name_args;
	@name_args = (name => shift @_) if @_ % 2 == 1;
	
	my %subsets = @_;
	
	return Scrooge::Subdata::And->	new(		@name_args, 
					patterns     => [values %subsets],
					subset_names => [keys %subsets]
					);
}

package Scrooge::Subdata:Or;
use strict;
use warnings;

our @ISA = qw(Scrooge::Or);

*prep_all = \&Scrooge::Role::Subdata::prep_all;

sub _init {
	my $self = shift;
	$self->SUPER::_init;
	Scrooge::Role::Subdata::_verify($self);
}

sub Scrooge::re_named_or {
	my @name_args;
	@name_args = (name => shift @_) if @_ % 2 == 1;
	
	my %subsets = @_;
	
	return Scrooge::Subdata::Or->	new(		@name_args,
					patterns     => [values %subsets],
					subset_names => [keys %subsets]
					);
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
than try to impose an untested pattern notation, this module
simply lets you construct the pattern object directly.

=back

=head1 Implementation Details

These are many details that I hope will help you if you try to look closely
at the implementation of this system.

=over

=item Details of stashing and unstashing

I'm keeping these notes as they explain how things work fairly well:

I believe that multiple copies of the same pattern (and an implementation of
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

=item patterns within Rules

Even more likely and problematic than the above problem is the possibility
that a particular pattern object is used within a pattern as well as B<within
the condition of neighboring pattern>. This is very much a problem since a
pattern used within the condition of another will B<not> be name-clash
detected and it will fiddle with internal data, including the current piddle
of interest.

Initially, I thought it would be adequate to implement a stack system on
C<_prep> and C<_cleanup>. However, named patterns need to be able to return
their offsets after C<_cleanup> is called, so these must B<not> be
cleaned-up. To solve this problem, I need to determine some means for the
pattern to realize that it has switched contexts, and then stash or unstash
the internal information like the match offsets and the piddle (and anything
else that's important.)

=back

=head1 TODO

These are items that are very important or even critical to getting Scrooge to
operate properly.

=over

=item Testing: Multiple copies of the same pattern, nested calls to pattern

I have implemented a match stack to allow for multiple copies of the same
pattern within a larger pattern. I have also implemented a stashing and
unstashing mechanism to allow for patterns to be called from within other
patterns without breaking the original. However, the code remains untestd.

=item Proper prep, cleanup, and stash handling on croak

I have added lots of code to handle untimely death at various stages of
execution of the pattern engine. I have furthermore added lots
of lines of explanation for nested and grouped patterns so that pin-pointing
the exact pattern is clearer. At this point, I need to test that all of the
deaths do not interfere with proper cleanup and that 

=back

=head1 IDEAS

This is the place where I put my ideas that I would like to implement, but
which are not yet implemented and which are not critical to the sensible
operation of the pattern engine.

=over

=item Concise Syntax Ideas

A potential concise syntax might look like this:

 $pattern = qnre{
    # Comments and whitespace are allowed
    
    # If there is more than one pattern in a row, the grouping
    # is assumed to be a re_seq group.
    
    # ---( Basics )---
    # Perl scalars and lists are properly interpolated:
    $my_pattern_object
    @my_pattern_objects
    
    # barewords are assumed to be pattern constructors
    # and are called with the given args
    reg1(args)
    
    # The interior of an argument list is pased *exactly* as is to the
    # constructor:
    reg2( value => $quantitiy, %other_args )
    
    # square bracket notation indicates the min
    # and max length that a pattern can match
    reg1(args)[quantifiers]
    
    # ---( Prefixes )---
    # Barewords are called as-is unless you specify an auto-prefix:
    Scrooge::OneD::
    
    # Now these constructors have that prefix added so:
    reg1(args)
    # is interpreted as Scrooge::OneD::reg1(args)
    
    # You can explicitly resolve a constructor like so:
    Scrooge::Extra::reg3(args)
    
    # To restore the original prefix, simply use two colons:
    ::
    
    # ---( Quantifiers )---
    # You can add square brackets immediately after a pattern's args to
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
    &< ... patterns ... >       # AND group
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
    # Repeat count comes before a pattern:
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
    # You can name any normal pattern by adding .name immediately after the
    # constructor name, before any arguments or quantifiers:
    reg2.name
    reg4.name(args)
    reg5.name[5, 20%]
    
    # You can name any grouped pattern by inserting the name between the
    # symbol and the angle brackets:
    $.my_sequence< ... >
    |.my_or< ... >
    # Spaces are allowed:
    & . named < ... >
    
    # You can name a repetition by putting the name before the colon:
    5.name:reg2
    
    # You can name both the repetition and the pattern, but they must have
    # different names:
    [4,8].name:reg2.name2
    
    # Once named, you can insert a previous named pattern like so:
    \name
    
    
    # ---( Clarifications )---
    # Note, this statement is not formatted clearly:
    pattern(args)[repeat, count] 
        :pattern2(args)
    # It means this:
    pattern(args)
    [repeat, count]:pattern2(args)
    
 };

I would use Devel::Declare to convert this into a set of nested
constructors.

=item Grouping quantifiers

It would be nice to be able to combine quantifiers and groups. A major issue
in this would be figuring out how to handle named captures for such a
situation.

=item OPTIMIZE Grouping

Include some sort of OPTIMIZE grouping that attempts to partition the data
in an optimal fashion using some sort of scoring mechanism?

 # Find the optimal division between an exponential drop
 # and a linear fit:
 my $pattern = NRE::OPTIMIZE($exponential_drop, $linear)

=back

=head1 SEE ALSO

Interesting article on finding time series that "look like" other time
series:

http://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.133.6186&rep=rep1&type=pdf

=head1 AUTHOR

David Mertens C<dcmertens.perl@gmail.com>
