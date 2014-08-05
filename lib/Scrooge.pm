use strict;
use warnings;

package Scrooge;
use Carp;
use Scrooge::Internals;
use Exporter;
#use PDL;
use Scalar::Util;

# Fow now, just pull all of these in manually.

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
a pattern on a list of key/value pairs (or an anonymous hash) in which the keys
are the names of the different data sets and the values are the actual data sets,
the things you'd normally send to C<apply>.

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

=head2 match ($data)

This method applies the pattern object on the given container. In list
context this returns a whole host of key/value pairs with information about
the match, or an empty list on failure. In scalar context this returns the
number of elements matched (including the magical string "0 but true" if
it matches zero elements), or undef on failure. In boolean context, it
return true if the match succeeded, or false if it failed.

For example, the following three expressions all Do Something when your
pattern matches, and do not Do Something when it fails:

 if (my %match_info = $pattern->match($data)) {
     # Do Something
 }
 
 if (my $amount_matched = $pattern->match($data)) {
     # Do Something 
 }
 
 if ($pattern->match($data)) {
     # Do Something
 }
 
Perl lets you use the returned matched length---even the string---in
arithmetic operations without issuing a warning. (Perl normally issues a
warning when you try to do arithmetic with a string, but it grants an
exception for the string "0 but true".) However, if you plan on
printing the matched length, you should assure a numeric value with either of
these two approaches:

 if (my $matched = $pattern->match($data)) {
     $matched += 0; # ensure $matched is numeric
     print "Matched $matched elements\n";
 }

or

 if (my %match_info = $pattern->match($data)) {
     print "Matched $match_info->{length} elements\n";
 }



This method can croak for a few reasons. If any of the patterns croak
during the preparation or matching stage, C<match> will do its best to
package the error message in a useful way and rethrow the error. Also, if
you are trying to use a data container for which Scrooge does not know how
to compute the length, C<match> will die saying as much. (See L</data_length>
to learn how to teach Scrooge about your data container.)

=cut

# User-level method, not to be overridden.
sub match {
	my $self = shift;
	my $data;
	if (@_ == 1) {
		$data = shift;
	}
	elsif (@_ % 2 == 0) {
		$data = {@_};
	}
	else {
		croak('Scrooge::match expects either a data argument or key/value data pairs');
	}
	
	# Get the data's length and verify that the container is a known type
	my $N = data_length($data);
	croak('Could not get length of the supplied data')
		if not defined $N or $N eq '';
	
	# Create the match info hash with some basic info already set:
	my %match_info = (
		data => $data, min_size => 1, max_size => $N, data_length => $N
	);
	
	# Prepare the pattern for execution. This may involve computing low and
	# high quantifier limits, keeping track of $data, stashing
	# intermediate data if this is a nested pattern, and many other things.
	# The actual prep method can fail, so look out for that.
	my (@croak_messages, $prep_results);
	eval {
		$prep_results = $self->prep(\%match_info);
		1;
	} or push @croak_messages, $@;
	unless ($prep_results) {
		eval { $self->cleanup(\%match_info) };
		push @croak_messages, $@ if $@ ne '';
		
		# Croak if there was an exception during prep or cleanup:
		if (@croak_messages) {
			die "Pattern encountered trouble:\n" . 
				join("\n !!!! and !!!!\n", @croak_messages);
		}
		
		# Otherwise, just return an empty match:
		return;
	}
	
	my $min_diff = $match_info{min_size} - 1;
	my $max_diff = $match_info{max_size} - 1;

	# Left and right offsets, maximal right offset, and number of consumed
	# elements:
	my ($l_off, $r_off, $consumed, %details);
	
	# Wrap all of this in an eval block to make sure croaks and other deaths
	# do not prevent cleanup:
	eval {
		# Run through all sensible left and right offsets. If the min size
		# is zero, it IS POSSIBLE for $l_off to equal $N. This would be the
		# case for a zero-width-assertion that is supposed to match at the
		# end of the data, for example.
		START: for ($l_off = 0; $l_off < $N - $min_diff; $l_off++) {
			# Start with the maximal possible r_off:
			$r_off = $l_off + $max_diff;
			$r_off = $N-1 if $r_off >= $N;
			
			$match_info{left} = $l_off;
			
			STOP: while ($r_off >= $l_off + $min_diff) {
				$match_info{right} = $r_off;
				$match_info{length} = $r_off - $l_off + 1
					|| '0 but true';
				
				$consumed = $self->apply(\%match_info);
				my $allowed_length = $r_off - $l_off + 1;
				if ($consumed > $allowed_length) {
					my $class = ref($self);
					my $name = $self->get_bracketed_name_string;
					croak("Internal error: pattern$name of class <$class> consumed $consumed,\n"
						. "but it was only allowed to consume $allowed_length");
				}
				# If they returned less than zero, adjust r_off and try again:
				if ($consumed < 0) {
					# Note that negative values of $consumed that are "too
					# large" do not cause the engine to croak, or even carp.
					$r_off += $consumed;
					next STOP;
				}
				# We're done if we got a successful match
				last START if $consumed and $consumed >= 0;
				# Move to the next starting position if the match at this
				# position failed:
				last STOP if $consumed == 0;
			}
		}
	};
	# Back-up $@:
	push @croak_messages, $@ if $@ ne '';
	
	# Run cleanup, backing up any error messages:
	eval { $self->cleanup(\%match_info) };
	push @croak_messages, $@ if $@ ne '';
	
	# Croak if there was an exception during prep or cleanup:
	if (@croak_messages) {
		die "Pattern encountered trouble:\n" . 
			join("\n !!!! and !!!!\n", @croak_messages);
	}
	
	# If we were successful, return the details:
	if ($consumed and $consumed >= 0) {
		return $consumed unless wantarray;
		# Make sure we update the length and right offset to reflect the
		# final match condition
		$match_info{length} = $consumed + 0;
		$match_info{right} = $match_info{left} + $consumed - 1;
		return %match_info;
	}
	# Otherwise return an empty list:
	return;
}

# THE magic value that indicates this module compiled correctly:
1;

=head1 TODO

These are items that I want to do before putting this library on CPAN.

=over

=item Tutorial

I've started Scrooge::Tutorial but not finished it.

=item Clean up cross-references

I have many broken links and cross-references that need to be fixed. These
include references to methods without providing a link to the method's
documentation.

=item Change re_named_or to re_tagged_or, re_* to pat_*

Referring to tagging instead of naming provides a distinguishing term rather
than overloading the already overused term "name". Also, the notion of these
as regular expressions was deprecated a while ago but the prefix remains.
That should be fixed.

=item Repeated patterns

I need to make a pattern that takes a single child pattern and lets you 
repeat it a specified number of times, probably called re_repeat

=item Explore recursive patterns

Recursion can be achieved by having an re_sub call itself. This should
work as-is thanks to all the stash management. I need to explore this in a
tutorial and test it.

=item Proper prep, cleanup, and stash handling on croak

I have added lots of code to handle untimely death at various stages of
execution of the pattern engine. I have furthermore added lots
of lines of explanation for nested and grouped patterns so that pin-pointing
the exact pattern is clearer. At this point, I need to ensure that these are
indeed tested.

=item remove MSER for the moment

I'll add this back, but it ought not be in the distribution for the first
CPAN release.

=back

These are things I want to do after the first CPAN release:

=over

=item Add MSER back

After the first CPAN release, I want to add the MSER analysis back.

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
