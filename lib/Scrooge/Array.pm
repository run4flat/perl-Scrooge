use strict;
use warnings;

package Scrooge::Array;
our @ISA = qw(Scrooge::Quantified);
use Scrooge ();
use Scrooge::Numeric;
use Carp;
our $VERSION = 0.01;

sub prep {
	my ($self, $match_info) = @_;
	
	# Bail out if inherited method fails
	return 0 unless $self->SUPER::prep($match_info);
	
	# Fail prep if the data is ...
	return 0 if
		if not defined $match_info->{data}      # not defined
		or not ref($match_info->{data})         # a scalar
		or ref($match_info->{data}) ne ref([]); # not an array ref
	return 1;
}

=head1 NAME

Scrooge::Array - Scrooge patterns for array data containers

=head1 VERSION

This documentation discusses version 0.01 of Scrooge::Array

=head1 SYNOPSIS

 use Scrooge::Array;
 
 # Find a sequence of values within one
 # standard deviation of the mean.
 my $near_avg = Scrooge::Array->interval '(@-$, @+$)';
 
 # consecutive strings that look like sentences
 my $cap_and_period = Scrooge::Array->regex(qr/^[A-Z].*\.$/);
 
 # consecutive arrayrefs that contain sentences
 my $list_of_lists = Scrooge::Array->isa(ref([]),
     matching => $cap_and_period
 );
 # consecutive arrayrefs that only contain sentences
 my $list_of_lists = Scrooge::Array->isa(ref([]),
     matching => re_seq(
         re_anchor_begin,
         re_rep($cap_and_period),
         re_anchor_end,
     )
 );
 
 # match 3-10 numbers whose values are between 10% of the
 # data range from the data's minimum, and two standard
 # deviations above the mean
 my $crazy_range = Scrooge::Array->range('(m+10%, @+2$)',
     quantifiers => [3,10],
 );
 
 # working here - add examples from local extrema

=head1 DESCRIPTION 

Scrooge::Array provides patterns to match sequences of array data.

=head1 PATTERNS

=head2 scr::arr::interval

This creates a L<Scrooge::Array::Interval> pattern, which matches sequential
elements of an array that are numeric scalars and which fall within the
specified numeric interval. The first argument is the interval string
(which is described in detail under L<Scrooge::Numeric>), followed by key/value
pairs. Scrooge::Array::Interval inherits functionality from Scrooge::Quantified,
so any keys for Scrooge::Quantified can be supplied.

For example:

 use Scrooge::Array;
 my $data = [1 .. 5];
 my $pattern = scr::arr::interval '(0, 4)';
 # Matches against 1, 2, and 3
 my %match_info = $pattern->match($data);

This pattern will croak if you pass an even number of arguments.

For the interval, the values for the mean, min, max, and standard deviation
are based only on the numeric values in the array. Non-numbers are ignored
in these calculations. Thus the following two arrays will both have a mean
of 5, a min of 0, and a max of 10:

 my $arr1 = [0, 5, 10]
 my $arr2 = ['foo', 5, 'bar', 0, 'baz', 10]

=cut

sub scr::arr::interval {
	croak("interval takes an interval followed by key-value pairs. You gave an even number of arguments")
		if @_ % 2 == 0;
	
	return Scrooge::Array::Interval->new(interval => @_);
}

=head2 regex

This creates a L<Scrooge::Array::Regex> pattern, which matches elements of an
array that are scalars and which match the specified regular expression.
The first argument is reference to a regular expression, followed by key/value
pairs. Scrooge::Array::Regex inherits functionality from Scrooge::Quantified,
so any keys for Scrooge::Quantified can be supplied.

For example:

 use Scrooge;
 use Scrooge::Array;
 my $data = [qw(This is a sentence.)];
 my $lowercase = Scrooge::Array->regex qr/^[a-z]+$/;
 # Matches against "is" and "a"
 my %match_info = $lowercase->match($data);

This pattern will croak if you pass an even number of arguments.

=cut

sub regex {
	my $class = shift;
	
	croak("regex takes and range followed by key-value pairs. You gave an even number of arguments")
		if @_ % 2 == 0;
	
	return Scrooge::Array::Regex->new(regex => @_);
}

# XXX working here

=head1 CLASSES

The short-name constructors provided above actually create objects of
various classes, as described below. You should only read this section if you
are interested in the details necessary for deriving a class from one of
these classes. If you just wish to use the patterns, the documentation above
should be sufficient.

=cut

############################################################################
                     package Scrooge::Array::Interval;
############################################################################
our @ISA = qw(Scrooge::Array);
use Scalar::Util qw(looks_like_number);
use Carp;

=head2 Scrooge::Array::Interval

The class underlying L</interval> is C<Scrooge::Array::Interval>. It inherets from
C<Scrooge::Quantified>.

=over

=item init

Ensures that the arguments to the constructor are valid, and parses the
numeric interval string.

=cut

sub init {
	my $self = shift;
	$self->SUPER::init;
	
	# Make sure we have an interval key
	croak('Scrooge::Array::Interval needs an interval key')
		unless exists $self->{interval};
	croak('interval string must be a *string*') if defined ref($self->{interval});
	
	# Make sure the interval key parses
	$self->{parsed_interval}
		= Scrooge::Numeric->parse_interval_string($self->{interval});
	
	return $self;
}

=item prep

Calculates the dataset properties needed for the interval test
and builds a subref that performs the interval check.

=cut

sub prep {
	my ($self, $match_info) = @_;
	
	# Bail out if inherited method fails
	return 0 unless $self->SUPER::prep($match_info);
	
	# Run through the list, keeping track of a number of values
	my $data = $match_info->{data};
	my ($min, $max, $MIN, $MAX, $sum, $sq_sum, $N);
	for my $val (@$data) {
		# Only work with numeric data
		next unless looks_like_number($val);
		# XXX use Data::Float for better checks?
		next if $val eq 'nan';
		
		$N++;
		$MIN = $val if not defined $MIN or $val < $MIN;
		$MAX = $val if not defined $MAX or $val > $MAX;
		$min = $val if $val !~ /^[+-]?inf$/ and 
			(not defined $min or $val < $min);
		$max = $val if $val !~ /^[+-]?inf$/ and 
			(not defined $max or $val > $max);
		$sum += $val;
		$sum_sq += $val*$val;
	}
	# Cannot succeed unless we have some numeric data
	return 0 unless $N;
	
	# var = sum((x - avg_x)**2) / (N - 1)
	#     = sum(x**2 - 2 * x * avg_x + avg_x**2) / (N - 1)
	#     = (sum(x**2) - 2 * avg_x * sum(x) + N * avg_x**2) / (N - 1)
	#     = (sum(x**2) - 2 * sum(x)**2 / N + N * sum(x)**2 / N**2) / (N - 1)
	#     = (sum(x**2) - sum(x)**2 / N) / (N - 1)
	
	# create subref to check the interval, and store it in match_info
	my %data_properties = (
		'@' => $sum / $N, stdev => 0, # default stdev to 0 for only one point
		m => $min, M => $max, x => $MIN, X => $MAX,
	);
	# Only calculate standard deviation if we have two or more points
	$data_properties{stdev} => sqrt(($sum_sq - $sum*$sum / $N) / ($N - 1))
		if $N > 1;
	
	$match_info->{interval_check_subref}
		= Scrooge::Numeric->build_interval_check_subref(
			$self->{parsed_interval}, \%data_properties);
	
	# All set!
	return 1;
}

=item apply



=cut

sub apply {
	my ($self, $match_info) = @_;
	my $left = $match_info->{left};
	my $data = $match_info->{data};
	my $check_subref = $match_info->{interval_check_subref};
	
	# How much of the range do we match?
	for (my $i = $left; $i <= $right; $i++) {
		next if $check_subref->($data->[$i]);
		# If that didn't go to the next $i, then we failed. That means we
		# match everything leading up to $i, but not $i itself. Thus
		# the matched length is:
		return $i - $left;
	}
	# Looks like we match the full length!
	return $right - $left + 1;
}

1;
__END__

##################### XXX working here: local extrema

package Scrooge::Array::Local_Extremum;
use Scrooge;
use Carp;
our @ISA = qw(Scrooge::Array);
use Scalar::Util qw(looks_like_number);

my @allowed_includes = qw(first last ends neither);
sub init {
	my $self = shift;
	$self->{include} ||= 'neither';
	croak('include key must be one of ' . join(', ', @allowed_includes)
		. ' but you gave me ' . $self->{include})
			unless grep { $self->{include} eq $_ } @allowed_includes;
	
	# Build the checker subref
	my $checker_subref_string = q[
		sub {
			my ($data, $position, $length) = @_;
			return 0 unless Scalar::Util::looks_like_number($data->[$position]);
	];
	
	$checker_subref_string .= q[
			return 0 if $position == 0;
	] if $self->{include} eq 'neither' or $self->{include} eq 'last';
	$checker_subref_string .= q[
			return 0 if $position == $length - 1;
	] if $self->{include} eq 'neither' or $self->{include} eq 'first';
	
	
	
	if ($self->{type} eq 'min') {
		$self->{checker_subref} = sub {
			
			
		}
	}
}

# Build checker subref
sub prep {
	my ($self, $match_info) = @_;
	
	# Bail out if inherited method fails
	return 0 unless $self->SUPER::prep($match_info);
	
	if ($self->{
}

# Override to set the min and max sizes directly
sub min_size { 1 }
sub max_size { 1 }

sub apply{
	my ($self, $match_info) = @_;
	my $data = $match_info->{data};
	my $include = $self->{include};
	my $max_element = $match_info->{data_length} - 1;
  
  # Crazy: what if there's only one point?
  return 1 if $max_element == 0 and $include ne 'neither';
  
  # Handle first/last points
  if ($l_off == 0) {
    return 0 if $include eq 'neither' or $include eq 'last';
    return 1 if $piddle->at(0) < $piddle->at(1);
    return 0;
  }
  if ($l_off == $max_element) {
    return 0 if $include eq 'neither' or $include eq 'first';
    return 1 if $piddle->at(-1) > $piddle->at(-2);
    return 0;
  }
  
  # Look for a local min
  if ($type eq 'min' or $type eq 'both') {
      return 1 if $piddle->at($l_off) < $piddle->at($l_off + 1) and 
                  $piddle->at($l_off) < $piddle->at($l_off - 1);

  }
  
  # Look for a local max
  if ($type eq 'max' or $type eq 'both'){
      return 1 if $piddle->at($l_off) > $piddle->at($l_off + 1) and
                  $piddle->at($l_off) > $piddle->at($l_off - 1);
  }
  
  # Failed
  return 0;
}

1;

__END__

=head1 AUTHOR

Jeff Giegold C<j.giegold@gmail.com>,
David Mertens C<dcmertens.perl@gmail.com>
