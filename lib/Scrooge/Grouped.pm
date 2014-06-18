use strict;
use warnings;
use Scrooge;

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
the basic methods of C<_init>, C<_prep>, and
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
sub add_name_to {
	my ($self, $hashref) = @_;
	# Go through each named value in this group's collection of names:
	while( my ($name, $ref) = each %{$self->{names}}) {
		croak("Found multiple patterns named $name")
			if defined $hashref->{$name} and $hashref->{$name} != $ref;
		
		$hashref->{$name} = $ref;
	}
}

=item _prep

The C<_prep> method calls C<prep> on all the children patterns (via the
C<prep_all_data> method). The patterns that succeeded are associated with the key
C<patterns_to_apply> and success is determined by the result of the
C<_prep_success> method. The result of that last method will depend on the
sort of grouping pattern: 'or' patterns will consider it a successful prep
if any of the patterns were successful, but 'and' and 'sequence' patterns
will only be happy if all the patterns had successful preps. Of course, the
prep could still fail if the accumulated minimum size is larger than the
data's length. Otherwise, this method returns true.

=cut

# XXX document patterns_to_apply etc
__PACKAGE__->add_special_property('patterns_to_apply', 'data', 'invocation');
__PACKAGE__->add_special_property('cache_keys', 'data', 'invocation');
__PACKAGE__->add_special_property('positive_matches', 'data', 'invocation');
__PACKAGE__->coerce_as_data_property('min_size');
__PACKAGE__->coerce_as_data_property('max_size');

# _prep_invocation simply calls the child prep methods, and ony returns failure
# if they all fail:
sub _prep_invocation {
	my $self = shift;
	
	return 0 unless $self->SUPER::_prep_invocation;
	
	my $N_succeeded = 0;
	foreach my $pattern (@{$self->{patterns}}) {
		$pattern->prep_invocation and $N_succeeded++;
	}
	
	return $N_succeeded > 0;
}

# _prep_data will call prep_data on all its children via the prep_all_data method.
# That method returns the list of successful child patterns and their data
# cache keys. Success or failure is based upon the inherited method
# _prep_success.

sub _prep_data {
	my $self = shift;
	
	# Bail out if inherited method fails
	return 0 unless $self->SUPER::_prep_data;
	
	# Run prep_data on all children
	my ($succeeded, $cache_keys) = $self->prep_all_data;
	
	# Store the patterns to apply. If _prep_success returns zero, we do not
	# need to call cleanup: that will be called by our parent:
	$self->patterns_to_apply($succeeded);
	return 0 unless $self->_prep_success;
	$self->cache_keys($cache_keys);
	$self->positive_matches([]);
	
	# Cache the minimum and maximum number of elements to match:
	$self->_minmax;
	my $data_size = Scrooge::data_length($self->data);
	$self->max_size($data_size) if $self->max_size > $data_size;
	
	# Check those values for sanity:
	return 0 if $self->max_size < $self->min_size
			or $self->min_size > $data_size;

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
	foreach my $pattern (@{$self->positive_matches}) {
		$pattern->clear_stored_match;
	}
	
	# Always return zero:
	return 0;
}

=item is_prepping, is_applying, is_cleaning

Each of these methods ensure that the base Scrooge method is called on the
current Grouping pattern and that the C<is_I<method>>s are called on all of
the children patterns. Note that these methods are called on B<all> the
patterns, whether or not they reported a successful prep.

=cut

# State functions need to be called on all children.
sub is_prepping {
	my $self = shift;
	$self->SUPER::is_prepping;
	
	# Collect any exceptions
	my @errors;
	foreach my $pattern (@{$self->{patterns}}) {
		eval {
			$pattern->is_prepping;
			1
		} or do {
			push @errors, $@;
		}
	}
	
	# Throw exceptions, if any
	if (@errors > 1) {
		die "Multiple patterns died just before prep:\n"
			. join("\n!!! AND !!!\n", @errors);
	}
	elsif (@errors == 1) {
		die "Pattern died just before prep:\n$errors[0]";
	}
}

sub is_applying {
	my $self = shift;
	$self->SUPER::is_applying;
	foreach my $pattern (@{$self->{patterns}}) {
		$pattern->is_applying;
	}
}

# Call the inherited is_cleaning, and all child is_cleaning methods:
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

=item prep_all_data

The C<prep_all_data> method of Scrooge::Grouped calls the C<prep_data> method on
each sub-pattern, tracking their success or failure. Even a successful
C<prep_data> does not guarantee that the pattern will be considered successful:
if the successfully prepped pattern has a minimum size that consumes more data
than is available, it's a failed prep overall and cannot lead to a successful
match. Unless there were exceptions, C<prep_all_data> returns an anonymous list
of successful patterns and a second list of their cache keys.

=cut

sub prep_all_data {
	my $self = shift;
	my $data = $self->data;
	my $cache_key = $self->cache_key;
	
	# Call the prep function for each of them, keeping track of all those
	# that succeed. Notice that I capture errors and continue because every
	# single pattern needs to run its prep method in order for it to be 
	# safe for it to call its cleanup method.
	my @succeeded;
	my @cache_keys;
	foreach (@{$self->{patterns}}) {
		$_->add_data($data);
		my $successful_prep = $_->prep_data;
		
		# Make sure the min size is not too large:
		if ($successful_prep and $_->min_size <= Scrooge::data_length($data)) {
			push @succeeded, $_;
			push @cache_keys, $cache_key;
		}
	}
	
	return \@succeeded, \@cache_keys;
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
	return @{$self->{patterns}} == @{$self->patterns_to_apply};
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
	push @{$self->positive_matches}, $pattern;
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
	$self->positive_matches->[-1]->clear_stored_match;
	pop @{$self->positive_matches};
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
	my ($self) = @_;
	my ($full_min, $full_max);
	
	my @patterns = @{$self->patterns_to_apply};
	my @cache_keys = @{$self->cache_keys};
	# Compute the min as the least minimum, and max as the greatest maximum:
	for my $i (0 .. $#patterns) {
		$patterns[$i]->cache_key($cache_keys[$i]);
		my $min = $patterns[$i]->min_size;
		my $max = $patterns[$i]->max_size;
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
	my ($self) = @_;
	return @{$self->patterns_to_apply} > 0;
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
	my @patterns = @{$self->patterns_to_apply};
	my @cache_keys = @{$self->cache_keys};
	my $max_size = $right - $left + 1;
	my $min_r = $left + $self->min_size - 1;
	my $i = 0;
	PATTERN: for (my $i = 0; $i < @patterns; $i++) {
		my $pattern = $patterns[$i];
		$pattern->cache_key($cache_keys[$i]);
		
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
	
	my @patterns = @{$self->patterns_to_apply};
	my @cache_keys = @{$self->cache_keys};
	# Compute the min as the greatest minimum, and max as the least maximum:
	for my $i (0 .. $#patterns) {
		$patterns[$i]->cache_key($cache_keys[$i]);
		my $min = $patterns[$i]->min_size;
		my $max = $patterns[$i]->max_size;
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
	my @patterns = @{$self->patterns_to_apply};
	my @cache_keys = @{$self->cache_keys};
	for (my $i = 0; $i < @patterns; $i++) {
		$patterns[$i]->cache_key($cache_keys[$i]);
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
work. The overridden methods include:

=over

=item _minmax

For a sequential pattern, the minimum possible match length is the sum of
the minimal lengths; the maximum possible match length is the sum of the
maximal lengths.

=cut

# Called by the _prep method, sets the internal minimum and maximum sizes:
sub _minmax {
	my $self = shift;
	my ($full_min, $full_max);
	
	my @patterns = @{$self->patterns_to_apply};
	my @cache_keys = @{$self->cache_keys};
	# Compute the min and max as the sum of the mins and maxes
	for my $i (0 .. $#patterns) {
		$patterns[$i]->cache_key($cache_keys[$i]);
		$full_min += $patterns[$i]->min_size;
		$full_max += $patterns[$i]->max_size;
	}
	$self->min_size($full_min);
	$self->max_size($full_max);
}

=item _apply

Applying a sequential pattern involves matching all the children in order,
one after the other. Scrooge::Sequence achieves this by calling its own
C<seq_apply> method recursively on the list of patterns.

=cut

sub _apply {
	my ($self, $left, $right) = @_;
	return $self->seq_apply($left, $right
		, $self->patterns_to_apply, $self->cache_keys);
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
	my ($self, $left, $right, $patterns_ref, $cache_keys_ref) = @_;
	my @patterns = @$patterns_ref;
	my @cache_keys = @$cache_keys_ref;
	my $pattern = shift @patterns;
	my $cache_key = shift @cache_keys;
	
	# Set this pattern's cache key before we get going
	$pattern->cache_key($cache_key);
	
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
			my $i = scalar @{$self->patterns_to_apply};
			my $name = $self->get_bracketed_name_string;
			my $child_name = $pattern->get_bracketed_name_string;
			die "In re_seq pattern$name, ${i}th pattern$child_name failed:\n$@"; 
		}
		
		# Croak if the pattern consumed more than it was given:
		if ($consumed > $size) {
			my $name = $self->get_bracketed_name_string;
			my $child_name = $pattern->get_bracketed_name_string;
			# Make sure i starts counting from 1 in death note:
			my $i = scalar @{$self->patterns_to_apply};
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
	for my $i (0 .. $#patterns) {
		$patterns[$i]->cache_key($cache_keys[$i]);
		$max_consumable -= $patterns[$i]->min_size;
	}
	
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
		($left_consumed, %details)
			= eval{$pattern->_apply($left, $left + $size - 1)};
		# Croak immediately if we encountered a problem:
		if ($@ ne '') {
			my $i = scalar @{$self->patterns_to_apply}
				- scalar(@patterns);
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
			my $i = scalar @{$self->patterns_to_apply}
				- scalar(@patterns);
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
				$right_consumed = $self->seq_apply($left + $size, $curr_right
					, \@patterns, \@cache_keys);
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
