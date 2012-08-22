use strict;
use warnings;
package Scrooge;
use Carp;
use Exporter;
use PDL;

our @ISA = qw(Exporter);

our @EXPORT = qw(re_or re_and re_seq re_sub re_any
		 re_zwa_sub re_zwa_position
		 re_anchor_begin re_anchor_end 
		 re_named_seq re_named_and re_named_or);

=head1 NAME

Scrooge - a greedy pattern engine for more than just strings

=cut

our $VERSION = 0.01;

=head1 VERSION

This documentation is for version 0.01 of Scrooge.

=head1 SYNOPSIS

 use Scrooge;
 
 # Build the pattern object first. This one
 # matches positive values and assumes it is
 # working with piddles.
 my $positive_pattern = re_sub(sub {
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

=head1 GETTING STARTED

If you are new to Scrooge, I recommend reading L<Scrooge::Tutorial>, which
walks you through building Scrooge patterns, both from standard patterns and
from easily written customizable ones.

=head1 DESCRIPTION

Scrooge creates a set of classes that let you construct greedy pattern objects
that you can apply to a container object such as an anonymous array or a piddle.
Because the patterns you might match are limitless, and the sort of container
you might want to use is also limitless, this module provides a means for
easily creating your own patterns, the glue necessary to put them together
in complex ways, and the engine to match those patterns against your data.
It does not offer a concise syntax (as you get with regular expressions),
but it provides the engine to do the work. You could create a module to parse
a concise syntax into the engine's pattern structures using
L<Regexp::Grammars> or a similar parsing module, if you want something like
that.

To get warmed up, let's look at some Perl regular expressions (which perform
greedy matching on strings):

 do_something()      if $string =~ /(ab)|(cd)/;
 do_something_else() if $string =~ /(a?b+)|(c*\d{3,})/;

The first expression does something if the string matches either 'a'
followed by 'b', or if it matches 'c' followed by 'd'. The second expression
does something else if the string matches zero or one 'a' followed by one or
more 'b', or if it matches zero or more 'c' followed by at least three
digits. The second regular expression differs from the first because it
makes use of quantifiers and because it uses a character class (the C<\d>).

The Scrooge equivalents of these take up quite a bit more space to
construct because as already mentioned there is no concise syntax for
creating Scrooge patterns. Also, Scrooge does not match against strings by
default, but against other sorts of containers like anonymous arrays. Here
is how to build a pattern that checks a PDL object for a positive number
followed by a local maximum, or a negative number followed by a local minimum.

 use Scrooge::PDL;
 my $pattern = re_or(
     re_seq( re_range(above => 0), re_local_max ),
     re_seq( re_range(below => 0), re_local_min )
 );

You would then apply that pattern to some data like so:

 do_something() if $pattern->apply($data);

The Scrooge pattern matching library can be conceptually structured into three
tiers. The top-level tier is a set of functions that help you quickly build
patterns such as C<re_seq> and C<re_any>, as well as the Scrooge methods
that enable you to run patters on data and retrieve the results. The mid-level
tier is the set of classes that actually implement that functionality such as
C<Scrooge::Quantified> and C<Scrooge::Seq>, along with how to create your own
classes. The bottom-level tier is the Scrooge base class and its internal
workings as a pattern matching engine. The documentation that follows progresses
from top to bottom.

=head1 PATTERNS

These are the usable short-name pattern constructors provided by C<Scrooge>.
The user-level methods that work across all C<Scrooge> patterns are discussed
below, in the L</METHODS> section.

=head2 re_any

Matches any value. This is a quantified pattern, which
means you can specify the minimum and maximum lengths that the pattern should
match. You can also name the regex.

 # Matches a single element:
 my $anything = re_any;
 
 # Matches 2-5 elements:
 my $some_stuff = re_any([2 => 5]);
 
 # Named capture matching between 15 and 100% of the data:
 my $stored_stuff = re_any('recall_me', [15 => '100%']);

=cut

sub re_any {
	croak("Scrooge::re_any takes one or two optional arguments: re_any([[name], quantifiers])")
		if @_ > 2;
	
	# Get the arguments:
	my $name = shift if @_ == 2;
	my $quantifiers = shift if @_ == 1;
	$quantifiers = [1,1] unless defined $quantifiers;
	
	# Create the subroutine pattern:
	return Scrooge::Quantified->new(quantifiers => $quantifiers
		, defined $name ? (name => $name) : ());
}


=head2 re_sub

Evaluates the supplied subroutine on the current subset of data, optionally
taking a capture name and a set of quantifiers. If no quantifiers are
specified, they default to C<[1, 1]>, that is, it matches one and only one
value.

The three arguments supplied to the function are (1) original data container
under consideration, (2) the left index offset under consideration, and (3)
the right index offset.

If the match succeeds, your subroutine should return the number of matched
values. If the match succeeds but it consumed zero values (i.e. a zero-width
assertion), return the string "0 but true", which is a magical value in Perl
that evaluates to true in boolean context, yet which is numerically zero in
numeric context and does not gripe when converted from a string value
to a numeric value (even when you've activated warnings). If the match will
always fail for the given left offset, you should return 0. Otherwise, if it
fails for the given value of the right offset but might succeed for a smaller
right offset, return -1. Return values are discussed in detail under the
documentation for L<_apply|/_apply ($left, $right)>.

 # Create a match sub to use (you can also supply an anonymous sub
 # directly to re_sub, if you wish)
 sub my_match_sub {
     my ($data, $l_off, $r_off) = @_;
     
     # Fail if can't match at $l_off
     return 0 if $data->can_never_match_at($l_off);
     
     # Return the matched length if it succeeds:
     return ($r_off - $l_off + 1)
         if $data->matches(from => $l_off, to => $r_off);
     
     # Not sure, return -1 to try a different value of $r_off
     return -1;
 }
 
 # Match one value with the custom sub
 my $custom_match = re_sub(\&my_match_sub);
 
 # Match between two and ten values with the custom sub
 my $quantified_custom_match
     = re_sub([2 => 10], \&my_match_sub);

=cut


# This builds a subroutine pattern object:
sub re_sub {
	croak("re_sub takes one, two, or three arguments: re_sub([[name], quantifiers], subref)")
		if @_ == 0 or @_ > 3;
	
	# Get the arguments:
	my $name = shift if @_ == 3;
	my $quantifiers = shift if @_ == 2;
	my $subref = shift;
	
	$quantifiers = [1,1] unless defined $quantifiers;
	
	# Create the subroutine pattern:
	return Scrooge::Sub->new(quantifiers => $quantifiers, subref => $subref
		, defined $name ? (name => $name) : ());
}

=head2 re_anchor_begin

Matches at the beginning of the data.

=cut

sub re_anchor_begin {
	return Scrooge::ZWA->new(position => 0);
}

=head2 re_anchor_end

Matches at the end of the data.

=cut

sub re_anchor_end {
	return Scrooge::ZWA->new(position => '100%');
}

=head2 re_zwa_position

Creates a position-based zero-width assertion. Zero-width assertions can
come in many flavors and assert many things, but the basic zero-width assertion
lets you make sure that the pattern matches at a particular position or range of
positions.

Zero-width assertions match B<in between> points. For example, if you have a
three-point sequence of values (10, 12, 33), there are four positions that a
zero-width assertion can match: to the left of 10, between 10 and 12, between 
12 and 33, and to the right of 33.

For example, using the positional assertion, I can match against
the two points to the left and to the right of the 10% with this pattern:

 my $left_and_right_of_ten_pct = re_seq(
     re_any([2 => 2]),
     re_zwa_position('10%'),
     re_any([2 => 2]),
 );

To match at one position, pass a single value. To match at a range a positions,
pass the starting and ending positions:

 re_zwa_position('10% + 1')
 re_zwa_position('5% - 1' => 20)

You can say quite a bit when specifying a position. To give you an idea,
here's a table describing different specifications and their resulting positions
for a 20-element array:

 string       offset     notes
 0            0
 1            1
 1 + 1        2
 -1           19
 5 - 10       -5         This will never match
 10%          10
 10% + 20%    6
 50% + 3      13
 100% + 5     25         This will never match
 10% - 5      -3         This will not match this array
 [10% - 5]    0          -3 => 0
 [6 - 10]     -4         This will never match
 -25          -5         This will not match this array
 [-25]        0          -25 => -5 => 0
 12% + 3.4    6          Rounded from 5.8
 14% + 3.4    6          Rounded from 6.2

Notice in particular that non-integers are rounded to the nearest integer and
strings wrapped in square brackets are truncated to the minimum or maximum offset
if the evaluation of the expression for the specific set of data falls outside
the range of valid offsets.

=cut

sub re_zwa_position {
	return Scrooge::ZWA->new(position => $_[0]) if @_ == 1;
	return Scrooge::ZWA->new(position => [@_]) if @_ == 2;
	croak("re_zwa_position expects either one or two arguments");
}

=head2 re_zwa_sub

Creates a zero-width assertion that matches at a position (if specified) and
matches against your supplied subroutine. This takes between one and three
arguments. In the one-argument form, it expects a subroutine that it will
test for a match. In the two-argument form, it expects a position specification
followed by the subroutine to match. In the three-argument form, it expects
a capture name, a position, and a subroutine.

The subroutine that you provide should accept two arguments: the data to match and the
left offset of the current match location. If the assertion succeeds, your
function should return the string '0 but true', and if the assertion fails,
your function should return a false value, such as the empty string.

=cut

sub re_zwa_sub {
	# This expects a subroutine as the last argument and key/value pairs
	# otherwise:
	croak("re_zwa_sub takes one, two, or three arguments: re_zwa_sub([[name], position], subref")
		if @_ == 0 or @_ > 3;
	
	# Pop the subref off the end and unpack the args
	my %args;
	$args{name} = shift if @_ == 3;
	$args{position} = shift if @_ == 2;
	$args{subref} = shift;
	
	# Verify the subref
	croak("re_zwa_sub requires a subroutine reference as the last argument")
		unless ref($args{subref}) eq ref(sub{});
	
	# Create and return the zwa:
	return Scrooge::ZWA::Sub->new(%args);
}

=head2 re_or

Takes a collection of pattern objects and evaluates all of
them until it finds one that succeeds. This does not take any quantifiers.

=cut

sub re_or {
	# If the first argument is an object, assume no name:
	return Scrooge::Or->new(patterns => \@_) if ref $_[0];
	# Otherwise assume that the first argument is a name:
	my $name = shift;
	return Scrooge::Or->new(name => $name, patterns => \@_);
}

=head2 re_and

Takes a collection of pattern objects and evaluates all of
them, returning true if all succeed. This does not take any quantifiers.

=cut

sub re_and {
	# If the first argument is an object, assume no name:
	return Scrooge::And->new(patterns => \@_) if ref $_[0];
	# Otherwise assume that the first argument is a name:
	my $name = shift;
	return Scrooge::And->new(name => $name, patterns => \@_);
}

=head2 re_seq

Applies a sequence of patterns in the order supplied.

This operates recursively thus:

 1) If the (i-1)th pattern succeeded, attempt to apply the ith pattern at its
    full quantifier range. If that fails, decrement the range until it it
    succeeds. If that fails, consider it a failure of the (i-1th) pattern at
    its current range. If it succeeds, move to the next pattern.
 2) If the ith pattern fails, the match fails.
 3) If the Nth pattern succeeds, return success.

=cut

sub re_seq {
	# If the first argument is an object, assume no name:
	return Scrooge::Sequence->new(patterns => \@_) if ref $_[0];
	# Otherwise assume that the first argument is a name:
	my $name = shift;
	return Scrooge::Sequence->new(name => $name, patterns => \@_)
}

=head2 SIMULTANEOUSLY MATCHING ON MULTIPLE DATASETS

You may very well have multiple sequences of data against which you want to
write a pattern. For example, if you have both position and velocity data
for a trajectory, you may want to find the first velocity maximum that
occurs B<after> a maximum in position. The three grouping regexes that follow
are similar to the grouping regexes that came before, except that they let
you specify the name of the dataset against which to match.

Name of the dataset? What name? To match against multiple datasets, C<apply>
a pattern on an anonymous hash with key/value pairs in which the keys are
the names of the different data sets and the values are the actual data sets,
the things you'd normally send to C<apply>.

The semantics of multiple, named data sets is still in flux and will change in
the future. For now, feel free to use these B<only if each object works with one
data set>. Calling the same pattern on multiple data sets will result in matches
being run only on the first dataset. If you need to run the same pattern on
multiple data sets, create multiple copies of the pattern.

=cut

sub _build_named_data_group_pattern {
	my $class_name = shift;
	my @name_args = (name => shift @_) if @_ % 2 == 1;
	my (@patterns, @names);
	while(@_ > 0 ) {
		push @names, (shift @_);
		push @patterns, (shift @_);
	}
	
	return $class_name->new(
		@name_args,
		subset_names => \@names,
		patterns => \@patterns,
	);
}

=head2 re_named_or

Applies a collections of patterns just like re_or, except that the data
applied to each pattern is based on the given name. The sequence can take an
optional first name, so the calling convention is:

 re_named_or( [name],
     set_name_1 => data_1,
     set_name_2 => data_2,
     ...
 );

=cut 

sub re_named_or {
	return _build_named_data_group_pattern('Scrooge::Subdata::Or', @_);
}

=head2 re_named_and

Applies a collections of patterns just like re_and, except that the data
applied to each pattern is based on the given name. The sequence can take an
optional first name, so the calling convention is:

 re_named_and( [name],
     set_name_1 => data_1,
     set_name_2 => data_2,
     ...
 );

=cut

sub re_named_and {
	return _build_named_data_group_pattern('Scrooge::Subdata::And', @_);
}

=head2 re_named_seq

Applies a sequence of patterns on the associated data sets in the order
supplied. The sequence can take an optional first name, so the calling 
convention is:

 re_named_seq( [name],
     set_name_1 => data_1,
     set_name_2 => data_2,
     ...
 );

=cut

sub re_named_seq {
	return _build_named_data_group_pattern('Scrooge::Subdata::Sequence', @_);
}

=head1 USER METHODS

These are the user-level methods that each pattern provides. Note that this
section does not discuss subclassing or constructors; those are discussed 
further below under L</SUBCLASSING> XXX. This section is the reference manual
for using your patterns once you've built them. Class authors should B<not>
override these methods, but instead should override methods with leading
underscores discussed under L</AUTHOR METHODS>.

=head2 apply ($data)

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

Note that you will get the empty list if your pattern fails, so if this fails:

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

If you only want to know where a sub-pattern matches, you can name that sub-pattern
and retrieve sub-match results using C<get_offsets_for>, as discussed below.

This method can croak for a few reasons. If any of the patterns croak
during the preparation or matching stage, C<apply> will do its best to
package the error message in a useful way and rethrow the error. Also, if
you are trying to use a data container for which Scrooge does not know how
to compute the length, C<apply> will die saying as much. (See L</data_length>
to learn how to teach Scrooge about your data container.)

=cut

# User-level method, not to be overridden.
sub apply {
	my $self = shift;
	my $data;
	if (@_ == 1) {
		$data = shift;
	}
	elsif (@_ % 2 == 0) {
		$data = {@_};
	}
	else {
		croak('Scrooge::apply expects either a data argument or key/value data pairs');
	}
	
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
	
	# Get the data's length
	my $N = data_length($data);
	croak("Could not get length of the supplied data")
		if not defined $N or $N eq '';
	
	# Note change in local state:
	$self->is_applying;
	
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

=head2 get_details_for ($name)

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
within the containers. That's probably exactly what you expected, so if this
last paragraph seems a bit confusing, you're probably best off just ignoring 
it.

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

=head2 get_details

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

=head1 AUTHOR METHODS

This section documents the basic class structure of Scrooge for those interested
in writing pattern classes. If your goal is to simply build and apply patterns
to data then this section is not for you.

There are many methods provided by Scrooge. Some of them are explicitly meant to
be overridden; others are explicitly not meant to be overridden. In general,
methods that begin with an underscore are overridable; methods that do B<not>
begin with an underscore should be left alone.

=head2 _init

This method is invoked during the construction of the pattern. The object is
hash-based and contains whichever key/value pairs were sent to the C<new> class
method. It will also indicate that its state is C<'not running'>, though you
should not change that unless you know what you're doing.

This method is meant to be overloaded by derived classes and should do whatever
constructor initialization stuff needs to happen. Remember that at this stage,
you do not have access to the data that you will match. That comes later. This
stage should primarily focus on argument validation and initialization. Once
your C<_init> code has finished, your object should be ready to have its
C<_prep> method invoked.

=cut

# Default init does nothing:
sub _init {
	croak('Scrooge::_init is a method that takes no arguments')
		unless @_ == 1;
}

=head2 _prep ($data)


The very last stage of C<prep> is calling this method, C<_prep>, whose name
differs from C<prep> only in the presence of the leading underscore. As a class
author, you should override this method. This function is called before the
pattern hammers on the supplied data. If you have any data-specific setup to do,
do it in this function. You should perform as much pre-calculation and
preparation as possible in this code so as to minimize repeated calculations in
your C<_apply> method.

If you are not deriving your class from L</Scrooge::Quantified>,
L</Scrooge::ZWA>, or L</Scrooge::Grouped> and you intend for your pattern to
run, you must either set C<< $self->{min_size} >> and C<< $self->{max_size} >>
at this point or you must override the related internal functions so that they
operate correctly without having values associated with those keys. The
C<min_size> and C<max_size> methods operate both as setters and as getters, so
the following code is an appropriate means to set these variables in your
C<_prep> method:

 $self->min_size($some_size);
 $self->max_size($some_size);

Having examined the data, if you know that this pattern will not match 
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

NOTE: Support for multiple data sets
will likely require that the name of the data be passed. In the future, it is
likely that the sub-dataset's name, if supplied, will be the second argument. At
any rate, consider the interfae of this function to be in alpha, and that
changes may occurr in the not-distant future. For the time being, as was
mentioned above under L</SIMULTANEOUSLY MATCHING ON MULTIPLE DATASETS>,
your users will have to stick with one dataset per pattern object. If they stick
with that, then everything mentioned above will work fine.

=cut

# Default _prep simply returns true, meaning a successful prep:
sub _prep {	return 1 }

=head2 _to_stash

In the discussion on L</_prep>, I mentioned calculation of internal data. If you
store any internal data, you should override C<_to_stash> and include the names
of those keys.

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

What should you have stashed? Basically, you should stash anything that you set
in C<_prep>, or which you generally expect to remain unchanged before, during,
and after the application of your pattern. The default keys that are stashed
include C<data>, C<min_size>, C<max_size>, and C<match_details>. The first three
are set during the prep stage and the last one is set after a successful match.
Hopefully that gives you some idea of what to stash. In general, stashing data
is relatively cheap but having sub-patterns destroy the internal state of your
pattern is impossible to recover from. When in doubt, if you put data into one
of your hash's keys, you should stash it.

=cut

# The internal keys with values that we want to protect in case of
# recursive usage:
sub _to_stash {
	croak('Scrooge::_to_stash is a method that takes no arguments')
		unless @_ == 1;
	return qw (data min_size max_size match_details);
}

=head2 min_size, max_size

These are getters and setters for the current lengths that indicate the
minimum and maximum number of elements that your pattern is capable of
matching. Scrooge expects these values to be set before or during L</_prep>
and afterwards consults whatever was stored there.

Unlike other non-underscore methods, you can override these if you like.

Note that at the moment, C<min_size> and C<max_size> are not querried
during the actual operation of the pattern, only at the beginning. In other
words, overriding these methods so that their return value changes throughout
the course of the pattern match (with a hope of reporting a more precise value,
perhaps) will not work.

You are guaranteed that C<_prep> will have been run before these methods are
run, and they will not be run if C<_prep> returned a false value. If you
call the base class's prep, you are also guaranteed that if C<min_size> or
C<max_size> are keys in the object, they will be the default values.

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

=head2 _apply ($left, $right)

This method is called when it comes time to apply the pattern to see if it
matches at the current left and right offsets, which are the two arguments
supplied to the method. The data is not included becaus it was cached under the
C<data> key during L</prep>; you can retrieve it under that key if you need it.

If your pattern encloses another, it should call the enclosed pattern's C<_apply>
method and take its return value into consideration with its own, unless
it returned 0 when you called C<_prep>. In that case, you should not call it.

There are actually many different return values, all with different meanings.
In short, if the condition matches, you should return the number of items matched
and any details that you wish the user to get when they call L</get_details_for>
on your pattern (assuming it's named), as key/value pairs. If it
does not match for this range but B<might> match for a shorter range (if
C<$right> were moved a little bit to the left), return -1. If it cannot
match starting at C<$left>, return numeric zero. Those are the basics. However,
other return values are allowed and using them can significantly improve the
performance of your pattern.

Here is a rundown of what to return when:

=over

=item More than the Full Length

You should never return more than the full length that was given to you (which
is C<$right - $left + 1>), and if you do, Scrooge will croak saying

 Internal error: pattern of class <class> consumed more than it was given

=for details
XXX add this to the list of errors reported.

=item Full Length

Return the full length, C<$right - $left + 1>, if the condition matches
against the full length.

=item Less than the Full Length

If your condition does not match against the entire range but it is easy
to check against shorter lengths, you can return the number of elements that it
matches. In terms of Perl arrays, if the match fails against the slice
C<@data[$left .. $right]> but it's easy to find some C<$less_than_right> for
which the match succeeds (against C<@data[$left .. $less_than_right]>), then
you can return the length of that match, which would be
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

=for details
XXX - make sure PDL's range pattern handles this correctly

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
C<$left> to C<$right>, but it might match for the same value for C<$left> and a
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
since the result will never be used: C<$first> will match at C<$right - 1> before
C<$second> gets a chance.

=back

Again, any positive match should also return pertinent details as key/value
pairs. The quintesential example is, say, a linear fit. If the data "looks"
linear (using, say, MSER or a Durbin-Watson statistic), you could return the
number of items included in that linear fit, along with they slope and the
intercept. Such a return statement might look like this:

 #       number matched                   details
 return ($right - $left + 1, slope => $slope, intercept => $intercept);

The details are stored via the C<store_match> method. In addition to the
key/value pairs returned by C<_apply>, the left and right offsets of the match
are stored under the keys C<left> and C<right>.

Note that the data and pre-calculation caching is a major tripping point of
multiple dataset matching, so the arguments to C<_apply> may change in the
future. The most likely situation is that the name of the dataset will be
included as a third argument. Stay tuned.

=head2 _cleanup

The overridable method C<_cleanup> allows you to clean up any resources at the
end of a match. Apart from stash management by grouping patterns (which have to
call C<cleanup> on their sub-patterns), I have not yet used C<_cleanup> in my
patterns. However, it is conceivable that you might want to allocate some
resource in the C<prep> stage, and then unallocate that resource at the end of
of the match. In that case, this overridable method is precisely what you will
want to use.

C<cleanup> (and therefore C<_cleanup> should only be called once, but your code
needs to be flexible enough to accomodate multiple calls to C<_cleanup> without
dying.

=cut

# Default _cleanup does nothing
sub _cleanup { }

=head1 DEEP METHODS

These are methods that the general Scrooge subclass writer won't need, but are
still needed sometimes.

=head2 new ($class, %args)

The role of the constructor is to create a blessed hash with any internal
data representations. This method name does not begin with an underscore, which
means that class authors should not override it. It is also a bit odd: typically
it is neither invoked by the user nor overridden by class authors. In general, a
class author supplies a short-form constructor that invokes C<new>, which
prepares a few bits and pieces of the internal state before calling L<_init>. If
you need to override initialization, you should override L</_init>.

This method croaks if, after the class name, there is not an even number of 
remaining arguments since it blesses the hash of key/value pairs into the
supplied class.

The basic chain is user-level-constructor -> C<new> -> C<_init>. The resulting
object at the end of this chaing must be capable of running its C<prep> method.

=cut

sub new {
	my $class = shift;
	croak("Internal Error: args to Scrooge::new must have a class name and then key/value pairs")
		unless @_ % 2 == 0;
	my $self = bless {@_}, $class;
	
	# Set the default state so that stashing works correctly:
	$self->{state} = 'not running';
	
	# Initialize the class:
	$self->_init;
	
	return $self;
}

=head2 add_name_to ($hashref)

This method is called called during the initialization stage of grouping
patterns. It takes the given anonymous hash and, if it is named, adds itself
under its name to the hash. This is used to build a quick look-up table for
pattern names, which is handy both for retrieval of results after a successful
match and for ensuring that named patterns do not clash when building complex
patterns.

If you are writing a new grouping pattern, in addition to adding your own name,
you should check for and add all of your childrens' names. (This behavior is
handled for you by L</Scrooge::Grouped>.) Note that if your pattern's name
is already taken, you should croak with a meaningful message, like

 croak("Found multiple patterns named $name.");

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

=head2 get_bracketed_name_string

This returns a string to be used in error messages. It returns an empty string
if the pattern does not have a name, or ' [name]' if it does have a name. This
is useful for constructing error messages of the following form:

 my $name = $self->get_bracketed_name_string;
 croak("Pattern$name tried to frobnosticate!")

You shouldn't override this unless you want more detailed error messages.

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

=head2 is_prepping

This is a setter method that changes the internal state of the pattern just
before L<prep|/prep ($data)> gets called.

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

=head2 prep ($data)

This method is neither user-level nor overridable. It is called as the first
stage of C<apply>. It handles the messy business of handling the pattern's
internal state and stashing the to-be-matched data in the C<data> key of the
(hash-based) object before calling C<_prep>.

As a class author, you should overload C<_prep> to control how your class
prepares for being matched.

=cut

sub prep {
	croak('Scrooge::prep is a one-argument method')
		unless @_ == 2;
	my ($self, $data) = @_;
	
	# Make sure this only gets run once per call to apply:
	return 1 if $self->{state};
	$self->{state} = 'prepping';
	
	# Stash everything. Note that under repeated invocations of a pattern, there
	# may be values that we traditionally stash that have lingered from the
	# previous invocation.
	# I would like to remove those values, but that causes troubles. XXX :-(
#	my @to_stash = $self->_to_stash;
	if (defined $self->{data}) {
		push @{$self->{"old_$_"}}, $self->{$_} foreach $self->_to_stash;
#			@to_stash;
	}
	else {
		#delete $self->{$_} foreach @to_stash;
	}
	
	$self->{data} = $data;
	return $self->_prep($data);
}

# Note: right now the pattern knows that it is being prepped inside a 

=head2 is_applying

This is a setter method that changes the internal state of the pattern just
before L</_apply> gets called.

=cut

sub is_applying {
	$_[0]->{state} = 'apply';
}

=head2 store_match ($hashref)

This method stores the match details under the C<match_details> key if the
pattern is named. Match details include the left and right offsets of the match
along with whatever key/value pairs are returned by the successful call to
L</_apply>. The results are actually stored in an anonymous array so that
multiple occurrances of the same pattern can match without overwriting each
other.

=cut

sub store_match {
	croak('Scrooge::store_match is a one-argument method')
		unless @_ == 2;
	my ($self, $details) = @_;
	
	# Only store the match if this is named
	return unless exists $self->{name};
	push @{$self->{match_details}}, $details;
}

=head2 clear_stored_match

Grouping patterns like L</re_and> and L</re_seq> need to have some way of
clearing a stored match when something goes wrong, and they do this by
calling C<clear_stored_match>. In the base class's behavior, this function
only does anything when there is a name associated with the pattern, and even
then only clears the most recently stored match. Grouping pattern objects should
clear their children patterns in addition to clearing their own values.

=cut

sub clear_stored_match {
	croak('Scrooge::_stored_match is a method that takes no arguments')
		unless @_ == 1;
	my $self = shift;
	
	return 0 unless exists $self->{name};
	pop @{$self->{match_details}};
	return 0;
}

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
#	''			=> sub { return length $_[0] },
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

=head2 is_cleaning

This is a setter method that changes the internal state of the pattern just
before L</cleanup> gets called.

=cut

# As with is_prepping, do *not* set the state since cleaning's short-
# circuiting depends on this being clear:
sub is_cleaning {
	delete $_[0]->{state};
}

=head2 cleanup

This method is called in one of two situations: (1) if you just returned 
zero from C<_prep> and (2) after the engine is done, regardless of whether
the engine matched or not. As with other methods that have an associated
underscore-prefixed variant, you should not override this method as it performs
various stashed-value restoration. This method eventually calls the
underscore method L</_cleanup>, which you can override.

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

=head1 CLASSES

The heierarchy of basic Scrooge patterns have three basic flavors:
quantified patterns, zero-width assertions, and grouped patterns. If you are
trying to write a rule to apply to data, you are almost certainly interested
in creating a new quantified pattern or zero-width assertion.

=cut

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
C<_init>, C<_prep>, and C<_apply> methods. If you need a pattern object that
handles quantifiers but you do not care how it works, you should inheret from
this base class and override the C<_apply> method.

Scrooge::Quantified provdes overrides for the following methods:

=over

=item _init

Scrooge::Quantified provides an C<_init> function that removes the C<quantifiers>
key from the pattern object, validates the quantifier strings, and stores them
under the C<min_quant> and C<max_quant> keys.

This method can croak for many reasons. If you do not pass in an anonymous array
with two arguments, you will get either this error:

 Quantifiers must be specified a defined value associated with key [quantifiers]

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

=item _prep

Given a set of data, this method calculates the minimum and maximum number of
elements that will match based on the quantifiers stored in C<min_quant> and
C<max_quant>. If it turns out that the minimum size is larger than the maximum
size, this method returns 0 to indicate that this pattern will never match. It
also does not set the min and max sizes in that case. That means that if you
inheret from this method, you should invoke this C<_prep> method; if the return
value is zero, your own C<_prep> method should also be zero, and if the return
value is 1, you should proceed with your own C<_prep> work.

=cut

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
	$self->min_size($min_size);
	$self->max_size($max_size);
	return 1;
}

=item _apply

This very simple method returns the full length as a successful match. It does
not provide any extra match details.

=cut

# apply (the non-overridable method) will store the saved values:
sub _apply {
	my (undef, $left, $right) = @_;
	return $right - $left + 1;
}

=back

=cut

# I don't need to override _stash or _cleanup because they already handle
# the size information.

package Scrooge::Sub;
our @ISA = qw(Scrooge::Quantified);
use Carp;

=head2 Scrooge::Sub

The Scrooge::Sub class is the class that underlies the L</re_sub> pattern
constructor. This is a fairly simple class that inherits from
L</Scrooge::Quantified> and expects to have a C<subref> key supplied in the call
to its constructor. Scrooge::Sub overrides the following Scrooge methods:

=over

=item _init

The initialization method verifies that you did indeed provide a subroutine
under the C<subref> key. If you did not, you will get this error:

 Scrooge::Sub pattern [$name] requires a subroutine reference

or, if your pattern is not named,

 Scrooge::Sub pattern requires a subroutine reference

It also calls the initialization code for C<Scrooge::Quantified> to make sure
that the quantifiers are valid.

=cut

sub _init {
	my $self = shift;
	
	# Check that they actually supplied a subref:
	if (not exists $self->{subref} or ref($self->{subref}) ne ref(sub {})) {
		my $name = $self->get_bracketed_name_string;
		croak("Scrooge::Sub pattern$name requires a subroutine reference")
	}
	
	# Perform the quantifier initialization
	$self->SUPER::_init;
}

=item _apply

Scrooge::Sub's C<_apply> method that evaluates the supplied subroutine at the
left and right offsets of current interest. See the documentation for L</re_sub>
for details about the arguments passed to the subroutine and return values. In
particular, if you return any match details, they will be included in the saved
match details if your pattern is a named pattern (and if it's not a named
pattern, you can still return extra match details though there's no point).

=cut

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

=back

=cut

package Scrooge::ZWA;
our @ISA = ('Scrooge');
use Carp;

=head2 Scrooge::ZWA

Scrooge::ZWA is a base class for zero-width assertions. It is derived directly
from C<Scrooge>, not C<Scrooge::Quantified>. It provides the means to indicate
positions at which it should match, although you are not required to specify
match B<positions> to use this class.

This class overrides C<min_size> and C<max_size> to always return zero, since
that's what zero-width assertions do. It also overrides C<_prep> and C<_apply>
so that its basic behavior is sensible and useful. During the C<prep> stage,
if there is a C<position> key, it creates a subroutine cached under the key
C<zwa_position_subref> that evaluates the position assertion codified by the
one or two values asssociated with the C<position> key and returns boolean
values indicating matching or failing to match the position.

For a discussion of the strings allowed in positional asertions, see
L</re_zwa_position>.

=over

=item min_size, max_size

Scrooge::ZWA overrides min_size and max_size to both return zero.

=cut

sub min_size { 0 }
sub max_size { 0 }

=item _prep

Scrooge::ZWA provides a C<_prep> method that evaluates the value associated
with the C<position> key. If that value is a scalar then the exact positiion
indicated by that scalar must match. If that value is an
anonymous array with two values, the two values indicate a range of positions
at which the assertion can match. Either way, if there is such a
C<position> key with values as described, the C<_prep> method will create
an anonymous subroutine under the key C<zwa_position_subref> that accepts a
single argument and returns a true or false value indicating whether the
position is matched. If there is no such C<position> key, there will still
be a subroutine under C<zwa_position_subref>, but it will always return a
true value. Thus, if you derive a class from C<Scrooge::ZWA>, running
C<< $self->SUPER::_prep >> will ensure that C<< $self->{zwa_position_subref} >>
is a subroutine that will give you a meaningful evaluation for any given
(left) offset.

=cut

# Prepares the zero-width assertion; parses the position strings and constructs
# an anonymous subroutine that can be called against the current left/right
# position.
sub _prep {
	my $self = shift;
	
	# Create a position assertion that always matches if no position was
	# specified.
	if (not exists $self->{position}) {
		$self->{zwa_position_subref} = sub { 1 };
		return 1;
	}
	
	my $position = $self->{position};
	
	# Check if they specified an exact position
	if (ref($position) eq ref('scalar')) {
		my $match_offset = parse_position($self->{data}, $position);
		
		# Fail the prep if the position cannot match
		return 0 if $match_offset < 0
			or $match_offset > Scrooge::data_length($self->{data});
		
		# Set the match function:
		$self->{zwa_position_subref} = sub {
			return $_[0] == $match_offset;
		};
		return 1;
	}
	# Check if they specified a start and finish position
	if (ref($position) eq ref([])) {
		my ($left_string, $right_string) = @$position;
		
		# Parse the left and right offsets
		my $left_offset = parse_position($self->{data}, $left_string);
		my $right_offset = parse_position($self->{data}, $right_string);
		
		# If the left offset is to the right of the right offset, it can never
		# match so return a value of zero for the prep
		return 0 if $left_offset > $right_offset;
		
		# Otherwise, set up the position match function
		$self->{zwa_position_subref} = sub {
			return $left_offset <= $_[0] and $_[0] <= $right_offset;
		};
		return 1;
	}
	
	# They didn't specify anything, so match anywhere
	$self->{zwa_position_subref} = sub { 1 };
	return 1;
}

=item _apply

The default C<_apply> for Scrooge::ZWA simply applies the subroutine under
C<< $self->{zwa_position_subref} >>, which asserts the positional request
codified under the key C<position>. If there is no such key/value pair,
then any position matches.

=cut

sub _apply {
	my ($self, $left, $right) = @_;
	return '0 but true' if $self->{zwa_position_subref}->($left);
	return 0;
}

=back

Scrooge::ZWA also provides a useful utility for parsing positions:

=over

=item parse_position

C<Scrooge::ZWA::parse_position> takes a data container and a position string
and evaluates the position. The allowed strings are documented under
L</re_zwa_position>; the data container must be something that 
L</Scroge::data_length> knows how to handle.

=cut

# Parses a position string and return an offset for a given piece of data.
sub parse_position{
        my ($data, $position_string) = @_;
        
        # Get the max index in a cross-container form
        my $max_index = Scrooge::data_length($data);
        my $pct = $max_index/100;
        
        my $original_position_string = $position_string;
        
        # Keep track of truncation
        my $truncate_extreme = 0;
        $truncate_extreme = 1 if $position_string =~ s/^\[(.*)\]/$1/s;
        
        # Replace percentages with evaluatable expressions
        $position_string =~ s/(\d)\s*\%/$1 * \$pct/;
        
        # Evaluate the string
        my $position = eval($position_string);
        croak("parse_position had trouble with position_string $original_position_string")
                if $@ ne '';
        
        # handle negative offsets
        if ($position < 0) {
        	no warnings 'numeric';
        	$position += $max_index if $position == $position_string;
        }
        
        # Handle truncation
        $position = 0 if $position < 0 and $truncate_extreme;
        $position = $max_index if $position > $max_index and $truncate_extreme;
        
        # Round the result if it's not an integer
        return int($position + 0.5) if $position != int($position);
        # otherwise just return the position
        return $position;
}

=back

=cut

package Scrooge::ZWA::Sub;
our @ISA = ('Scrooge::ZWA');
use Carp;

=head2 Scrooge::ZWA::Sub

As Scrooge::Sub is to Scrooge::Quantified, so Scrooge::ZWA::Sub is to
Scrooge::ZWA. This class provides a means for overriding the C<_apply>
method of zero-width assertions by allowing you to provide an anonymous
subroutine reference that will be evaluated to determine if the zero-width
assertion should hold at the given position. It expects the subroutine to be
associated with the C<subref> key.

This class overrides the following methods:

=over

=item _init

The C<_init> method of Scrooge::ZWA::Sub ensures that you provided a
subroutine associated with the C<subref> key, and it calls Scrooge::ZWA::_init
as well, to handle the position key (if any).

=cut

sub _init {
	my $self = shift;
	
	# Verify the subref
	croak("Scrooge::ZWA::Sub requires a subroutine reference associated with key 'subref'")
		unless exists $self->{subref} and ref($self->{subref}) eq ref(sub{});
	
	$self->SUPER::_init;
}

=item _apply

The C<_apply> method of Scrooge::ZWA::Sub proceeds in two stages. First it
evaluates the positional subroutine, returning false if the position does
not match the position spec. Recall that the position subroutine will return
a true value if there was no position spec. At any rate, if the position
subroutine returns true, C<_apply> evaluates the subroutine under the 
C<subref> key, passing the routine C<$data, $left, $right> (though C<$right>
will always equal C<$left - 1>).

The subroutine associated with C<subref> must return a value that evaluates
to zero in numeric context, either the string C<'0 but true'> for a true value
or the numeric value 0. It can also return details as key/value pairs upon a
successful match.

=cut

sub _apply {
	my ($self, $left, $right) = @_;
	unless ($right < $left) {
		my $name = $self->get_bracketed_name_string;
		croak("Internal error in calling re_zwa pattern$name: $right is not "
			. "less that $left");
	}
	
	# Make sure the position matches the specification (and if they didn't
	# indicate a position, it will always match)
	return 0 unless $self->{zwa_position_subref}->($left);
	
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
		die("Zero-width assertion$name did not consume zero elements\n");
	}
	
	# Return the result:
	return ($consumed, %details);
}

=back

=cut

package Scrooge::Grouped;
our @ISA = qw(Scrooge);
use Carp;

=head2 Scrooge::Grouped

Scrooge::Grouped is an abstract base class for grouped patterns, patterns
whose primary purpose is to take a collection of patterns and apply them all
to a set of data in one way or another. The canonical grouped patters are
L</re_or>, L</re_and>, and L</re_seq>.

This class provides quite a bit of functionality shared between all grouping
classes. The big challenge for grouped patterns is ensuring that all stages
of the pattern process touch each pattern at the right time. This includes
the nitty-gritty of things like storing matches, unstoring (failed) matches,
stashing and unstashing values, and other things. This base class exists so
that you can (mostly) ignore these details.

Scrooge::Grouped is derived directly from Scrooge and provides methods for
the basic methods of C<_init>, C<_prep>, and C<_to_stash>, in addition to
some of the lower-level methods. It also utilizes many new group-specific
methods that only make sense in the context of gouped patterns, and which
can be overridden in derived classes. It is an abstract base class, however,
and derived classes must supply their own C<_apply> method.

Scrooge::Grouped checks that all of its patterns are derived from Scrooge at
construction time, so you canot create recursive patterns with code like this:

 my $recursive;
 $recursive = re_seq($something_else, $recursive);

This is considered to be a Good Thing (because getting the internals right
is Really Hard). However, it is possible to create recursive patterns by a
different means by using L</re_sub>.

The methods that Scrooge::Grouped overrides include:

=over

=item _init

This method provides basic verification of the input. In particular, it
verifies that the there is a C<patterns> key that holds an array of
patterns which are themselves derived from C<Scrooge>. It also adds all
named patterns to is collection of names and ensures that there are no name
conflicts between two unrelated patterns.

This method will croak for one of three reasons. If you do not provide a
pattern key or if the associated value is not an anonymous array, you will
get the error

 Grouped patterns must supply a key [patterns] with an array of patterns

If you supply an empty array, you will get the error 

 You must give me at least one pattern in your group

and if any of the elements in that array are not patterns, you will get this
error:

 Invalid pattern

=cut

sub _init {
	my $self = shift;
	croak("Grouped patterns must supply a key [patterns] with an array of patterns")
		unless exists $self->{patterns} and ref($self->{patterns}) eq ref([]);
	
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

=item add_name_to ($hashref)

This method is called by grouping methods on their enclosed patterns during
the initialization stage. If a grouping pattern is a child of a larger
grouping pattern, it needs to ensure that both its own name and its chilren's
names are added to the given hash, hence this overload.

=cut

# This is only called by patterns that *hold* this one, in the process of
# building their own name tables. Add this and all children to the hashref.
# Structures like ABA should pass this, but recursive structures will go
# into deep recursion.
# XXX recursive check this
sub add_name_to {
	my ($self, $hashref) = @_;
	# Go through each named value in this group's collection of names:
	while( my ($name, $ref) = each %{$self->{names}}) {
		croak("Found multiple patterns named $name")
			if defined $hashref->{$name} and $hashref->{$name} != $ref;
		
		$hashref->{$name} = $ref;
	}
}

=item _to_stash

In addition to the base class items that need to be stashed, this method
indicates that the keys C<patterns_to_apply> and C<positive_matches> are to
be stashed and unstashed.

=cut

# Some state information that will need to be stashed:
sub _to_stash {
	my $self = shift;
	return qw(patterns_to_apply positive_matches), $self->SUPER::_to_stash;
}

=item _prep

The C<_prep> method calls C<prep> on all the children patterns (via the
C<prep_all> method). The patterns that succeeded are associated with the key
C<patterns_to_apply> and success is determined by the result of the
C<_prep_success> method. The result of that last method will depend on the
sort of grouping pattern: 'or' patterns will consider it a successful prep
if any of the patterns were successful, but 'and' and 'sequence' patterns
will only be happy if all the patterns had successful preps. Of course, the
prep could still fail if the accumulated minimum size is larger than the
data's length. Otherwise, this method returns true.

=cut

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

=item _cleanup

The C<_cleanup> method is responsible for calling C<_cleanup> on B<all> the
patterns. The patterns can croak in their C<_cleanup> stage, if they think
that's a good idea: all such deaths will be captured and stored until all
patterns have had a chance to C<_cleanup>, at which point they will be
rethrown in agregate.

=cut

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

=item clear_stored_match

This calls the C<clear_stored_match> method on all the children that
reported successful matches, as well as this grouping pattern.

=cut

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

=item is_prepping, is_applying, is_cleaning

Each of these methods ensure that the base Scrooge method is called on the
current Grouping pattern and that the C<is_I<method>>s are called on all of
the children patterns. Note that these methods are called on B<all> the
patterns, whether or not they reported a successful C<_prep>.

=cut

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

=item get_details_for

This method overloads the base Scrooge method to check if this pattern or 
any children patterns have the requested name and returning the match
details for that pattern. (The base class just checks if the this pattern
has the requested name; it has no notion of children and, thus, no notion
of checking for them.)

The return values in scalar and list context are the same as for the base
L</get_details_for>.

=cut

sub get_details_for {
	my ($self, $name) = @_;
	# This is a user-level function. Croak if the name does not exist.
	croak("Unknown pattern name $name") unless exists $self->{names}->{$name};
	
	# Propogate the callin context:
	return ($self->{names}->{$name}->get_details) if wantarray;
	return $self->{names}->{$name}->get_details;
}

=back

In addition, Scrooge::Grouped provides many new overridable methods,
including:

=over

=item prep_all

The C<prep_all> method of Scrooge::Grouped calls the C<prep> method on each
sub-pattern, tracking the success or failure, as well as any exceptions. Even
if one of the pattern throws an exception, C<prep_all> continues C<prep>ing
the remainder of the patterns because they cannot have their C<_cleanup>
methods called if they have not already been C<prep>ed.

If there were no exceptions, C<prep_all> returns a list of patterns whose
C<_prep> methods returned true values. Even a successful C<prep> does not
guarantee that the pattern will be returned as successful: if the
successfully prepped pattern has a minimum size that consumes more data than
is available, it's a failed prep overall and cannot lead to a successful
match.

=cut

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

=item _prep_success

The C<_prep_success> method is an overridable method that is supposed to
analyze the contents of the C<patterns> and C<patterns_to_apply> keys to
determine if the the group's prep was successful. 'or' patterns will be happy
if there is at least one pattern to apply, but 'and' and 'seq' patterns will
want all of their patterns to have succeeded. The base-class behavior follows
the latter case and returns false unless there are as many patterns to apply
as their are patterns in the group.

=cut

# The default success happens when we plan to apply *all* the patterns
sub _prep_success {
	my $self = shift;
	return @{$self->{patterns}} == @{$self->{patterns_to_apply}};
}

=item push_match

Successful matches are tracked with a call to C<push_match>, which stores a
reference to the pattern in the array associated with C<positive_matches>,
and invokes the C<store_match> method on the pattern. This method expects
two arguments: the pattern object and a reference to a hash of match details.

Because the same grouping pattern can appear multiple times as part of a 
larger pattern, and because all such appearances share the same match stac,
it is critical that any and all patterns added with C<push_match> be tracked,
somehow, so that if something fails and they must be removed, corresponding
calls to C<pop_match> only pop off the matches associated with the matches
at the current appearance, and not with previous appearances of the pattern.

=cut

sub push_match {
	croak('Scrooge::Grouped::push_match is a method that expects two arguments')
		unless @_ == 3;
	my ($self, $pattern, $details) = @_;
	push @{$self->{positive_matches}}, $pattern;
	$pattern->store_match($details);
}

=item pop_match

The C<pop_match> method removes the most recent addition to the
C<positive_matches> stack and calls its C<clear_stored_match> method. This
only marks a bad match on a single pattern, not all the patterns on the
stack of C<positive_matches>.

=cut

# This should only be called when we know that something is on the
# positive_matches stack. recursive check this XXX
sub pop_match {
	my $self = shift;
	$self->{positive_matches}->[-1]->clear_stored_match;
	pop @{$self->{positive_matches}};
}

=back

Finally, this class has a couple of requirements for derived classes.
Classes that inherit from Scrooge::Grouped must implement these methods:

=over

=item _minmax

Scrooge::Grouped calls the method C<_minmax> during the C<prep> stage. This
method is supposed to calculate the grouping pattern's minimum and maximum
lengths and store them using the class setters
C<< $self->min_size($new_min) >> and C<< $self->max_size($new_max) >>. The
minimum match size for an Or group will be very different from the minimum
match size for a Sequence group, for example.

=item _apply

Scrooge::Grouped does not provide an C<_apply> method, so derived classes
must provide one of their own.

=back

=cut

package Scrooge::Or;
our @ISA = qw(Scrooge::Grouped);
use Carp;

=head2 Scrooge::Or

This is the class that provides the functionality behind L</re_or>. This
class defines a grouping pattern that looks for a successful match on any
of its patterns, consuming as many elements as the successfully matched
child pattern.

Scrooge::Or does not need to provide any new methods and simply overrides
methods from the parent classes. The overrides include 

=over

=item _minmax

For Or groups, the minimum possible match size is the smallest minimum
reported by all the children, and thel maximum possible match size is the
largest maximum reported by all the children.

=cut

# Called by the _prep method; sets the internal minimum and maximum match
# sizes.
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

=item _prep_success

Or groups consider a C<prep> to be successful if any one of is children
succeeds, which differs from the base class implementation in which all the
children are expected to succeed.

=cut

# Must override the default _prep_success method. If we have *any* patterns
# that will run, that is considered a success.
sub _prep_success {
	return @{$_[0]->{patterns_to_apply}} > 0;
}

=item _apply

The C<_apply> method of Scrooge::Or takes all the patterns that returned a
successful C<prep> and tries to match each of them in turn. Order matters in
so far as the successful match is the first match in the list that returns a
successful match. A pattern is tried on the full range of right offsets
before moving to the next pattern.

=cut

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

=item clear_stored_match

Scrooge::Or only stores a single matched pattern at a time, so it only needs
to clear the last match if its parent tells it to clear its stored match.

=cut

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

=back

=cut

package Scrooge::And;
our @ISA = qw(Scrooge::Grouped);
use Carp;

=head2 Scrooge::And

This class provides the functionality for matching all of its children
patterns at the exact same left and right offsets and underlies C</re_and>.
Most of the functionality provided by Scrooge::Grouped is sufficient, but
this class overrides two methods:

=over

=item _minmax

The minimum and maximum sizes reported by Scrooge::And must correspond with
the most restricted possible combination of options. If one child pattern
requires at least five elements and the next pattern requires at least ten
elements, the pattern can only match at least ten elements. Similarly, if
the one pattern can match no more than 20 elements and another can match no
more than 30, the two can only match at most 20 elements.

=cut

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

=item _apply

Applying Scrooge::And at a given left and right offsets involves applying
all the child patterns at the same left and right offsets and adjusting the
right offset until all of the child patterns match or one of them fails
outright.

This method can die for a couple of reasons. If any of the child patterns
die, it will reissue the error with the following message:

 In re_and pattern [$name], $ith pattern [$child-name] died:
 $error_message

This will also die if any of the child patterns try to consume more elements
than they were allowed to consume with this error message:

 In re_and pattern [$name], $ith pattern [$child_name] consumed $actual
 but it was only allowed to consume $allowed

=cut

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
			die "In re_and pattern$name, ${i}th pattern$child_name died:\n$@"; 
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
	return $consumed_length if $consumed_length > 0;
	return '0 but true';
}

=back

=cut

package Scrooge::Sequence;
our @ISA = qw(Scrooge::Grouped);
use Carp;

=head2 Scrooge::Sequence

The Scrooge::Sequence class provides the functionality for sequential
pattern matching, which is at the heart of greedy pattern matching. This
class overrides a handful of Scrooge::Grouped methods in order to perform its
work and adds one new private key: C<temp_matches>. The overridden methods
include:

=over

=item _init

The C<_init> method calls the Scrooge::Grouped initialization and sets the
C<temp_matches> key to an empty hash.

=cut

sub _init {
	my $self = shift;
	$self->SUPER::_init();
	$self->{temp_matches} = {};
}

=item _minmax

For a sequential pattern, the minimum possible match length is the sum of
the minimal lengths; the maximum possible match length is the sum of the
maximal lengths.

=cut

# Called by the _prep method, sets the internal minimum and maximum sizes:
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


=item _to_stash

Since Scrooge::Sequence uses the private key C<temp_matches>, it needs to
ensure that the is stashed, so it overrides C<_to_stash> to indicate the
additional key.

=cut

# make sure that temp_matches is stashed:
sub _to_stash {
	return 'temp_matches', $_[0]->SUPER::_to_stash;
}

=item _apply

Applying a sequential pattern involves matching all the children in order,
one after the other. Scrooge::Sequence achieves this by calling its own
C<seq_apply> method recursively on the list of patterns.

=cut

sub _apply {
	my ($self, $left, $right) = @_;
	return $self->seq_apply($left, $right, @{$self->{patterns_to_apply}});
}

=back

This class also creates a new function that handles the heavy lifting of the
match:

=over

=item seq_apply

This method provides the heavy lifting for the greedy sequential matching.
It takes a left offset, a right offset, and a list of patterns to apply
and operates recursively.

If there is only one pattern, the method evaluates the pattern for the
given left and right offsets and returns the number of consumed elements.
(It does not adjust the right offset if the child returns a negative offset;
it leaves any and all such adjustments for the caller to handle.)

If there are multiple patterns, the matching proceeds thus:

=over

=item 1.

The first pattern is shifted off the top of the list and applied at the
given left offset. The applied right offset starts with enough room so that
the remaining patterns can match within the alotted right offset passed into
the method.

=item 2.

Said applied right offset gets widdled down until the first pattern matches.

=item 3.

If the first pattern fails to match for any right offset, the method returns
a match failure.

=item 4.

If the first match succeeds, the remaining patterns are matched with
C<seq_apply> with a left offset that starts to the right of the first
pattern's match, and the given right offset.

=item 5.

If the remaining patterns return a negative number, it adjusts the right
offset and calls C<seq_apply> until the remaining patterns match (in which
case it returns a success with the number of matched elements) or fail
outright.

=item 6.

If the remaining patterns fail for the first pattern's current right offset,
this method goes back and reduces the first pattern's right offset until it
matches again, at which point it resumes with step 4.

=back

=cut

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

=back

=cut

# Role for situations involving more than one data set.
package Scrooge::Role::Subdata;
use Carp;

=head2 Scrooge::Role::Subdata

working here - doc more

Current limitation: all pattern objects *must* be distinct, or must be run
on the same data. The pattern will cache the first set of data that it gets
prepped with and will ignore any other prepped data sets. XXX

=cut

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
our @ISA = qw(Scrooge::Sequence);

*prep_all = \&Scrooge::Role::Subdata::prep_all;

sub _init {
	my $self = shift;
	$self->SUPER::_init;
	Scrooge::Role::Subdata::_verify($self);
}

package Scrooge::Subdata::And;
our @ISA = qw(Scrooge::And);

*prep_all = \&Scrooge::Role::Subdata::prep_all;

sub _init {
	my $self = shift;
	$self->SUPER::_init;
	Scrooge::Role::Subdata::_verify($self);
}

package Scrooge::Subdata::Or;
our @ISA = qw(Scrooge::Or);

*prep_all = \&Scrooge::Role::Subdata::prep_all;

sub _init {
	my $self = shift;
	$self->SUPER::_init;
	Scrooge::Role::Subdata::_verify($self);
}

# THE magic value that indicates this module compiled correctly:
1;

=head1 TODO

These are items that are very important or even critical to getting Scrooge to
operate properly.

=over

=item Testing: Multiple copies of the same pattern, nested calls to pattern

I have implemented a match stack to allow for multiple copies of the same
pattern within a larger pattern. I have also implemented a stashing and
unstashing mechanism to allow for patterns to be called from within other
patterns without breaking the original. This may, or may not, be tested. (This
comment was written a long time ago, and I may have written the tests for this
issue in the interim.)

=item Proper prep, cleanup, and stash handling on croak

I have added lots of code to handle untimely death at various stages of
execution of the pattern engine. I have furthermore added lots
of lines of explanation for nested and grouped patterns so that pin-pointing
the exact pattern is clearer. At this point, I need to ensure that these are
indeed tested.

=back

=head1 SEE ALSO

Interesting article on finding time series that "look like" other time
series:

http://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.133.6186&rep=rep1&type=pdf

For basics on Perl regular expressions, see L<perlretut>. For text parsing,
you should consider L<Regexp::Grammars>, L<Parse::RecDescent>, or the more
recent addition: L<Marpa::XS>.

=head1 AUTHORS

David Mertens C<dcmertens.perl@gmail.com>,
Jeff Giegold C<j.giegold@gmail.com>
