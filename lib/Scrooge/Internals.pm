=head1 PROPERTIES

Confession time: one of the most difficult aspects of Scrooge to implement was
robust caching. I figured it out, but it was harder than I had anticipated.
Cached calculations and match details are surprisingly easy to overwrite when
you just store them in the hash underlying C<$self>:

 $self->{some_value} = $self->calculate_something($self->data);

For this reason, Scrooge has a concept known as guarded properties and it
provides a handful of class meta-methods to make guarded properties easy to
implement in your Scrooge subclasses. After reading this section, you should be
able to use guarded methods that Just Work.

As far as Scrooge is concerned, there are two events against which you may wish
to guard your cached data. The pattern may be asked to match against multiple
sets of data within the same (larger) pattern, so precalculated results that
are specific to data should guard against switching of data. The pattern may
also cache partial match data, which should be guarded against mid-match
re-invocations. The quintesential example of this is a nested bracket
pattern (which makes little sense in the context of this engine, but bear with
me):

 my $bracketed;
 $bracketed = re_or (
   # Either a sequence of '(', bracketed_sequence, ')' ...
   re_seq (
     $opening_bracket,
     re_sub(
       my ($data, $left, $right) = @_;
       return $bracketed->apply($data->slice("$left:$right"));
     ),
     $closing_bracket,
   ),
   # ... or no brackets
   $no_brackets
 );

In this example, it may be that C<$opening_bracket> wishes to store some
information unique to each time it is called, and since C<$bracketed> is
invoked B<in the middle of the match>, C<$opening_bracket> needs some way to
make sure that its inner invocations do not overwrite internal data for outer
invocations. 

Some of your pattern's properties do not need to be guarded against either of 
these events. For example, a pattern's name or a sequence pattern's list of
sub-patterns never change, neither for changes in the data of interest nor the
invocation of the pattern. For these properties, you can create your own
accessor methods, or you can access the values directly as members of the
hash underlying C<$self>:

 print "Pattern ", $self->{name}, " encountered trouble: $message\n";
 # (Better to use the get_bracketed_name_string method than
 # to use $self->{name} directly, though).

If you property is either data- or invocation-specific, Scrooge provides a
meta-method that creates accessors for those properties and adds the
proper underlying machinery to protect those values when data is changed or the
pattern is invoked multiple times. The method, documented below, is illustrated
thus:

 __PACKAGE__->add_special_property('name_of_property', 'data', 'invocation');

You then set and retrieve those values using class methods of the same name:

 my $special_prop = $self->name_of_property;

The Scrooge base class comes with a handful of properties already, some
unguarded, some data-guarded, and some invocation-guarded.

=head2 name

The pattern's name is used when retrieving the match details and is not guarded.
It also should not be changed.

=head2 final_details

The final match details are associated with the C<final_details> key. It is not
guarded because it is never set until the pattern is finished.

=head2 min_size, max_size

For the Scrooge base-class, these are invocation-specific properties that
indicate the minimum and maximum number of elements that your pattern can
match. These are somewhat unusual in that some derived classes coerce these
into data-guarded properties while other derived classes ignore them completely
and provide their own C<min_size> and C<max_size> methods that return constant
values and do not operate as setters.

Note that at the moment, C<min_size> and C<max_size> are not querried in the
middle of the operation of the pattern, only at the beginning. In other
words, overriding these methods so that their return value changes throughout
the course of the pattern match (with a hope of reporting a more precise value,
perhaps) will not work.

=cut

our $has_to_stash = 1;
__PACKAGE__->add_special_property('min_size', 'invocation');
__PACKAGE__->add_special_property('max_size', 'invocation');

=head2 data

All Scrooge objects have the C<data> property, which is data-specific for obvious
reasons.

=cut

__PACKAGE__->add_special_property('data', 'data');

=head2 match_details

If a pattern is named, match results are accumulated onto the anonymous array
associated with the C<match_details> property. This is an invocation-guarded
property. You should not manipulate this directly. If you write a grouping
pattern, you should manipulate child patterns with L</store_match> and
L</clear_stored_match>, but only if L</Scrooge::Grouped> doesn't
provide what you need.

=cut

__PACKAGE__->add_special_property('match_details', 'invocation');

=head2 state

The pattern's state is an internal property. Whether it is guarded or not is
something of a grey area as its value is used to ensure that guarding works.
(At any rate, don't use this property name or you will very likely cause the
pattern internals to run amock.)

=head2 prep_result

This data-specific internal property is only used during the prep phase of the
pattern.

=head2 cache_key

This data-specific internal property is used to ensure that the accessor methods
for data-guarded properties actually retrieve the correct values. (It is, oddly
enough, invocation-guarded, not data-guarded, since it cannot be data-guarded.)

=cut

__PACKAGE__->add_special_property('cache_key', 'invocation');

=head2 add_special_property

This B<class> method performs all the necessary internal machinery to create
and manage an invocation- and/or data-guarded property. You invoke it in your
class definition. For example:

 package My::Pattern;
 our @ISA = qw( Scrooge );
 ...
 # Create a data-guarded property
 __PACKAGE__->add_special_property('my_data_property', 'data');
 # Create an invocation-guarded property
 __PACKAGE__->add_special_property('my_invocation_property', 'invocation');
 # Create a data-and-invocation-guarded property
 __PACKAGE__->add_special_property('my_both_property', 'data', 'invocation');
 ...

This will create an accessor method for you that you can safely invoke to
retrieve the value you need:

 sub _prep_data {
     my $self = shift;
     ...
     $self->my_data_property('new_value');
     ...
 }

To set these values before the pattern begins matching, you should overload the
C<_prep_invocation> and C<_prep_data> methods, described below. (XXX link those)
If your property is data-based and is protected against changes in the data, you
can only access it during C<_prep_data>, C<_apply>, and C<_cleanup>. If it is
only invocation-protected, you can access it at any point.

XXX Double-check that invocation-guarded handling properly invokes initialization
of data-and-invocation-guarded properties, 

XXX document the all_* accessor, for us in C<_cleanup>

=cut

sub add_special_property {
	my ($package, $prop_name, @options) = @_;
	
	# Make sure they provided at least one property descriptor
	croak("Special property must have a descriptor, either 'data' or 'invocation'")
		unless @options;
	
	# Make sure they used the right property descriptors
	croak("Special proerty options include only 'data' and 'invocation'")
		if @options != grep { /data/ or /invocation/ } @options;
	
	if (grep {/data/} @options) {
		__add_property_accessor($package, $prop_name, 1);
	}
	else {
		__add_property_accessor($package, $prop_name);
	}
	if (grep {/invocation/} @options) {
		__add_property_to_stash($package, $prop_name);
		__add_to_stash($package);
	}
}

#####
##### These are meta-methods, absolutely only for internal use
#####

sub __add_property_accessor {
	my ($package, $prop_name, $is_data_accessor) = @_;
	
	# Make this blank for object properties
	my $accessor_string = '';
	$accessor_string = '{$self->{cache_key}}' if $is_data_accessor;
	
	# Create this property's accessor method and add it to the to_stash list
	eval qq{
		package $package;
		sub $prop_name {
			my \$self = shift;
			
			# Return the data-specific value if called as a getter
			return \$self->{$prop_name}$accessor_string if \@_ == 0;
			
			# Set the data-specific value if called as a setter
			\$self->{$prop_name}$accessor_string = \$_[0];
		}
	};
	
	# add the appropriate all_ accessor
	if ($is_data_accessor) {
		eval qq{
			package $package;
			sub all_$prop_name {
				return values \%{ \$_[0]->{$prop_name} };
			}
		}
	}
	else {
		eval qq{
			package $package;
			sub all_$prop_name {
				return \$_[0]->{$prop_name};
			}
		}
	}
}

sub __add_property_to_stash {
	my ($package, $prop_name) = @_;
	eval qq{
		package $package;
		push our \@to_stash, '$prop_name';
	};
}

# Ensures that the _to_stash method is in the package
sub __add_to_stash {
	my $package = shift;
	eval qq{
		package $package;
		
		sub _to_stash {
			my \$self = shift;
			return our \@to_stash, \$self->SUPER::_to_stash;
		}
		
		our \$has_to_stash = 1;
	} unless eval '$' . $package . '::has_to_stash';
}

#####
##### End meta-methods
#####

=head2 coerce_as_data_property

Performs the necessary internal machinery to esure that an B<inherited>
invocation-guarded property is also guarded against data changes:

 __PACKAGE__->coerce_as_data_property('property_name');

=cut

sub coerce_as_data_property {
	my ($package, $prop_name) = @_;
	__add_property_accessor($package, $prop_name, 1);
}

# Scrooge's base class method; the installed to_stash method also invokes
# the parent's _to_return method, which doesn't exist for the base class.
sub _to_stash {
	return our @to_return;
}

=head2 Example

 package My::Scrooge::Subclass;
 
 __PACKAGE__->add_special_property('foo', 'invocation')
 __PACKAGE__->add_special_property('file_handle', 'data')
 
 # Set object-specific values in _init
 sub _init {
     ...
     # Keep track of the number of nesting levels:
     $self->{nesting_levels} = 0;
     ...
 }
 
 # Set invocation-specific values in _prep_invocation
 sub _prep_invocation {
     ...
     # Count the number of times this is invoked:
     $self->{nesting_levels}++;
     
     # Set the initial value for foo:
     $self->foo([]);
     ...
 }
 
 # Set data-specific values in _prep_data
 sub _prep_data {
     ...
     open my $new_fh, '<', $file_name;
     $self->file_handle($new_fh);
     ...
 }
 
 # Retrieve any values in _apply
 sub _apply {
     ...
     my $length = $self->length;
     my $fh = $self->file_handle;
     push @{$self->foo}, some_thing($self);
     ...
 }
 
 # During cleanup, the all_ accessors may be useful
 sub _cleanup {
     my @file_handles = $self->all_file_handle;
     close $_ foreach @file_handles;
 }


=head1 AUTHOR METHODS

This section documents the basic class structure of Scrooge for those interested
in writing pattern classes. If your goal is to simply build and apply patterns
to data then this section is not for you.

Scrooge provides a number of methods that you as a class author
will likely want to use or override. Some of what follows are explicitly meant
to be overridden; others are explicitly not meant to be overridden. In general,
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
sub _init { }

=head2 add_data ($data)

This method is a low-level method that helps prepare the data-guarded
properties. It stores the data under a data-specific cache key, sets the
pattern's current cache key as the just-computed cache key, and returns said
cache key. 

If you are writing a grouping or other container class, you should call this
method with the data that the pattern is to analyze just before invoking the
pattern's C<prep> method.

=cut

sub add_data {
	my ($self, $data) = @_;
	my $cache_key = Scalar::Util::refaddr($_[1]);
	$self->cache_key($cache_key);
	$self->data($data);
	return $cache_key;
}

=head2 _prep

XXX document _prep_data, _prep_invocation

The very last stage of C<prep> is calling this method, C<_prep>, whose name
differs from C<prep> only in the presence of the leading underscore. As a class
author, you should override this method. This function is called before the
pattern hammers on the data. If you have any data-specific setup to do with
data-guarded properties, do it in this function. You should perform as much
pre-calculation and preparation as possible in this code so as to minimize
repeated calculations in your C<_apply> method. This method should return
either 1 or 0 indicating that it either has or does not have a chance of
matching the data.

This method will be called once for each set of data that is being matched
against your pattern. That is, if you use something like L</re_named_seq> and
associate two different tags with your pattern, for example, this method will
be called twice. (Actually, they will be called twice if the data sets
associated with those tags are distinct.)

You can retrieve that data for calculations with the L</data> accessor method:

 my $min_value = $self->data->min;

Having examined the data, if you know that this pattern will not match 
you should return zero. This guarantees that the following functions
will not be called on your pattern during this run with this data: C<_apply>, 
C<_min_size>, C<_max_size>, and C<_store_match>. Put a little bit
differently, it is safe for any of those functions to assume that C<_prep>
has been called and was able to set up data-guarded properties that might be
required for their operation because they won't be called if C<_prep> returned
zero. Furthermore, if you realize in the middle of C<_prep>
that your pattern cannot run, it is safe to return 0 immediately and expect
the parent pattern to call C<_cleanup> for you. (working here - make sure the
documentation for Scrooge::Grouped details what Grouped patterns are supposed to
do with C<_prep> return values. XXX)

Your pattern may still be querried afterwards for a match by
C<get_details_for> or C<get_details>, regardless of the return value of
C<_prep>. In both of those cases, returning the undefined value,
indicating a failed match, would be the proper thing to do.

=cut

sub _prep_invocation {
	my $self = shift;
	
	# Associate the match details with an anonymous array
	$self->match_details([]);
	
	return 1;
}

# Default _prep_data simply returns true, meaning a successful prep:
sub _prep_data { return 1 }

=head2 _to_stash

XXX - put this somewhere else

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

=head2 _apply ($left, $right)

XXX - double-check these docs

This method is called when it comes time to apply the pattern to see if it
matches at the current left and right offsets on this data, which are the three
arguments supplied to the method.

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

=head2 _cleanup

The overridable method C<_cleanup> allows you to clean up any resources at the
end of a match. Apart from stash management by grouping patterns (which have to
call C<cleanup> on their sub-patterns), I have not yet used C<_cleanup> in my
patterns. However, it is conceivable that you might want to allocate some
resource in the C<prep> stage, and then unallocate that resource at the end of
of the match. In that case, this overridable method is precisely what you will
want to use.

C<cleanup> (and therefore C<_cleanup>) should only be called once, even if 
C<_prep> was called multiple times (for multiple data sets. However, it may in
fact be called more than once and your code needs to be flexible enough to
accomodate multiple calls to C<_cleanup> without dying.

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

This method sets up the internal state of the pattern just before
L<prep|/prep ($data)> gets called. This method is also responsible for ensuring
that the pattern is in a good state to be prepared and will croak if you are
trying to use it in some invalid way. If you somehow manage to use a pattern
within its own prep or cleanup code, you will get one of these errors:

 Pattern [name] uses itself in prep code, which is not allowed
 Pattern [name] uses itself in cleanup code, which is not allowed

=cut

# The first phase. Back up the old state and clear the current state. The
# state is required to be 'not running' before the pattern starts, and it
# is required to have a defined value during all three user-directable
# phases.
sub is_prepping {
	croak('Scrooge::is_prepping is a method that takes no arguments')
		unless @_ == 1;
	my $self = shift;
	if (my $state = delete $self->{state}) {
		push @{$self->{old_state}}, $state;

		# A pattern can only move into the prep state if it is 'not running' or in
		# the middle of 'apply'. We die *before* having modified the state because
		# cleanup only restores if the old state is 'apply'
		my $name = $self->get_bracketed_name_string;
		croak("Pattern$name uses itself in cleanup code, which is not allowed")
			if $state eq 'cleaning';
		croak("Pattern$name uses itself in prep code, which is not allowed")
			if $state eq 'prepping';
		croak("Internal error: Pattern$name managed to get to is_prepping with an unknown state")
			if $state ne 'not running' and $state ne 'apply';
	}
}

=head2 prep

This method is neither user-level nor overridable. It is called as the first
stage of C<apply>. This method ensures that C<_prep_data> gets called once for
each set of data, and that C<_prep_invocation> gets called once per invocation.
As a class author, you should overload C<_prep_data> C<_prep_invocation> to
control how your class prepares for being matched.

=cut

sub prep_invocation {
	croak('Scrooge::prep_invocation takes no argument') unless @_ == 1;
	my $self = shift;
	
	# Make sure this only gets run once per invocation, and that if it was
	# already run on this data, the previous return value is again returned:
	return $self->{prep_result}{invocation}
		if exists $self->{prep_result}{invocation};
	
	# Indicate the change of state and stash old values, if appropriate
	$self->{state} = 'prepping';
	if ($self->{old_state}->[-1] eq 'apply') {
		push @{$self->{"old_$_"}}, $self->{$_} foreach $self->_to_stash;
	}
	
	# Once-per-invocation preparation
	return $self->{prep_result}{invocation} = $self->_prep_invocation;
}

sub prep_data {
	croak('Scrooge::prep takes no argument') unless @_ == 1;
	my $self = shift;
	
	# Handle a bad invocation prep, in which case data-specific prep should
	# not happen.
	return 0 if $self->{prep_result}{invocation} == 0;
	
	# We'll need the cache key for the rest of this.
	my $cache_key = $self->cache_key;
	
	# Make sure this only gets run once per dataset per call to apply, and that
	# if it was already run on this data, the previous return value is again
	# returned:
	return $self->{prep_result}{$cache_key}
		if exists $self->{prep_result}{$cache_key};
	
	# Return the result of the prep:
	return $self->{prep_result}{$cache_key} = $self->_prep_data;
}

=head2 is_applying

This is a setter method that changes the internal state of the pattern just
before L</_apply> gets called.

=cut

sub is_applying {
	my $self = shift;
	delete $self->{prep_result};
	$self->{state} = 'apply';
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
	push @{$self->match_details}, $details;
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
	pop @{$self->match_details};
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
	delete $_[0]->{prep_result};
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
	$self->{final_details} = $self->match_details;
	
	# Call sub-class's cleanup method:
	eval { $self->_cleanup() };
	my $err_string = $@;
	
	# ALWAYS unstash the previous state, which is always guaranteed to have
	# a meaningful value:
	$self->{state} = pop @{$self->{old_state}};
	
	# Unstash everything if the match was previously applying itself
	if ($self->{state} eq 'apply') {
		$self->{$_} = pop @{$self->{"old_$_"}} foreach $self->_to_stash;
	}
	
	# Finally, check the error state from the sub-class's cleanup:
	die $err_string if $err_string ne '';
}
