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

our @EXPORT = qw(re_or re_and re_seq re_sub re_any re_zwa);

=head1 NAME

Scrooge - a greedy regular expression engine for arbitrary objects, like PDLs

=cut

our $VERSION = 0.01;

=head1 VERSION

This documentation is supposed to be for version 0.01 of Scrooge.

=head1 SYNOPSIS

 use Scrooge;
 
 # Build the regular expression object first. This one
 # matches positive values and assumes it is working with
 # piddles.
 my $positive_re = re_sub(sub {
     # Supplied args (for re_sub, specifically) are the
     # object (in this case assumed to be a piddle), the
     # left slice offset, and the right slice offset:
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
 
 # ... after you've built a few regexes ...
 
 # Matches regex a, b, or c:
 my ($matched, $offset)
     = re_or( $re_a, $re_b, $re_c )->apply($data);
 
 # Matches regex a, b, and c:
 my ($matched, $offset)
     = re_and ( $re_a, $re_b, $re_c )->apply($data);
 
 # Matches first, then second, then anything, then third
 my ($matched, $offset)
     = re_seq ( $re_first, $re_second, re_any, $re_third);

=head1 DESCRIPTION

Scrooge creates a set of classes that let you construct numerical regular
expression objects that you can apply to a container object such as an anonymous
array, or a piddle. Because the patterns against which you might match are
limitless, this module provides a means for easily creating your own conditions
and the glue necessary to put them together in complex ways. It does not offer a
concise syntax, but it provides the back-end machinery to support such a concise
syntax for various data containers and applications.

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
construct. Here is how to build a numerical regular expression that checks
for a positive number followed by a local maximum, or a negative number
followed by a local minimum. I'll assume that the individual regular expression
pieces (i.e. C<$positive_re>) already exist.

 my $regex = re_or(
     re_seq( $positive_re, $local_max_re ),
     re_seq( $negative_re, $local_min_re )
 );

=head1 Examples

Here is a regular expression that checks for a value that is positive and
which is a local maximum, but which is flanked by at least one negative
number on both sides. All of these assume that the data container is a piddle.

 my $is_local_max = re_sub( [1,1],  # quantifiers, exactly one
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
 my $regex = re_seq(
     $is_negative, $is_local_max, $is_negative
 );
 
 # Match it against some data:
 if ($regex->apply($data)) {
     # Do something
 }

=head1 METHODS

These are the user-level methods that each regex provides. Note that this
section does not discuss subclassing or constructors; those are discussed below.
In other words, if you have regex objects and you want to use them this is the
public API that you can use.

=over

=item apply ($data)

This method applies the regular expression object on the given container. The
return value is a bit complicated to explain, but in general it Does What You
Mean. In boolean context, it returns a truth value indicating whether the regex
matched or not. In scalar context, it returns a scalar indicating the number of
elements that matched if something matched, and undef otherwise. In particular,
if the regex matched zero elements, it returns the string "0 but true", which
evaluates to zero in numeric context, but true in boolean context. Finally, in
list context, if the regex fails you get an empty list, and if it succeeds you
get two numbers indicating the number of matched elements and the offset
(without any of that zero-but-true business to worry about).

To put it all together, the following three expressions all Do Something when
your regex mathces:

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
arithmetic operations without issuing a warning. (Perl normally issues a
warning when you try to do arithmetic with a string, but it grants an
exception for the string "0 but true".) However, if you plan on
printing the matched length, you should assure a numeric value with either of
these two approaches:

 if (my $matched = $regex->apply($data)) {
     $matched += 0; # ensure $matched is numeric
     print "Matched $matched elements\n";
 }

or

 if (my ($matched) = $regex->apply($data)) {
     print "Matched $matched elements\n";
 }

Note that if your regex matches, you will get the empty list, so, if this fails:

 my ($matched, $offset) = $regex->apply($data);

both C<$matched> and C<$offset> will be the undefined value, and if you use
the expression in the conditional as in the first example above, the
condition will evaluate to boolean false. The only major gotcha in this
regard is that Perl's list flatting means this will B<NOT> do what you think it
is supposed to do:

 my ($first_matched, $first_off, $second_matched, $second_off)
     = ($regex1->apply($data), $regex2->apply($data));

If C<$regex1> fails to match and C<$regex2> succeeds, the values for the
second regex will be stored in C<$first_matched> and C<$first_off>. So, do
not use the return values from a regular expression in a large list
assignment like this.

working here - discuss known types and how unknown types throw errors (or should
they silently fail instead? I think not.)

If you only want to know where a sub-regex matches, you can name that sub-regex
and retrieve sub-match results using C<get_offsets_for>, as discussed below.

=cut

# User-level method, not to be overridden.
our %method_table;
sub apply {
	croak('Scrooge::apply is a one-argument method')
		unless @_ == 2;
	my ($self, $data) = @_;
	
	# Prepare the regex for execution. This may involve computing low and
	# high quantifier limits, keeping track of $data, stashing
	# intermediate data if this is a nested regex, and many other things.
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
			die "Regex encountered trouble:\n" . 
				join("\n !!!! and !!!!\n", @croak_messages);
		}
		
		# Otherwise, just return an empty match:
		return;
	}
	
	# Note change in local state:
	$self->is_applying;
	
	# Get the data's length
	my $N = data_length($data);
	croak("Could not get length of the supplied data") if $N eq '';
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
					croak("Internal error: regex$name of class <$class> consumed $consumed,\n"
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
		die "Regex encountered trouble:\n" . 
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

After running a successful regex, you can use this method to query the match
details for named regexes. This method returns an anonymous hash containing
the left and right offsets along with any other details that the regex
decided to return to you. (For example, a regex could return the average
value of the matched data since that information might be useful, and it
was part of the calculation.)

Actually, you can have the same regex appear multiple times within a larger
regular expression. In that case, the return value will be a list of hashes,
each of which contains the pertinent details. So if this named regex appears
five times but only matches twice, you will get a list of two hashes with
the details.

The returned results also depend upon the calling context. If you ask for
the match details in scalar context, only the first such hash will be
returned, or undef if there were no matches. In list context, you get a list
of all the hashes, or an empty list of there were not matches. As such, the
following expressions Do What You Mean:

 if (my @details = $regex->get_details_for('constant')) {
     for my $match_details (@details) {
         # unpack the left and right boundaries of the match:
         my %match_hash = %$match_details;
         my ($left, $right) = @match_details{'left', 'right'};
         # ...
     }
 }
 
 for my $details ($regex->get_details_for('constant')) {
     print "Found a constant region between $details->{left} "
		. "and $details->{right} with average value "
		. "$details->{average}\n";
 }
 
 if (my $first_details = $regex->get_details_for('constant')) {
     print "The first constant region had an average of "
		. "$details->{average}\n";
 }

Note that for zero-width matches that succeed, the value of right will be one
less than the value of left.

Finally, note that you can call this method on container regexes such as
C<re_and>, C<re_or>, and C<re_seq> to get the information for named sub-regexes
within the containers.

=cut

sub get_details_for {
	croak('Scrooge::get_details_for is a one-argument method')
		unless @_ == 2;
	my ($self, $name) = @_;
	
	# Croak if this regex is not named:
	croak("This regex was not told to capture anything!")
		unless defined $self->{name};
	
	# Croak if this regex has a different name (shouldn't happen, but let's
	# be gentle to our users):
	croak("This regex is named $self->{name}, not $name.")
		unless $self->{name} eq $name;
	
	# Be sure to propogate calling context. Note that these return an empty
	# list or an undefined value in their respective contexts if not items
	# matched 
	return ($self->get_details) if wantarray;	# list context
	return $self->get_details;					# scalar context
}

=item get_details

Returns the match details for the current regex, as described under
C<get_details_for>. The difference between this method and the previous one is
that (1) if this regex was not named, it simply returns the undefined value
rather than croaking and (2) this method will not search sub-regexes for
container regexes such as C<re_and>, C<re_or>, and C<re_seq> since it has no
name with which to search.

=cut

# This returns the details stored by this regex. Note that this does not
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
performance of your regex.

Here is a rundown of what to return when:

=over

=item More than the Full Length

You should never return more than the full length, and if you do, the regex
engine will croak saying

 Internal error: regex of class <class> consumed more than it was given

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
numerical regular expressions, this could be a condition on the slope between
two values, or a threshold crossing between two values, for instance. In those
cases, your regex does not match either of the values, but it matches in-between
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

You might ask, why not just B<evaluate> the condition at the lesser value? The
reason to avoid this is because this regex may be part of a combined C<re_or>
regex, for example. You might have a regex such as C<re_or ($first, $second)>.
Suppose C<$first> fails at C<$right> but will succeed at C<$right - 1>, and
C<$second> fails at C<$right> but will succeed at C<$right - 2>. It would be
inefficient for C<$second> to evaluate its truth condition at C<$right - 2>
since the result will never be used.

=back




=head1 Creating your own Regex Class

The heierarchy of numerical regular expressions have two basic flavors:
Quantified regular expressions and Grouped regular expressions. If you are
trying to write a rule to apply to data, you are almost certainly interested
in creating a new Quantified regular expression. That's also the easier one
of the two to create, so I'll discuss subclassing that first.

To subclass C<Scrooge::Quantified> (argh... not finished, but see the
next section as it discusses most of this anyway).


=head1 Internals

All regex classes must inheret from C<Scrooge> or a class derived from
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

This function is called when it comes time to apply the regex to see if it
matches the current range. That arguments to the apply function are the left
and right offsets, respectively. (The data is not included, and you should
make sure that you've cached a reference to the container during the C<_prep>
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

This function is called before the regular expression hammers on the supplied
data. If you have any data-specific setup to do, do it in this function.

From the standpoint of internals, you need to know two things: what this
function should prepare and what this function should return. (For a
discussion on intepreting return values from C<_prep>, see Scrooge::Grouped.)

If you are not deriving your class from Scrooge::Quantified or Scrooge::Grouped and
you intend for your regex to run, you must either set C<< $self->{min_size} >>
and C<< $self->{max_size} >> at this point or you must override the
related internal functions so that they operate correctly without having
values associated with those keys.

If, having examined the data, you know that this regex will not match, 
you should return zero. This guarantees that the following functions
will not be called on your regex during this run: C<_apply>, C<_min_size>,
C<_max_size>, and C<_store_match>. Put a little bit
differently, it is safe for any of those functions to assume that C<_prep>
has been called and was able to set up internal data that might be required
for their operation. Furthermore, if you realize in the middle of C<_prep>
that your regex cannot run, it is safe to return 0 immediately and expect
the parent regex to call C<_cleanup> for you. (working here - make sure the
documentation for Scrooge::Grouped details what Grouped regexes are supposed to
do with C<_prep> return values.)

Your regex may still be querried afterwards for a match by
C<get_details_for> or C<get_details>, regardless of the return value of
C<_prep>. In both of those cases, returning the undefined value,
indicating a failed match, would be the proper thing to do.

The C<_prep> method is called as the very first step in C<apply>.



=cut



# The first phase. Back up the old state and clear the current state. The
# state is required to be 'not running' before the regex starts, and it
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
	
	# Stash everything. Note that under repeated invocations of a regex, there
	# may be values that we traditionally stash that have lingered from the
	# previous invocation.
	# I would like to remove those values, but that causes troubles. :-(
#	my @to_stash = $self->_to_stash;
	if (defined $self->{data}) {
		push @{$self->{"old_$_"}}, $self->{$_} foreach $self->_to_stash;
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

# The internal keys with values that we want to protect in case of
# recursive usage:
sub _to_stash {
	croak('Scrooge::_to_stash is a method that takes no arguments')
		unless @_ == 1;
	return qw (data min_size max_size match_details);
}

=item _stash

working here - rewrite, this realy *is* an internal function

This is what is called when you need to stash old copies of internal data.
This happens when your regex is used as a smaller part of a regex, and also
when it is called within the execution of a condition. Basically, if you 
override C<_prep> to initialize any internal data during C<_prep>, you must
override C<_stash> to back it up.

When you override this method, you must call the parent with
C<< $self->SUPER::_stash($data) >> in your overridden method. Otherwise,
internal data needed by the base class will not be properly backed up.

=cut

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
#	# stupid reason, the sub-class's cleanup uses a regex, then we have
#	# to guard against call-stack issues. We do that by noting the size of
#	# the current partial_state stack before we call.
#	my $partial_state_stack_size = scalar(@{$self->{old_partial_state}});
	# Call sub-class's cleanup method:
	eval { $self->_cleanup() };
	my $err_string = $@;
#	# If the partial state stack has changed size, then it's because the
#	# _cleanup method called a numerical regex that contained this regex.
#	# Sounds ridiculous, but under very contrived circumstances, it can
#	# happen without deep recursion. If it happened, restore *this* regex's
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
the C<match_details> key if the regex is named.

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

Grouping regexes like re_and and re_seq need to have some way of
clearing a stored match when something goes wrong, and they do this by
calling C<clear_stored_match>. In the base class's behavior, this function
only runs when there is a name associated with the regex. Grouping regex
objects should clear their children regexes, in addition to clearing their
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

This method adds this regex's name (along with a reference to itself) to the
supplied hashref. This serves two purposes: first, it gives the owner a fast
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

sub add_name_to {
	croak('Scrooge::add_name_to is a one-argument method')
		unless @_ == 2;
	my ($self, $hashref) = @_;
	return unless exists $self->{name};
	
	my $name = $self->{name};
	# check if the name exists:
	croak("Found multiple regular expressions named $name")
		if exists $hashref->{$name} and $hashref->{$name} != $self;
	# Add self to the hashref under $name:
	$hashref->{$name} = $self;
}

=item _get_bracketed_name_string

This returns a string to be used in error messages. It should return an
empty string if the regex does not have a name, or ' [name]' if it does
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

=head2 Cross-Container Accessors

Scrooge is designed to operate on any data container you wish to throw at
it. However, it needs to know how to get certain information about your
container. At the moment, at least, it needs to know how to get your container's
length.

However, the current API also provides hooks for getting an element at
a given offset and for taking a slice of the current data's contents. I hope
that such a general set of functions will make it easier to write
container-agnostic regular expression objects, though the jury is still out on
whether or not this is a good way of doing it. Part of me suspects that this is
not really a generically good idea...

=item %Scrooge::method_table

This holds subroutine references that handle various operations that
are meant to work cross-container. You should add specially named methods to
this table for your container so that calls to C<Scrooge::data_length>,
C<Scrooge::data_at>, and C<Scrooge::data_slice> all work for your
container.

For example, after doing this:

 $Scrooge::method_table{'My::Class::Name'} = {
     # Required for your container to work with Scrooge
     length => sub {
         # Returns the length of its first argument.
         return $_[0]->length;
     },
     # Optional
     at => sub {
         # Returns the value at the given location
         my ($container, $offset) = @_;
         return $container->at($offset);
     },
     # Optional
     slide => sub {
         # Returns a class-equivalent slice:
         my ($container, $left, $right) = @_;
         return $container->subset($left => $right);
     },
 };

Then, if C<$object> is an object or C<My::Class::Name>, you can simply use
C<Scrooge::length($object)> to get the length of your class's container.
See the next item for more details.

=cut

%method_table = (
	(ref [])  => {
		length => sub { return scalar(@$_[0]) },
		at     => sub { return $_[0]->[$_[1]] },
		slice  => sub { return [ @{$_[0]}[$_[1] .. $_[2]] ] },
	},
	PDL => {
		length => sub { return $_[0]->dim(0) },
		at     => sub { return $_[0]->sclr($_[0]) },
		slice  => sub { return $_[0]->slice("$_[1]:$_[2]") },
	},
);

=item data_length, data_at, data_slice

These are generic data-container-agnostic wrappers to get the data's length,
to get an element at a given offset, or to take a slice from a data container.
They delegate to the methods in C<%method_table>, as discussed next.

working here - decide how I want to export these. They should probably export
under the tab C<:container-wrappers> or some such. And, they should definitely
not be documented here but somewhere further down, or even in a separate
document geared towards data container authors.

=cut

sub data_length {
	my $data = shift;
	return $method_table{ref $data}->{length}->($data)
		if exists $method_table{ref $data};
	# working here - consider adding some useful error messages.
	croak("Unable to determine the length of your data\n");
}

sub data_at {
	my ($data, $offset) = @_;
	return $method_table{ref $data}->{at}->($data, $offset);
	# working here - consider adding some useful error messages.
}

sub data_slice {
	my ($data, $left, $right) = @_;
	return $method_table{ref $data}->{slice}->($data, $left, $right);
	# working here - consider adding some useful error messages.
}

=back

=cut

package Scrooge::Quantified;
use parent -norequire, 'Scrooge';
use strict;
use warnings;
use Carp;

=head1 Scrooge::Quantified

The Quantified abstract base class inherets from the Scrooge abstract base class
and provides functionality for handling quantifiers, including parsing the
quantifier argument. If you need a regex object that handles quantifiers but
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

Creates a regex that matches any value.

=cut

sub Scrooge::re_any {
	croak("Scrooge::re_any takes one or two optional arguments: re_any([[name], quantifiers])")
		if @_ > 2;
	
	# Get the arguments:
	my $name = shift if @_ == 2;
	my $quantifiers = shift if @_ == 1;
	$quantifiers = [1,1] unless defined $quantifiers;
	
	# Create the subroutine regexp:
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


# This builds a subroutine regexp object:
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
	
	# Create the subroutine regexp:
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
		die "Subroutine regex$name died:\n$@";
	}
	
	# Make sure they didn't break any rules:
	if ($consumed > $right - $left + 1) {
		my $name = $self->get_bracketed_name_string;
		die "Subroutine regex$name consumed more than it was allowed to consume\n";
	}
	
	# Return the result:
	return ($consumed, %details);
}

package Scrooge::ZeroWidthAssertion;
use parent -norequire, 'Scrooge::Quantified';
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
	my $self = Scrooge::ZeroWidthAssertion->new(quantifiers => [0,0],
		subref => $subref, defined $name ? (name => $name) : ());
	
}

sub _apply {
	my ($self, $left, $right) = @_;
	unless ($right < $left) {
		my $name = $self->get_bracketed_name_string;
		croak("Internal error in calling re_zwa regex$name: $right is not "
			. "less that $left");
	}
	
	# Evaluate their subroutine:
	my ($consumed, %details)
		= eval{$self->{subref}->($self->{data}, $left, $right)};
	
	# Handle any exceptions
	if ($@ ne '') {
		my $name = $self->get_bracketed_name_string;
		die "re_zwa regex$name died:\n$@\n";
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
# Defines grouped regexes, like re_or, re_and, and re_seq
use parent -norequire, 'Scrooge';
use strict;
use warnings;
use Carp;

sub _init {
	my $self = shift;
	croak("Grouped regexes must supply a key [regexes]")
		unless defined $self->{regexes};
	
	croak("You must give me at least one regex in your group")
		unless @{$self->{regexes}} > 0;
	
	# Create the list of names, starting with self's name. Adding self
	# simplifies the logic later.
	$self->{names} = {};
	$self->{names}->{$self->{name}} = $self if defined $self->{name};
	
	# Check each of the child regexes and add their names:
	foreach (@{$self->{regexes}}) {
		croak("Invalid regex") unless eval {$_->isa('Scrooge')};
		$_->add_name_to($self->{names});
	}
	
	return $self;
}

# Derivatives must supply their own _apply

# Some state information that will need to be stashed:
sub _to_stash {
	my $self = shift;
	return qw(regexes_to_apply positive_matches), $self->SUPER::_to_stash;
}

# _prep will call _prep on all its children and keep track of those that
# return true values. Success or failure is based upon the inherited method
# _prep_success.
sub _prep {
	my ($self, $data) = @_;
	# Call the prep function for each of them, keeping track of all those
	# that succeed. Notice that I capture errors and continue because every
	# single regex needs to run its prep method in order for it to be 
	# safe for it to call its cleanup method.
	my @succeeded;
	my @errors;
	foreach (@{$self->{regexes}}) {
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
	
	# Store the regexes to apply. If _prep_success returns zero, we do not
	# need to call cleanup: that will be called by our parent:
	$self->{regexes_to_apply} = \@succeeded;
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

# The default success happens when we plan to apply *all* the regexes
sub _prep_success {
	my $self = shift;
	return @{$self->{regexes}} == @{$self->{regexes_to_apply}};
}

sub _cleanup {
	my $self = shift;
	# Call the cleanup method for *all* child regexes:
	my @errors;
	foreach (@{$self->{regexes}}) {
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
	foreach my $regex (@{$self->{regexes}}) {
		$regex->is_prepping;
	}
}

sub is_applying {
	my $self = shift;
	$self->SUPER::is_applying;
	foreach my $regex (@{$self->{regexes}}) {
		$regex->is_applying;
	}
}

# As with is_prepping, do *not* set the state since cleaning's short-
# circuiting depends on this being clear:
sub is_cleaning {
	my $self = shift;
	$self->SUPER::is_cleaning;
	foreach my $regex (@{$self->{regexes}}) {
		$regex->is_cleaning;
	}
}

# Clear stored match assumes that all the regexes matched, so this will
# need to be overridden for re_or:
sub clear_stored_match {
	my $self = shift;
	# Call the parent's method:
	$self->SUPER::clear_stored_match;
	
	# Call all the positively matched regexes' clear function:
	foreach my $regex (@{$self->{positive_matches}}) {
		$regex->clear_stored_match;
	}
	
	# Always return zero:
	return 0;
}

sub push_match {
	croak('Scrooge::Grouped::push_match is a method that expects two arguments')
		unless @_ == 3;
	my ($self, $regex, $details) = @_;
	push @{$self->{positive_matches}}, $regex;
	$regex->store_match($details);
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
	croak("Unknown regex name $name") unless exists $self->{names}->{$name};
	
	# Propogate the callin context:
	return ($self->{names}->{$name}->get_details) if wantarray;
	return $self->{names}->{$name}->get_details;
}

# This is only called by regexes that *hold* this one, in the process of
# building their own name tables. Add this and all children to the hashref.
# Structures like ABA should pass this, but recursive structures will go
# into deep recursion.
# recursive check this
sub add_name_to {
	my ($self, $hashref) = @_;
	# Go through each named value in this group's collection of names:
	while( my ($name, $ref) = each %{$self->{names}}) {
		croak("Found multiple regular expressions named $name")
			if defined $hashref->{$name} and $hashref->{$name} != $ref;
		
		$hashref->{$name} = $ref;
	}
}



=head2 re_or

This takes a collection of regular expression objects and evaluates all of
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
	foreach my $regex (@{$self->{regexes_to_apply}}) {
		my $min = $regex->min_size;
		my $max = $regex->max_size;
		$full_min = $min if not defined $full_min or $full_min > $min;
		$full_max = $max if not defined $full_max or $full_max < $max;
	}
	$self->min_size($full_min);
	$self->max_size($full_max);
}

# Must override the default _prep_success method. If we have *any* regexes
# that will run, that is considered a success.
sub _prep_success {
	return @{$_[0]->{regexes_to_apply}} > 0;
}

# This only needs to clear out the current matching regex:
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

# Run all the regexes (that said they wanted to run). Return the first
# success that we find:
sub _apply {
	my ($self, $left, $right) = @_;
	my @regexes = @{$self->{regexes_to_apply}};
	my $max_size = $right - $left + 1;
	my $min_r = $left + $self->min_size - 1;
	my $i = 0;
	REGEX: for (my $i = 0; $i < @regexes; $i++) {
		my $regex = $regexes[$i];
		
		# skip if it wants too many:
		next if $regex->min_size > $max_size;
		
		# Determine the minimum allowed right offset
		my $min_r = $left + $regex->min_size - 1;
		
		# Start from the maximum allowed right offset and work our way down:
		my $r = $left + $regex->max_size - 1;
		$r = $right if $r > $right;
		
		RIGHT_OFFSET: while($r >= $min_r) {
			# Apply the regex:
			my ($consumed, %details) = eval{$regex->_apply($left, $r)};
			
			# Check for exceptions:
			if ($@ ne '') {
				my $name = $self->get_bracketed_name_string;
				my $child_name = $regex->get_bracketed_name_string;
				die "In re_or regex$name, ${i}th regex$child_name failed:\n$@"; 
			}
			
			# Make sure that the regex didn't consume more than it was supposed
			# to consume:
			if ($consumed > $r - $left + 1) {
				my $name = $self->get_bracketed_name_string;
				my $child_name = $regex->get_bracketed_name_string;
				die "In re_or regex$name, ${i}th regex$child_name consumed $consumed\n"
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
				$self->push_match($regex => {left =>$left, %details
										, right => $left + $consumed - 1});
				return $consumed;
			}
			
			# At this point, the only option remaining is that the regex
			# returned zero, which means the match will fail at this value
			# of left, so move to the next regex:
			next REGEX;
		}
	}
	return 0;
}

sub Scrooge::re_or {
	# If the first argument is an object, assume no name:
	return Scrooge::Or->new(regexes => \@_) if ref $_[0];
	# Otherwise assume that the first argument is a name:
	my $name = shift;
	return Scrooge::Or->new(name => $name, regexes => \@_);
}

=head2 re_and

This takes a collection of regular expression objects and evaluates all of
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
	my @regexes = @{$self->{regexes_to_apply}};
	for (my $i = 0; $i < @regexes; $i++) {
		my ($consumed, %details) = eval{$regexes[$i]->_apply($left, $right)};
		
		# Croak problems if found:
		if($@ ne '') {
			my $name = $self->get_bracketed_name_string;
			my $child_name = $regexes[$i]->get_bracketed_name_string;
			# Clear the stored matches before dying, just in case:
			$self->pop_match for (1..$i);
			# Make sure i starts counting from 1 in death note:
			$i++;
			die "In re_and regex$name, ${i}th regex$child_name failed:\n$@"; 
		}
		
		# Return failure immediately:
		if (not $consumed) {
			# Clear the stored matches before failing:
			$self->pop_match for (1..$i);
			return 0;
		}
		
		# Croak if the regex consumed more than it was given:
		if ($consumed > $consumed_length) {
			my $name = $self->get_bracketed_name_string;
			my $child_name = $regexes[$i]->get_bracketed_name_string;
			# Clear the stored matches before dying, just in case:
			$self->pop_match for (1..$i);
			# Make sure i starts counting from 1 in death note:
			$i++;
			die "In re_and regex$name, ${i}th regex$child_name consumed $consumed\n"
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
		$self->push_match($regexes[$i], {left => $left, %details
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
	foreach my $regex (@{$self->{regexes_to_apply}}) {
		my $min = $regex->min_size;
		my $max = $regex->max_size;
		$full_min = $min if not defined $full_min or $full_min < $min;
		$full_max = $max if not defined $full_max or $full_max > $max;
	}
	$self->min_size($full_min);
	$self->max_size($full_max);
}

sub Scrooge::re_and {
	# If the first argument is an object, assume no name:
	return Scrooge::And->new(regexes => \@_) if ref $_[0];
	# Otherwise assume that the first argument is a name:
	my $name = shift;
	return Scrooge::And->new(name => $name, regexes => \@_);
}

=head2 re_seq

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

Consider this recursive regex:

  $recursive_seq = re_seq(A, $recursive_seq);

This won't pass add_name_to if either A or the sequence is named, and
if neither are named, it will recurse infinitely and never return. Now,
this problem is better solved with a repetition, but I bet a recursive
sequence regex could be useful in some context, somewhere. Also, it
would fall into a recursive loop figuring out the max or min lengths. :-(

However, consider this regex:

 my ($seq_regex, $and_regex);
 $seq_regex = re_seq(A, $and_regex);
 $and_regex = re_and(B, $seq_regex);
 
 # which is equivalent to 
 $seq_regex = re_seq(A, re_and(B, $seq_regex));

To the best of my knowledge, this sequence can never terminate successfully.
On the other hand, this one can terminate successfully:

 $seq_regex = re_seq(A, re_or(B, $seq_regex));

but that is equivalent to the following repetition regex:

 $regex = re_seq( REPEAT(A), B);

However, this regex cannot be written like that:

 $regex = re_seq(A re_or(B, $regex), A);

That finds nested numerical signatures, much like the followin quasi-string
regex:

 $regex = re_seq(
     /\(/,          # opening paren
     /[^()]*/,      # anything which is not paretheses
     REPEAT([0,1],  # zero or one
         $regex),   #     nested parentheses
     /[^()]*/,      # anything which is not paretheses
     /\)/           # closing paren
 );

So, by allowing for nested regexes, I allow for the possibility of recursive
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
	return $self->seq_apply($left, $right, @{$self->{regexes_to_apply}});
}

sub seq_apply {
	my ($self, $left, $right, @regexes) = @_;
	my $regex = shift @regexes;
	my $data = $self->{data};
	
	# Handle edge case of this being the only regex:
	if (@regexes == 0) {
		# Make sure we don't sent any more or any less than the regex said
		# it was willing to handle:
		my $size = $right - $left + 1;
		return 0 if $size < $regex->min_size;
		
		# Adjust the right edge if the size is too large:
		$size = $regex->max_size if $size > $regex->max_size;
		$right = $left + $size - 1;
		
		my ($consumed, %details) = eval{$regex->_apply($left, $right)};
		
		# If the regex croaked, emit a death:
		if ($@ ne '') {
			my $i = scalar @{$self->{regexes_to_apply}};
			my $name = $self->get_bracketed_name_string;
			my $child_name = $regex->get_bracketed_name_string;
			die "In re_seq regex$name, ${i}th regex$child_name failed:\n$@"; 
		}
		
		# Croak if the regex consumed more than it was given:
		if ($consumed > $size) {
			my $name = $self->get_bracketed_name_string;
			my $child_name = $regex->get_bracketed_name_string;
			# Make sure i starts counting from 1 in death note:
			my $i = scalar @{$self->{regexes_to_apply}};
			die "In re_seq regex$name, ${i}th regex$child_name consumed $consumed\n"
				. "but it was only allowed to consume $size\n";
		}
		
		# Save the match if the match succeeded (i.e. '0 but true', or a
		# positive number):
		$self->push_match($regex, {left => $left, %details,
				right => $left + $consumed - 1})
			if $consumed and $consumed >= 0;
		
		return $consumed;
	}
	
	# Determine the largest possible size based on the requirements of the
	# remaining regexes:
	my $max_consumable = $right - $left + 1;
	$max_consumable -= $_->min_size foreach (@regexes);
	
	# Fail if the maximum consumable size is smaller than this regex's
	# minimum requirement. working here: this condition may never occurr:
	my $min_size = $regex->min_size;
	return 0 if $max_consumable < $min_size;
	
	# Set up for the loop:
	my $max_offset = $max_consumable - 1 + $left;
	my $min_offset = $min_size - 1 + $left;
	my ($left_consumed, $right_consumed) = (0, 0);
	my $full_size = $right - $left + 1;
	my %details;
	
	# Start at the maximum possible size:
	
	LEFT_SIZE: for (my $size = $max_consumable; $size > $min_size; $size--) {
		# Apply this regex to this length:
		($left_consumed, %details) = eval{$regex->_apply($left, $left + $size - 1)};
		# Croak immediately if we encountered a problem:
		if ($@ ne '') {
			my $i = scalar @{$self->{regexes_to_apply}} - scalar(@regexes);
			my $name = $self->get_bracketed_name_string;
			my $child_name = $regex->get_bracketed_name_string;
			die "In re_seq regex$name, ${i}th regex$child_name failed:\n$@"; 
		}
		
		# Fail immediately if we get a numeric zero:
		return 0 unless $left_consumed;
		
		# Croak if the regex consumed more than it was given:
		if ($left_consumed > $size) {
			my $name = $self->get_bracketed_name_string;
			my $child_name = $regex->get_bracketed_name_string;
			# Make sure i starts counting from 1 in death note:
			my $i = scalar @{$self->{regexes_to_apply}} - scalar(@regexes);
			die "In re_seq regex$name, ${i}th regex$child_name consumed $left_consumed\n"
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
		
		# If we are here, we know that the current regex matched starting at
		# left with a size of $size. Store that and then make sure that the
		# remaining regexes match:
		$self->push_match($regex, {left => $left, %details,
				right => $left + $size - 1});
		
		$right_consumed = 0;
		my $curr_right = $right;
		eval {
			do {
				# Shrink the current right edge:
				$curr_right += $right_consumed;
				# Try the regex:
				$right_consumed = $self->seq_apply($left + $size, $curr_right, @regexes);
			} while ($right_consumed < 0);
		};
		
		# Rethrow any problems after cleaning up the match stack:
		if ($@ ne '') {
			$self->pop_match;
			die $@;
		}
		
		# At this point, we know that the right regex either matched at the
		# current value of $curr_right with a width of $right_consumed, or
		# that it failed. If it failed, clear the left regex's match and
		# try again at a shorter size:
		if ($right_consumed == 0) {
			$self->pop_match;
			next LEFT_SIZE;
		}
		
		# If we are here, then it succeeded and we have our return values.
		# Be sure to return "0 but true" if that was what was returned:
		return $left_consumed if $left_consumed + $right_consumed == 0;
		return $left_consumed + $right_consumed;
	}
	
	# We can only be here if the combined regexes failed to match:
	return 0;
}

# Called by the _prep method, sets the internal minimum and maximum sizes:
# recursive check this
sub _minmax {
	my $self = shift;
	my ($full_min, $full_max) = (0, 0);
	
	# Compute the min and max as the sum of the mins and maxes
	foreach my $regex (@{$self->{regexes_to_apply}}) {
		$full_min += $regex->min_size;
		$full_max += $regex->max_size;
	}
	$self->min_size($full_min);
	$self->max_size($full_max);
}

sub Scrooge::re_seq {
	# If the first argument is an object, assume no name:
	return Scrooge::Sequence->new(regexes => \@_) if ref $_[0];
	# Otherwise assume that the first argument is a name:
	my $name = shift;
	return Scrooge::Sequence->new(name => $name, regexes => \@_)
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

=head1 Implementation Details

These are many details that I hope will help you if you try to look closely
at the implementation of this system.

=over

=item Details of stashing and unstashing

I'm keeping these notes as they explain how things work fairly well:

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

=back

=head1 TODO

These are items that are very important or even critical to getting the
regular expression engine to operate properly.

=over

=item Testing: Multiple copies of the same regex, nested calls to regex

I have implemented a match stack to allow for multiple copies of the same
regex within a larger regex. I have also implemented a stashing and
unstashing mechanism to allow for regexes to be called from within other
regexes without breaking the original. However, the code remains untestd.

=item Proper prep, cleanup, and stash handling on croak

I have added lots of code to handle untimely death at various stages of
execution of the regular expression engine. I have furthermore added lots
of lines of explanation for nested and grouped regexes so that pin-pointing
the exact regex is clearer. At this point, I need to test that all of the
deaths do not interfere with proper cleanup and that 

=back

=head1 IDEAS

This is the place where I put my ideas that I would like to implement, but
which are not yet implemented and which are not critical to the sensible
operation of the regular expression engine.

=over

=item Concise Syntax Ideas

A potential concise syntax might look like this:

 $regex = qnre{
    # Comments and whitespace are allowed
    
    # If there is more than one regex in a row, the grouping
    # is assumed to be a re_seq group.
    
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
    Scrooge::OneD::
    
    # Now these constructors have that prefix added so:
    reg1(args)
    # is interpreted as Scrooge::OneD::reg1(args)
    
    # You can explicitly resolve a constructor like so:
    Scrooge::Extra::reg3(args)
    
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
