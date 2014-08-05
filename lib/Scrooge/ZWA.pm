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
this class also overrides C<prep> and C<apply> so that its basic behavior is
sensible and useful. During the C<prep> stage, if there is a C<position>
key, it creates a subroutine in the match_info cached under the key
C<zwa_position_subref>. This subroutine evaluates the position assertion
codified by the one or two values asssociated with the C<position> key and
returns boolean values indicating matching or failing to match the position.

For a discussion of the strings allowed in positional asertions, see
L<Scrooge/parse_position>.

The position key can be associated either with a single position (scalar) or
a two-element array ref, each being position strings. If a single position
is given, then this assertion will only match at the given position. If a
pair of positions is given, then this assertion will match at any location
between the first and second positions. If the second position ends up
being "in front of" the first position, the assertion never matches. This
is allowed and will not issue an error or warning.

=over

=item init

This method ensures that the position key, if suppplied, is associated with
a valid value: a scalar or a two-element array. The position string is
parsed for validity during initialization, so you'll know about any errors
before actually applying the pattern.

=cut

sub init {
	my $self = shift;
	$self->SUPER::init;
	
	# No position is ok
	return if not exists $self->{position};
	
	# Scalar position is ok
	return unless ref($self->{position});
	
	# Two-element position is ok
	croak('Scrooge::ZWA optional position key must be associated with a scalar or two-element array')
		unless ref($self->{position}) eq ref([]) and @{$self->{position}} == 2;
	
	# Be sure that the position(s) parse
	my @pos = ref($self->{position}) eq ref([]) ? @{$self->{position}}
		: ($self->{position});
	Scrooge::parse_position(1, $_) foreach (@pos);
}

=item prep

Scrooge::ZWA provides a C<prep> method that converts the value(s) in the
C<position> key to hard offset numbers, based on the length of provided data.
It prepares an optimized subref that is able to quickly evaluate whether the
current positiong satisfies the position constraints, and if no C<position>
is given the subref simply returns true. Thus, if you derive a class from
C<Scrooge::ZWA>, running C<< $self->SUPER::prep >> will ensure that
C<< $match_info->{zwa_position_subref} >> returns subroutine that will give
you a meaningful answer.

If you ever need to call that subref (during apply, presumably), you should
be aware that the subroutine does not expect any arguments; it closes over
the match_info hashref so it can retrieve the match position directly,
without needing to have arguments passed.

=cut

sub prep {
	my ($self, $match_info) = @_;
	
	# Bail out if inherited method fails
	return 0 unless $self->SUPER::prep($match_info);
	
	# Set the min and max size both to zero
	$match_info->{min_size} = $match_info->{max_size} = 0;
	
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
		my $match_offset = Scrooge::parse_position($data_length, $position);
		
		# Fail the prep if the position cannot match
		return 0 if $match_offset < 0 or $match_offset > $data_length;
		
		# Set the match function:
		$match_info->{zwa_position_subref} = sub {
			return $match_info->{left} == $match_offset ? '0 but true' : 0;
		};
		return 1;
	}
	# Check if they specified a start and finish position
	if (ref($position) eq ref([])) {
		my ($left_string, $right_string) = @$position;
		
		# Parse the left and right offsets
		my $left_offset = Scrooge::parse_position($data_length, $left_string);
		my $right_offset = Scrooge::parse_position($data_length, $right_string);
		
		# If the left offset is to the right of the right offset, it can never
		# match so return a value of zero for the prep
		return 0 if $left_offset > $right_offset;
		
		# Otherwise, set up the position match function
		$match_info->{zwa_position_subref} = sub {
			my $position = $match_info->{left};
			return $left_offset <= $position and $position <= $right_offset
				? '0 but true' : 0;
		};
		return 1;
	}
	
	# should never get here if _init does its job
	croak('Scrooge::ZWA internal error - managed to get to end of prep()');
}

=item apply

The default C<apply> for Scrooge::ZWA simply applies the subroutine
associated with C<zwa_position_subref>, which asserts the positional request
codified under the key C<position>. If there is no such key/value pair, then
any position matches, making this something of a no-op.

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
	delete $my_match_info->{zwa_position_subref};
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
evaluates the positional subroutine. If the current position does not match
the position spec, it return immediately and does not even call your
function. (Recall that the position subroutine will return a true value if
there was no position spec.) C<apply> then evaluates the subroutine under
the  C<subref> key, passing along the C<$match_info> hashref.

The subroutine associated with C<subref> B<must> return a value that
evaluates to zero in numeric context, either the string C<'0 but true'> for
a successful match or the numeric value 0 on a failed one. We're not messing
around with this: failure to comply results in a runtime exception stating

  Zero-width assertion did not consume zero elements

=cut

sub apply {
	my ($self, $match_info) = @_;
	
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

