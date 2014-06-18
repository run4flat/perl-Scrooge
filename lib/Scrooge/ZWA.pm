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

=item _init

This method ensures that the position key, if suppplied, is associated with a
valid value: a scalar or a two-element array.

=cut

sub _init {
	my $self = shift;
	
	# No position is ok
	return if not exists $self->{position};
	
	# Scalar position is ok
	return unless ref($self->{position});
	
	# Two-element position is ok
	croak('Scrooge::ZWA optional position key must be associated with a scalar or two-element array')
		unless ref($self->{position}) eq ref([]) and @{$self->{position}} == 2;
}

=item min_size, max_size

Scrooge::ZWA overrides min_size and max_size to both return zero.

=cut

sub min_size { 0 }
sub max_size { 0 }

=item zwa_position_subref

Getter/setter for the zero-width position assertion subroutine. XXX

=cut

__PACKAGE__->add_special_property('zwa_position_subref', 'data');

=item _prep_data

XXX double check these docs

Scrooge::ZWA provides a C<_prep_data> method that examines the value associated
with the C<position> key for the data in question. If that value is a scalar
then the exact positiion indicated by that scalar must match. If that value is
an anonymous array with two values, the two values indicate a range of positions
at which the assertion can match. Either way, if there is such a C<position> key
with values as described, the C<_prep_data> method will store an anonymous
subroutine under C<zwa_position_subref> that accepts a single argument---the
left offset---and returns a true or false value indicating whether the position
is matched. C<zwa_position_subref> will always return a usable subroutine: if
there is no C<position> key, the returned subroutine simply always returns a
true value. Thus, if you derive a class from C<Scrooge::ZWA>, running
C<< $self->SUPER::_prep_data >> will ensure that C<< $self->zwa_position_subref >>
returns subroutine that will give you a meaningful evaluation for any given
(left) offset.

=cut

# Prepares the zero-width assertion; parses the position strings and constructs
# an anonymous subroutine that can be called against the current left/right
# position.
sub _prep_data {
	my $self = shift;
	
	# Create a position assertion that always matches if no position was
	# specified.
	if (not exists $self->{position}) {
		$self->zwa_position_subref(sub { 1 });
		return 1;
	}
	
	my $position = $self->{position};
	my $data = $self->data;
	
	# Check if they specified an exact position
	if (ref($position) eq ref('scalar')) {
		my $match_offset = parse_position($data, $position);
		
		# Fail the prep if the position cannot match
		return 0 if $match_offset < 0
			or $match_offset > Scrooge::data_length($data);
		
		# Set the match function:
		$self->zwa_position_subref(sub {
			return $_[0] == $match_offset;
		});
		return 1;
	}
	# Check if they specified a start and finish position
	if (ref($position) eq ref([])) {
		my ($left_string, $right_string) = @$position;
		
		# Parse the left and right offsets
		my $left_offset = parse_position($data, $left_string);
		my $right_offset = parse_position($data, $right_string);
		
		# If the left offset is to the right of the right offset, it can never
		# match so return a value of zero for the prep
		return 0 if $left_offset > $right_offset;
		
		# Otherwise, set up the position match function
		$self->zwa_position_subref(sub {
			return $left_offset <= $_[0] and $_[0] <= $right_offset;
		});
		return 1;
	}
	
	# should never get here if _init does its job
	croak('Scrooge::ZWA internal error - managed to get to end of _prep_data');
}

=item _apply

The default C<_apply> for Scrooge::ZWA simply applies the subroutine associated
with C<zwa_position_subref>, which asserts the positional
request codified under the key C<position>. If there is no such key/value pair,
then any position matches.

=cut

sub _apply {
	my ($self, $left, $right) = @_;
	return '0 but true' if $self->zwa_position_subref->($left);
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
	return 0 unless $self->zwa_position_subref->($left);
	
	# Evaluate their subroutine:
	my ($consumed, %details)
		= eval{$self->{subref}->($self->data, $left, $right)};
	
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

