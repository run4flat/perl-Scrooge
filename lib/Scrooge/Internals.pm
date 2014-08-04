use strict;
use warnings;

package Scrooge;

=head1 PROPERTIES

Confession time: one of the most difficult aspects of Scrooge to implement was
robust caching. I figured it out, but it was harder than I had anticipated.
Cached calculations and match details are surprisingly easy to overwrite when
you just store them in the hash underlying C<$self>:

 $self->{some_value} = $self->calculate_something($self->data);

After a long struggle, and then a good while off, I realized that I could
achieve what I wanted by using Perl's stack, coupled with a simple lexically
scoped hashref. The hashref is specific to the set of data you're working
with, so you are safe to assume that any values in the hashref have been
computed specifically with respect to your current data. This has
substantially reduced the number of lines as well as the complexity of the
code involved in this implementation.

=head1 AUTHOR METHODS

This section documents the basic class structure of Scrooge for those interested
in writing pattern classes. If your goal is to simply build and apply patterns
to data then this section is not for you.

Scrooge provides a number of methods that you as a class author
will likely want to use or override. Some of what follows are explicitly meant
to be overridden; others are explicitly not meant to be overridden. Your best
guide to know which is which is to check the documentation. :-)

=head2 init ($self)

This overrideable method is invoked during the construction of the pattern.
The object is hash-based and contains whichever key/value pairs were sent to
the C<new> class method. This method is meant to be overloaded by derived
classes and should do whatever constructor initialization stuff needs to
happen.

Remember that at this stage, you do not have access to the data that you will
match. That comes later. This stage should primarily focus on argument
validation and initialization. Once your C<init> code has finished, your
object should be ready to have its C<prep> method invoked.

=cut

# Default init does nothing:
sub init { }

=head2 prep ($self, $match_info)

This overrideable method is the first step of the pattern matching process,
called just before the pattern hammers on the data. If you have any
data-specific setup to do, do it in this function, storing any intermediate
results or calculations in the C<$match_info> hashref. You should perform as
much pre-calculation and preparation as possible in this code so as to minimize
repeated calculations in your C<apply> method. This method should return
either 1 or 0 indicating that it either has or does not have a chance of
matching the data.

This method will be called once for each set of data that is being matched
against your pattern. That is, if you use something like L</re_named_seq> and
associate two different tags with your pattern, for example, this method will
be called twice.

The C<$match_info> hashref comes pre-populated with the following keys:

=over

=item data

the data to match

=item min_size

the default minimum match size, which is 1 (and which you should override
if you have reason to do so)

=item max_size

the default maximum match size, which is the length of the data (and which
you should override if you have reason to do so)

=item length

the length of the data

=back

Having examined the data, if you know that this pattern will not match 
you should return zero. This guarantees that the C<apply> function will not
be called on your pattern during this run with this data. Put a little bit
differently, it is safe for C<apply> to assume that C<prep> has been called
and was able to set up properties in C<$match_info> that might be required
for its operation because it won't be called if C<prep> returned zero.
Furthermore, if you realize in the middle of C<prep> that your pattern
cannot run, it is safe to return 0 immediately and expect the parent pattern
to call C<cleanup> for you.

(working here - make sure the documentation for Scrooge::Grouped details
what Grouped patterns are supposed to do with C<prep> return values. XXX)

Your pattern may still be querried afterwards for a match by
C<get_details_for> or C<get_details>, regardless of the return value of
C<prep>. In both of those cases, returning the undefined value,
indicating a failed match, would be the proper thing to do.

=cut

# Default prep simply returns true, meaning a successful prep:
sub prep { return 1 }

=head2 apply ($self, $match_info)

This method is called when it comes time to apply the pattern to see if it
matches the data. The match info will be the same hashref that was passed
to the C<prep> method; in addition, the C<left> and C<right> keys will have
the left and right offsets to test. This function will be called repeatedly
over the course of the match process until all possible combinations of left
and right have been checked.

NOTE that the default behavior is to match at least one element. If your
pattern indicates that it can match zero elements, then the left offset can
be EQUAL TO the length of the data, and right offset can be as small as -1.
If you are writing a zero-width assertion, you should not blithely use the
values of left and right.

If your pattern encloses another, it should call the enclosed pattern's C<apply>
method and take its return value into consideration with its own, unless
it returned 0 when you called C<prep>. In that case, you should not call it.

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
key/value pairs returned by C<apply>, the left and right offsets of the match
are stored under the keys C<left> and C<right>.

=head2 cleanup ($self, $match_info)

The overridable method C<cleanup> allows you to declutter the C<$match_info>
hashref and clean up any resources at the end of a match. For example, during
the C<prep> stage, some of Scrooge's patterns actually construct small,
optimized subrefs that get called by reference during the match process.
These subrefs get removed during C<cleanup> so they do not show up in the
final, returned hash.

C<cleanup> may be called many times, so be sure your code does not cause
trouble on multiple invocations. (Note that deleting non-existent keys from
a Perl hash is just fine, because Perl is cool like that.)

=cut

# Default _cleanup does nothing
sub cleanup { }

=head1 DEEP METHODS

These are methods that the general Scrooge subclass writer won't need, but are
still needed sometimes.

=head2 new ($class, %args)

The role of the constructor is to create a blessed hash with any internal
data representations. This method name does not begin with an underscore, which
means that class authors should not override it. It is also a bit odd: typically
it is neither invoked by the user nor overridden by class authors. In general, a
class author supplies a short-form constructor that invokes C<new>, which
prepares a few bits and pieces of the internal state before calling L</init>. If
you need to override initialization, you should override L</init>.

This method croaks if, after the class name, there is not an even number of 
remaining arguments since it blesses the hash of key/value pairs into the
supplied class.

The basic chain is user-level-constructor -> C<new> -> C<init>. The resulting
object at the end of this chaing must be capable of running its C<prep> method.

=cut

sub new {
	my $class = shift;
	croak("Internal Error: args to Scrooge::new must have a class name and then key/value pairs")
		unless @_ % 2 == 0;
	my $self = bless {@_}, $class;
	
	# Initialize the class:
	$self->init;
	
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

1;
