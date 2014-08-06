use strict;
use warnings;

package Scrooge;
use Carp;
use Exporter;
use Scalar::Util;
use Scrooge::Quantified;
use Scrooge::Grouped;
use Scrooge::ZWA;

our @ISA = qw(Exporter);

our @EXPORT = qw(re_or re_and re_seq re_sub re_any
		 re_zwa_sub re_zwa_position
		 re_anchor_begin re_anchor_end 
		 re_named_seq re_named_and re_named_or);

our $VERSION = 0.01;

###########################################################
# Usage      : Class::Name->new(key => value, key => value, ...)
# Purpose    : basic init-invoking constructor
# Returns    : new Scrooge object of the given class
# Parameters : invoking class name, key/value pairs
# Throws     : never
# Notes      : none
###########################################################
sub new {
	my $class = shift;
	croak("Internal Error: args to Scrooge::new must have a class name and then key/value pairs")
		unless @_ % 2 == 0;
	my $self = bless {@_}, $class;
	
	# Initialize the class:
	$self->init;
	
	return $self;
}

# Default init does nothing:
sub init { }

###########################################################
# Usage      : $pattern->match($data)
#            : $pattern->match(key => value, key => value, ...)
# Purpose    : runs the greedy pattern match; returns results
# Returns    : success in scalar context: numberof items matched
#            :     (including '0 but true')
#            : success in list context: key/value pairs with match
#            :     results, including left, right, and length (all numeric)
#            : failure in scalar context: 0
#            : failure in list context: empty list
# Parameters : invoking pattern, data to match
# Throws     : if prep, apply, or cleanup stages die
#            : if pattern claims to consume more than it was allowed
# Notes      : This probably should not be overridden
###########################################################
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
	
	# Create the match info hash with some basic info already set:
	my %match_info = (data => $data);
	
	# Prepare the pattern for execution. The actual prep method can fail, so
	# look out for that.
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
	my $N = $match_info{data_length};

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
				
				$consumed = $self->apply(\%match_info) || 0;
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
	eval { $self->cleanup(\%match_info, \%match_info) };
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
		my @name_kv = ($self->{name}, delete $match_info{$self->{name}})
			if $self->{name};
		return %match_info, @name_kv;
	}
	# Otherwise return an empty list:
	return;
}

# I broke this into its own method so that early exits work in a way that is
# well understood: return statements.
sub prep_on_key {
	my ($self, $match_info) = @_;
	
	my $key = $self->{on_key};
	# No on_key? No problem!
	return 1 unless defined $key;
	
	my $data = $match_info->{data};
	
	# Cannot work if the data is not a hashref. Fail in that case.
	return 0 unless ref($data) eq ref({});
	
	# String, which simply gives the key: look for it
	if (ref($key) eq '') {
		return 0 unless exists $data->{$key};
		$match_info->{data} = $data->{$key};
		return 1;
	}
	
	# Regex, which we run against the list of keys in the dataset
	if (ref($key) eq ref(qr//)) {
		for my $k (sort keys %$data) {
			if ($k =~ $key) {
				$match_info->{data} = $data->{$k};
				return 1;
			}
		}
		return 0;
	}
	
	# Neither string nor regex: croak
	croak("Unknown on_key type " . ref($key) . "; expected scalar or qr//");
}

# Default prep handles the on_key option
sub prep {
	my ($self, $match_info) = @_;
	
	# check for on_key handling.
	return 0 unless $self->prep_on_key($match_info);
	
	# Get the data's length and verify that the container is a known type
	my $N = data_length($match_info->{data});
	croak('Could not get length of the supplied data')
		if not defined $N or $N eq '';
	
	# Set up the default min, max, and length information
	$match_info->{min_size} = 1;
	$match_info->{max_size} = $N;
	$match_info->{data_length} = $N;
	
	return 1;
}

# Default cleanup simply ensures its info gets added under its name (if
# named) to the top match info hash
sub cleanup {
	my ($self, $top_match_info, $my_match_info) = @_;
	return unless exists $self->{name};
	
	# We're not supposed to set up our name if there is no top match
	return if not defined $top_match_info;
	
	# Don't set up names more than once.
	return if $my_match_info->{cleaned}++;
	
	# Add our match info to the top match info under $name. I don't need to
	# weaken since $top_match_info properly unlinks this informaton before
	# returning the results
	my $name = $self->{name};
	$top_match_info->{$name} ||= [];
	push @{$top_match_info->{$name}}, $my_match_info;
}

sub get_bracketed_name_string {
	croak('Scrooge::get_bracketed_name_string is a method that takes no arguments')
		unless @_ == 1;
	my $self = shift;
	if (defined $self->{name}) {
		return ' [' . $self->{name} . ']';
	}
	return '';
}

# See also the special cases in data_length
our %length_method_table = (
	(ref [])    => sub { return scalar(@{$_[0]}) },
	PDL         => sub { return $_[0]->dim(0) },
	(ref {})    => sub { 0 },
	(ref sub{}) => sub { 0 },
);

sub data_length {
	my $data = shift;
	
	# Special case undefined data and string data up-front
	croak('undefined data has undefined length') if not defined $data;
	return length($data) if ref($data) eq ref('scalar');
	
	# For all else, refer to the method table
	return $length_method_table{ref $data}->($data)
		if exists $length_method_table{ref $data};
	croak('Scrooge was unable to determine the length of your data, which is of class '
		. ref($data));
}


# Parses a position string and return an offset for a given piece of data.
sub parse_position {
	my ($max_index, $position_string, $stop_at_closing_bracket) = @_;
	
	# Return zero for empty strings (and, incidentially, the number 0)
	return 0 unless $position_string;
	
	# Copy so we can modify the string
	my $original_position_string = $position_string;
	
	# check for malformed input before removing whitespace
	croak("Found whitespace between two numbers without an operator "
		. "in position string $original_position_string")
		if $position_string =~ /[%\d\]]\s+[\d\[]/;
	
	# Remove all whitespace
	$position_string =~ s/\s+//g;
	
	# This will be our final position number. Start off at the natural
	# position.
	my $position = 0;
	
	ROUND: while($position_string ne '') {
		my $dp;
		if ($position_string =~ s/^\]// and $stop_at_closing_bracket) {
			$stop_at_closing_bracket = 'found';
			last ROUND;
		}
		if ($position_string =~ s/^\[//) {
			# parse the interior, which strips off the final square bracket
			($dp, $position_string)
				= parse_position($max_index, $position_string, 1);
			# truncate
			$dp = 0 if $dp < 0; # thus, this will never get adjusted below
			$dp = $max_index if $dp > $max_index;
		}
		elsif ($position_string =~ s/^([+\-]?\d+(\.\d*)?)%//) {
			# percentage strings
			$dp = $1 * $max_index / 100;
		}
		elsif ($position_string =~ s/^([+\-]?\d+(\.\d*)?)//) {
			# bare number
			$dp = $1;
		}
		else {
			croak("Invalid position string $original_position_string");
		}
		$position += $dp;
	}
	
	# Indicate we didn't find the closing bracket
	croak("Did not find closing bracket in position string $original_position_string")
		if $stop_at_closing_bracket and $stop_at_closing_bracket ne 'found';
	
	# Round the result if it's not an integer
	$position = int($position + 0.5) if $position != int($position);
	
	# Return the result. If we are parsing a truncation, also return the
	# clipped position string.
	return ($position, $position_string) if $stop_at_closing_bracket;
	return $position;
}


############################
# Short-named constructors #
############################

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

sub re_anchor_begin {
	return Scrooge::ZWA->new(position => 0);
}

sub re_anchor_end {
	return Scrooge::ZWA->new(position => '100%');
}

sub re_zwa_position {
	return Scrooge::ZWA->new(position => $_[0]) if @_ == 1;
	return Scrooge::ZWA->new(position => [@_]) if @_ == 2;
	croak("re_zwa_position expects either one or two arguments");
}

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

sub re_or {
	# If the first argument is an object, assume no name:
	return Scrooge::Or->new(patterns => \@_) if ref $_[0];
	# Otherwise assume that the first argument is a name:
	my $name = shift;
	return Scrooge::Or->new(name => $name, patterns => \@_);
}

sub re_and {
	# If the first argument is an object, assume no name:
	return Scrooge::And->new(patterns => \@_) if ref $_[0];
	# Otherwise assume that the first argument is a name:
	my $name = shift;
	return Scrooge::And->new(name => $name, patterns => \@_);
}

sub re_seq {
	# If the first argument is an object, assume no name:
	return Scrooge::Sequence->new(patterns => \@_) if ref $_[0];
	# Otherwise assume that the first argument is a name:
	my $name = shift;
	return Scrooge::Sequence->new(name => $name, patterns => \@_)
}

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

sub re_named_or {
	return _build_named_data_group_pattern('Scrooge::Subdata::Or', @_);
}

sub re_named_and {
	return _build_named_data_group_pattern('Scrooge::Subdata::And', @_);
}

sub re_named_seq {
	return _build_named_data_group_pattern('Scrooge::Subdata::Sequence', @_);
}

# THE magic value that indicates this module compiled correctly:
1;

__END__

=head1 NAME

Scrooge - a greedy pattern engine for more than just strings

=cut

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

What follows is broken into three parts: an overview of greedy pattern
matching, a description of the only user-level method C<match>, and an
explanation of how to compose patterns.

=head2 Overview

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

 do_something() if $pattern->match($data);

The Scrooge pattern matching library can be conceptually structured into three
tiers. The top-level tier is a set of functions that help you quickly build
patterns such as C<re_seq> and C<re_any>, as well as the Scrooge methods
that enable you to run patters on data and retrieve the results. The mid-level
tier is the set of classes that actually implement that functionality such as
C<Scrooge::Quantified> and C<Scrooge::Seq>. The bottom-level tier is the
Scrooge base class and its semi-internal workings as a pattern matching engine.
The documentation that follows covers the top and the bottom; the documetation
for the different classes in contained in other modules.

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

=head2 Building Patterns

There are two ways to build patterns. The first is to call the C<new>
method on the class of the pattern you wish to build, which returns an
object of the given type. The second is to use short-name constructors.

=head2 new ($class, %args)

Scrooge is built on a classic new -> init scheme. The default new class
method creates a new object, blesses it, and calls init on the resulting
blessed object. You should not need to override this method. Furthermore,
for most uses, you should not need to call this directly.

This method croaks if, after the class name, there is not an even number of 
remaining arguments since it blesses the hash of key/value pairs into the
supplied class.

It is possible to supply a hashref to a pattern, and have the pattern
work on a given element of that hashref. You do this by supplying the
C<on_key> key/value pair to the constructor. Then, when the pattern is run
on the data, it will check that the data is a hashref and use the data
under the specified key instead of the bare hashref.


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

=head2 re_anchor_begin

Matches at the beginning of the data.

=head2 re_anchor_end

Matches at the end of the data.

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

=head2 re_or

Takes a collection of pattern objects and evaluates all of
them until it finds one that succeeds. This does not take any quantifiers.

=head2 re_and

Takes a collection of pattern objects and evaluates all of
them, returning true if all succeed. This does not take any quantifiers.

=head2 re_seq

Applies a sequence of patterns in the order supplied.

This operates recursively thus:

 1) If the (i-1)th pattern succeeded, attempt to apply the ith pattern at its
    full quantifier range. If that fails, decrement the range until it it
    succeeds. If that fails, consider it a failure of the (i-1th) pattern at
    its current range. If it succeeds, move to the next pattern.
 2) If the ith pattern fails, the match fails.
 3) If the Nth pattern succeeds, return success.

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

=head2 re_named_or

Applies a collections of patterns just like re_or, except that the data
applied to each pattern is based on the given name. The sequence can take an
optional first name, so the calling convention is:

 re_named_or( [name],
     set_name_1 => data_1,
     set_name_2 => data_2,
     ...
 );

=head2 re_named_and

Applies a collections of patterns just like re_and, except that the data
applied to each pattern is based on the given name. The sequence can take an
optional first name, so the calling convention is:

 re_named_and( [name],
     set_name_1 => data_1,
     set_name_2 => data_2,
     ...
 );

=head2 re_named_seq

Applies a sequence of patterns on the associated data sets in the order
supplied. The sequence can take an optional first name, so the calling 
convention is:

 re_named_seq( [name],
     set_name_1 => data_1,
     set_name_2 => data_2,
     ...
 );

=head1 SUBCLASSING

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

=head2 cleanup ($self, $top_match_info, $match_info)

The overridable method C<cleanup> allows you to declutter the C<$match_info>
hashref and clean up any resources at the end of a match. For example, during
the C<prep> stage, some of Scrooge's patterns actually construct small,
optimized subrefs that get called by reference during the match process.
These subrefs get removed during C<cleanup> so they do not show up in the
final, returned hash. The default behavior includes functionality for putting
the match info for this pattern in the top-level match info under the
pattern's name, if it exists. This makes it easie to look up information
about the match.

C<cleanup> may be called many times, so be sure your code does not cause
trouble on multiple invocations. (Note that deleting non-existent keys from
a Perl hash is just fine, because Perl is cool like that.)

These are methods that the general Scrooge subclass writer won't need, but are
still needed sometimes.

=head2 get_bracketed_name_string

This returns a string to be used in error messages. It returns an empty string
if the pattern does not have a name, or ' [name]' if it does have a name. This
is useful for constructing error messages of the following form:

 my $name = $self->get_bracketed_name_string;
 croak("Pattern$name tried to frobnosticate!")

You shouldn't override this unless you want more detailed error messages.

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

=head2 Scrooge::parse_position ($max_offset, $position_string)

C<Scrooge::parse_position> is a utility function that takes a max index and
a position string and evaluates the position. The allowed strings are
documented under L</re_zwa_position>.

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

=cut
