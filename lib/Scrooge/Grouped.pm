use strict;
use warnings;
use Scrooge;

package Scrooge::Grouped;
our @ISA = qw(Scrooge);
use Carp;
use Safe::Isa;

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

=item init

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

sub init {
	my $self = shift;
	$self->SUPER::init;
	
	croak("Grouped patterns must supply a key [patterns] with an array of patterns")
		unless exists $self->{patterns} and ref($self->{patterns}) eq ref([]);
	
	croak("You must give me at least one pattern in your group")
		unless @{$self->{patterns}} > 0;
	
	# Check each of the child patterns
	for my $pattern (@{$self->{patterns}}) {
		croak("Invalid pattern") unless $pattern->$_isa('Scrooge');
	}
	
	return $self;
}

=item prep

The C<prep> method calls C<prep> on all the children patterns (via the
C<prep_all> method). The patterns that do not give trouble are associated
with the key C<group_infos> and success is determined by the
result of the C<prep_success> method. The result of that last method will
depend on the sort of grouping pattern: 'or' patterns will consider it a
successful prep if any of the patterns were successful, but 'and' and
'sequence' patterns will only be happy if all the patterns had successful
preps. Of course, the prep could still fail if the accumulated minimum size
is larger than the data's length. Otherwise, this method returns true.

=cut

# Success or failure is based upon the overrideable method prep_success.
sub prep {
	my ($self, $match_info) = @_;
	
	# Bail out if inherited method fails
	return 0 unless $self->SUPER::prep($match_info);
	
	# Call the prep function for each of them, keeping track of all those
	# that succeed.
	my @succeeded;
	for my $pattern (@{$self->{patterns}}) {
		# Make a copy of the match info for the child pattern
		my $child_match_info = { %$match_info };
		
		# Make sure the min size is not too large:
		if ($pattern->prep($child_match_info) and
			$child_match_info->{min_size} <= $match_info->{data_length}
		) {
			$child_match_info->{_pattern} = $pattern;
			push @succeeded, $child_match_info;
		}
		else {
			# Call cleanup immediately if prep failed
			$pattern->cleanup($child_match_info);
		}
	}
	
	# Store the patterns to apply. If prep returns zero, we do not
	# need to call cleanup: that will be called by our parent:
	$match_info->{infos_to_apply} = \@succeeded;
	return 0 unless $self->prep_success($match_info);
	
	# Cache the minimum and maximum number of elements to match:
	$self->minmax($match_info);
	
	# Check those values for sanity:
	return 0 if $match_info->{max_size} < $match_info->{min_size}
			or $match_info->{min_size} > $match_info->{data_length};
	
	# Create the empty match array, onto which we'll push child pattern
	# info hashes that match
	$match_info->{positive_matches} = [];
	
	# If we're here, then all went well, so return as much:
	return 1;
}

=item cleanup

The C<cleanup> method is responsible for calling C<cleanup> on B<all> the
patterns. The patterns can croak in their C<cleanup> stage, if they think
that's a good idea: all such deaths will be captured and stored until all
patterns have had a chance to C<cleanup>, at which point they will be
rethrown in agregate.

=cut

sub cleanup {
	my ($self, $top_match_info, $match_info) = @_;
	
	# Call our own cleanup (handling named matching)
	$self->SUPER::cleanup($top_match_info, $match_info);
	
	# Call the cleanup method for all successfully prepped child patterns
	my @errors;
	for my $pattern_info (@{$match_info->{infos_to_apply}}) {
		my $pattern = delete $pattern_info->{_pattern};
		eval { $pattern->cleanup($top_match_info, $pattern_info) };
		push @errors, $@ if $@ ne '';
	}
	
	# Rethrow if we caught any exceptions:
	if (@errors == 1) {
		die(@errors);
	}
	elsif (@errors > 1) {
		die(join(('='x20) . "\n", 'Multiple Errors', @errors));
	}
	
	# Remove tracking of group infos (also consider making direct links
	# to child patterns based on key names; working here)
	delete $match_info->{infos_to_apply};
}

=back

Finally, this class has a couple of requirements for derived classes.
Classes that inherit from Scrooge::Grouped must implement these methods:

=over

=item minmax

Scrooge::Grouped calls the method C<minmax> during the C<prep> stage. This
method is supposed to calculate the grouping pattern's minimum and maximum
lengths and store them in the group's match info using the class setters.
The minimum match size for an Or group will be very different from the
minimum match size for a Sequence group, for example.

=item apply

Scrooge::Grouped does not provide an C<apply> method, so derived classes
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

=item minmax

For Or groups, the minimum possible match size is the smallest minimum
reported by all the children, and the maximum possible match size is the
largest maximum reported by all the children.

=cut

# Called by the _prep method; sets the internal minimum and maximum match
# sizes.
sub minmax {
	my ($self, $match_info) = @_;
	my ($full_min, $full_max);
	
	for my $child_info (@{$match_info->{infos_to_apply}}) {
		my $min = $child_info->{min_size};
		my $max = $child_info->{max_size};
		$full_min = $min if not defined $full_min or $full_min > $min;
		$full_max = $max if not defined $full_max or $full_max < $max;
	}
	
	$match_info->{min_size} = $full_min;
	$match_info->{max_size} = $full_max;
}

=item prep_success

Or groups consider a C<prep> to be successful if any one of is children
succeeds, which differs from the base class implementation in which all the
children are expected to succeed.

=cut

sub prep_success {
	my ($self, $match_info) = @_;
	return @{$match_info->{infos_to_apply}} > 0;
}

=item apply

The C<apply> method of Scrooge::Or takes all the patterns that returned a
successful C<prep> and tries to match each of them in turn. Order matters in
so far as the successful match is the first match in the list that returns a
successful match. A pattern is tried on the full range of right offsets
before moving to the next pattern.

=cut

sub apply {
	my ($self, $match_info) = @_;
	my $left = $match_info->{left};
	my $max_size = $match_info->{length};
	INFO: for my $info (@{$match_info->{infos_to_apply}}) {
		my $pattern = $info->{_pattern};
		
		# skip if it wants too many:
		next if $info->{min_size} > $max_size;
		
		# Set up the info for this round of matching
		$info->{left} = $left;
		
		# Determine the minimum allowed right offset
		my $min_r = $left + $info->{min_size} - 1;
		
		# Start from the maximum allowed right offset and work our way down:
		my $r = $left + $info->{max_size} - 1;
		$r = $match_info->{right} if $r > $match_info->{right};
		
		RIGHT_OFFSET: while($r >= $min_r) {
			# Set up the info for this round of matching
			$info->{right} = $r;
			$info->{length} = $r - $left + 1 || '0 but true';
			
			# Apply the pattern:
			my $consumed = eval{ $pattern->apply($info) } || 0;
			
			# Check for exceptions:
			if ($@ ne '') {
				my $name = $self->get_bracketed_name_string;
				my $child_name = $pattern->get_bracketed_name_string;
				die "In re_or pattern$name, subpattern$child_name failed:\n$@"; 
			}
			
			# Make sure that the pattern didn't consume more than it was supposed
			# to consume:
			if ($consumed > $info->{length}) {
				my $name = $self->get_bracketed_name_string;
				my $child_name = $pattern->get_bracketed_name_string;
				die "In re_or pattern$name, subpattern$child_name consumed $consumed\n"
					. "but it was only allowed to consume $info->{length}\n"; 
			}
			
			# Check for a negative return value, which means 'try again at a
			# shorter length'
			if ($consumed < 0) {
				$r += $consumed;
				redo RIGHT_OFFSET;
			}
			
			# Save the results and return if we have a good match:
			if ($consumed) {
				$match_info->{positive_matches} = [$info];
				$info->{length} = $consumed + 0;
				$info->{right} = $left + $consumed - 1;
				return $consumed;
			}
			
			# At this point, the only option remaining is that the pattern
			# returned zero, which means the match will fail at this value
			# of left, so move to the next pattern.
			next INFO;
		}
	}
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

=item minmax

The minimum and maximum sizes reported by Scrooge::And must correspond with
the most restricted possible combination of options. If one child pattern
requires at least five elements and the next pattern requires at least ten
elements, the pattern can only match at least ten elements. Similarly, if
the one pattern can match no more than 20 elements and another can match no
more than 30, the two can only match at most 20 elements.

=cut

# Called by the prep method; stores minimum and maximum match sizes in the
# info hashref
sub minmax {
	my ($self, $match_info) = @_;
	my ($full_min, $full_max);
	
	# Compute the min as the greatest minimum, and max as the least maximum:
	for my $info (@{$match_info->{infos_to_apply}}) {
		my $min = $info->{min_size};
		my $max = $info->{max_size};
		$full_min = $min if not defined $full_min or $full_min < $min;
		$full_max = $max if not defined $full_max or $full_max > $max;
	}
	$match_info->{min_size} = $full_min;
	$match_info->{max_size} = $full_max;
}

=item apply

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

# Return false if any of them fail or if they cannot agree on the matched
# length
sub apply {
	my ($self, $match_info) = @_;
	my $left = $match_info->{left};
	my $consumed_length = $match_info->{length};
	my @infos = @{$match_info->{infos_to_apply}};
	for (my $i = 0; $i < @infos; $i++) {
		# Set up this info's match parameters
		my $info = $infos[$i];
		$info->{left} = $left;
		$info->{right} = $match_info->{right};
		$info->{length} = $match_info->{length};
		
		# Figure out how much the pattern consumes
		my $consumed = eval{ $info->{_pattern}->apply($info) } || 0;
		
		# Croak problems if found:
		if($@ ne '') {
			my $name = $self->get_bracketed_name_string;
			my $child_name = $info->{_pattern}->get_bracketed_name_string;
			# Clear the stored matches before dying, just in case:
			$match_info->{positive_matches} = [];
			# Make sure i starts counting from 1 in death note:
			$i++;
			die "In re_and pattern$name, ${i}th pattern$child_name died:\n$@"; 
		}
		
		# Return failure immediately:
		$match_info->{positive_matches} = [] and return 0 if not $consumed;
		
		# Croak if the pattern consumed more than it was given:
		if ($consumed > $consumed_length) {
			my $name = $self->get_bracketed_name_string;
			my $child_name = $info->{_pattern}->get_bracketed_name_string;
			# Clear the stored matches before dying, just in case:
			$match_info->{positive_matches} = [];
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
			$match_info->{positive_matches} = [];
			
			# Fail if the new length would be too small:
			return 0 if $consumed_length < $match_info->{min_size};
			
			# Adjust the right offset and start over:
			$match_info->{right} = $consumed_length + $left - 1;
			$match_info->{length} = $consumed_length;
			$i = 0;
			redo;
		}
		
		# Otherwise, we have a successful match, so add it:
		push @{$match_info->{positive_matches}}, $info;
		$info->{length} = $consumed + 0;
		$info->{right} = $left + $consumed - 1;
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

=item minmax

For a sequential pattern, the minimum possible match length is the sum of
the minimal lengths; the maximum possible match length is the sum of the
maximal lengths.

=cut

# Called by the prep method, sets the internal minimum and maximum sizes:
sub minmax {
	my ($self, $match_info) = @_;
	my ($full_min, $full_max);
	
	# Compute the min as the greatest minimum, and max as the least maximum:
	for my $info (@{$match_info->{infos_to_apply}}) {
		$full_min += $info->{min_size};
		$full_max += $info->{max_size};
	}
	$match_info->{min_size} = $full_min;
	$match_info->{max_size} = $full_max;
}

=item apply

Applying a sequential pattern involves matching all the children in order,
one after the other. Scrooge::Sequence achieves this by calling its own
C<seq_apply> method recursively on the list of patterns.

=cut

sub apply {
	my ($self, $match_info) = @_;
	my $left = $match_info->{left};
	my $right = $match_info->{right};
	return $self->seq_apply($match_info, $left, $right,
		@{$match_info->{infos_to_apply}});
}

=back

This class also creates a new function that handles the heavy lifting of the
match:

=over

=item seq_apply

This method provides the heavy lifting for the greedy sequential matching.
It takes the sequence's match info, the left offset, the right offset, and a
list of patterns to apply, and operates recursively on the list of patterns.

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
	my ($self, $match_info, $left, $right, @infos_to_apply) = @_;
	my $info = shift @infos_to_apply;
	my $pattern = $info->{_pattern};
	
	$info->{left} = $left;
	
	# Handle edge case of this being the only pattern:
	if (@infos_to_apply == 0) {
		
		# Make sure we don't send any more or any less than the pattern said
		# it was willing to handle:
		my $size = $right - $left + 1;
		return 0 if $size < $info->{min_size};
		# Adjust the right edge if the size is too large:
		$size = $info->{max_size} if $size > $info->{max_size};
		$right = $left + $size - 1;
		
		$info->{right} = $right;
		$info->{length} = $size;
		
		my $consumed = eval{ $pattern->apply($info) } || 0;
		
		# If the pattern croaked, emit a death:
		if ($@ ne '') {
			my $i = scalar @{$match_info->{infos_to_apply}};
			my $name = $self->get_bracketed_name_string;
			my $child_name = $pattern->get_bracketed_name_string;
			die "In re_seq pattern$name, ${i}th pattern$child_name failed:\n$@"; 
		}
		
		# Croak if the pattern consumed more than it was given:
		if ($consumed > $size) {
			my $name = $self->get_bracketed_name_string;
			my $child_name = $pattern->get_bracketed_name_string;
			# Make sure i starts counting from 1 in death note:
			my $i = scalar @{$match_info->{infos_to_apply}};
			die "In re_seq pattern$name, ${i}th pattern$child_name consumed $consumed\n"
				. "but it was only allowed to consume $size\n";
		}
		
		# Save the match if the match succeeded (i.e. '0 but true', or a
		# positive number):
		if ($consumed and $consumed >= 0) {
			push @{$match_info->{positive_matches}}, $info;
			$info->{length} = $consumed + 0;
			$info->{right} = $left + $consumed - 1;
		}
		return $consumed;
	}
	
	# Determine the largest possible size based on the requirements of the
	# remaining patterns:
	my $max_consumable = $right - $left + 1;
	for my $info (@infos_to_apply) {
		$max_consumable -= $info->{min_size};
	}
	
	# Fail if the maximum consumable size is smaller than this pattern's
	# minimum requirement. working here: this condition may never occurr:
	my $min_size = $info->{min_size};
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
		$info->{right} = $left + $size - 1;
		$info->{length} = $size;
		$left_consumed = eval{ $pattern->apply($info) } || 0;
		# Croak immediately if we encountered a problem:
		if ($@ ne '') {
			my $i = scalar @{$match_info->{infos_to_apply}}
				- scalar(@infos_to_apply);
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
			my $i = scalar @{$match_info->{infos_to_apply}}
				- scalar(@infos_to_apply);
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
		$info->{size} = $left_consumed + 0;
		$info->{right} = $left + $left_consumed - 1;
		push @{$match_info->{positive_matches}}, $info;
		
		$right_consumed = 0;
		my $curr_right = $right;
		eval {
			do {
				# Shrink the current right edge:
				$curr_right += $right_consumed;
				# Try the pattern:
				$right_consumed = $self->seq_apply($match_info, $left + $size,
					$curr_right, @infos_to_apply);
			} while ($right_consumed < 0);
		};
		
		# Rethrow any problems after cleaning up the match stack:
		if ($@ ne '') {
			pop @{$match_info->{positive_matches}};
			die $@;
		}
		
		# At this point, we know that the right pattern either matched at the
		# current value of $curr_right with a width of $right_consumed, or
		# that it failed. If it failed, clear the left pattern's match and
		# try again at a shorter size:
		if (!$right_consumed) {
			pop @{$match_info->{positive_matches}};
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
