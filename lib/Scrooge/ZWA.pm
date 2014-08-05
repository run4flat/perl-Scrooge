use strict;
use warnings;
use Scrooge;

package Scrooge::ZWA;
our @ISA = ('Scrooge');
use Carp;

=head2 Scrooge::ZWA

Scrooge::ZWA is a base class for zero-width assertions. It is derived directly
from C<Scrooge>, not C<Scrooge::Quantified>. It provides the means to indicate
positions at which it should match, although you are not required to specify
match B<positions> to use this class.

Besides setting the min and max allowed size to zero during the prep stage,
this class also overrides C<prep> and C<apply>
so that its basic behavior is sensible and useful. During the C<prep> stage,
if there is a C<position> key, it creates a subroutine cached under the key
C<zwa_position_subref> that evaluates the position assertion codified by the
one or two values asssociated with the C<position> key and returns boolean
values indicating matching or failing to match the position.

For a discussion of the strings allowed in positional asertions, see
L</re_zwa_position>.

=over

=item init

This method ensures that the position key, if suppplied, is associated with a
valid value: a scalar or a two-element array.

=cut

sub init {
	my $self = shift;
	
	# No position is ok
	return if not exists $self->{position};
	
	# Scalar position is ok
	return unless ref($self->{position});
	
	# Two-element position is ok
	croak('Scrooge::ZWA optional position key must be associated with a scalar or two-element array')
		unless ref($self->{position}) eq ref([]) and @{$self->{position}} == 2;
}

=item prep

Scrooge::ZWA provides a C<prep> method that examines the value associated
with the C<position> key for the data in question. If that value is a scalar
then the exact positiion indicated by that scalar must match. If that value is
an anonymous array with two values, the two values indicate a range of positions
at which the assertion can match. Either way, if there is such a C<position> key
with values as described, the C<prep> method will store an anonymous
subroutine under C<zwa_position_subref> that returns a true or false value
indicating whether the position is matched. Note that the subroutine accepts
no arguments; it closes over the match_info hashref, so it can retrieve the
match position directly, without needing to have arguments passed.
C<zwa_position_subref> will always be associated with a usable subref: if
there is no C<position> key, the returned subroutine simply always returns a
true value. Thus, if you derive a class from C<Scrooge::ZWA>, running
C<< $self->SUPER::prep >> will ensure that C<< $match_info->{zwa_position_subref} >>
returns subroutine that will give you a meaningful answer.

=cut

# Prepares the zero-width assertion; parses the position strings and constructs
# an anonymous subroutine that gets evaluated against the current left/right
# position.
sub prep {
	my ($self, $match_info) = @_;
	
	# Bail out if inherited method fails
	return 0 unless $self->SUPER::prep($match_info);
	
	# Create a position assertion that always matches if no position was
	# specified.
	if (not exists $self->{position}) {
		$match_info->{zwa_position_subref} = sub { 1 };
		return 1;
	}
	
	my $position = $self->{position};
	my $data_length = $match_info->{data};
	
	# Check if they specified an exact position
	if (ref($position) eq ref('scalar')) {
		my $match_offset = parse_position($data_length, $position);
		
		# Fail the prep if the position cannot match
		return 0 if $match_offset < 0 or $match_offset > $data_length;
		
		# Set the match function:
		$self->zwa_position_subref(sub {
			return $match_info->{left} == $match_offset;
		});
		return 1;
	}
	# Check if they specified a start and finish position
	if (ref($position) eq ref([])) {
		my ($left_string, $right_string) = @$position;
		
		# Parse the left and right offsets
		my $left_offset = parse_position($data_length, $left_string);
		my $right_offset = parse_position($data_length, $right_string);
		
		# If the left offset is to the right of the right offset, it can never
		# match so return a value of zero for the prep
		return 0 if $left_offset > $right_offset;
		
		# Otherwise, set up the position match function
		$self->zwa_position_subref(sub {
			my $position = $match_info->{left};
			return $left_offset <= $position and $position <= $right_offset;
		});
		return 1;
	}
	
	# should never get here if _init does its job
	croak('Scrooge::ZWA internal error - managed to get to end of prep()');
}

=item apply

The default C<apply> for Scrooge::ZWA simply applies the subroutine associated
with C<zwa_position_subref>, which asserts the positional
request codified under the key C<position>. If there is no such key/value pair,
then any position matches.

=cut

sub apply {
	my ($self, $match_info) = @_;
	return $match_info->{zwa_position_subref}->();
}

=item cleanup

The cleanup for Scrooge::ZWA removes the subref under C<zwa_position_subref>.

=cut

sub cleanup {
	my ($self, $top_match_info, $my_match_info) = @_;
	$self->SUPER::cleanup($top_match_info, $my_match_info);
	delete $match_info->{zwa_position_subref};
}

=back

Scrooge::ZWA also provides a useful utility for parsing positions:

=over

=item parse_position

C<Scrooge::ZWA::parse_position> takes a max index and a position string
and evaluates the position. The allowed strings are documented under
L</re_zwa_position>.

=cut

# Parses a position string and return an offset for a given piece of data.
use Scalar::Util qw(looks_like_number);
sub parse_position{
	my ($max_index, $position_string) = @_;
	
	# Create the percentage scale
	my $pct = $max_index/100;
	
	my $original_position_string = $position_string;
	my $position;
	
	# Strip edge whitespace
	$position_string =~ s/^\s+//;
	$position_string =~ s/\s+$//;
	
	# Return zero for empty strings
	return 0 if $position_string eq '';
	
	if ($position_string =~ s/^\[(.*)\]/$1/s) {
		# Handle truncation
		my $to_truncate = parse_position($max_index, $position_string);
		$position = 0 if $position < 0;
		$position = $max_index if $position > $max_index;
	}
	elsif ($position_string =~ s/^([+\-]?\d+(\.\d*)?)%//) {
		# Handle percentage strings
		my $pct = $1 * $max_index / 100;
		$position = parse_position($max_index, $position_string) + $pct;
	}
	elsif (not looks_like_number($position_string)) {
		croak"parse_position expected a number but got $original_position_string");
	}
	
	# handle negative offsets
	$position += $max_index if $position < 0;
	
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
Scrooge::ZWA. This class provides a means for overriding the C<apply>
method of zero-width assertions by allowing you to provide an anonymous
subroutine reference that will be evaluated to determine if the zero-width
assertion should hold at the given position. It expects the subroutine to be
associated with the C<subref> key.

This class overrides the following methods:

=over

=item init

The C<init> method of Scrooge::ZWA::Sub ensures that you provided a
subroutine associated with the C<subref> key, and it calls Scrooge::ZWA::init
as well, to handle the position key (if any).

=cut

sub init {
	my $self = shift;
	
	# Verify the subref
	croak("Scrooge::ZWA::Sub requires a subroutine reference associated with key 'subref'")
		unless exists $self->{subref} and ref($self->{subref}) eq ref(sub{});
	
	$self->SUPER::init;
}

=item apply

The C<apply> method of Scrooge::ZWA::Sub proceeds in two stages. First it
evaluates the positional subroutine, returning false if the position does
not match the position spec. Recall that the position subroutine will return
a true value if there was no position spec. At any rate, if the position
subroutine returns true, C<apply> evaluates the subroutine under the 
C<subref> key, passing along the C<$match_info>.

The subroutine associated with C<subref> must return a value that evaluates
to zero in numeric context, either the string C<'0 but true'> for a successful
match or the numeric value 0 on a failed one.

=cut

sub apply {
	my ($self, $match_info) = @_;
	unless ($match_info->{right} < $match_info->{right}) {
		my $name = $self->get_bracketed_name_string;
		croak("Internal error in calling re_zwa pattern$name: $match_info->{right} is not "
			. "less that $match_info->{right}");
	}
	
	# Make sure the position matches the specification (and if they didn't
	# indicate a position, it will always match)
	return 0 unless $match_info->{zwa_position_subref}->();
	
	# Evaluate their subroutine:
	my $consumed = eval{ $self->{subref}->($match_info) };
	
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
	return $consumed;
}

=back

=cut

