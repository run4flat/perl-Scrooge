package Scrooge::PDL;

use Exporter 'import';
our @EXPORT = qw(re_range re_local_extremum re_local_min re_local_max);
use strict;
use warnings;
use Carp;
our $VERSION = 0.01;

=head1 NAME

Scrooge::PDL - Basic PDL patterns for Scrooge

=head1 VERSION

This documentation discusses version 0.01 of Scrooge::PDL

=head1 SYNOPSIS

 # match numbers between 5 and 10
 my $five_and_ten = re_range(below => 10, above => 5);
 
 # match 3-10 numbers whose values are between 10% of the
 # data range from the data's minimum, and two standard
 # deviations above the mean
 my $crazy_range = re_range(
     below => '2@',
     above => '10%',
     quantifiers => [3,10],
 );
 
 # working here - add examples from local extrema

=head1 DESCRIPTION 

PDL::Scrooge provides a handful of patterns to match PDL data: C<re_range>,
C<re_local_max>, C<re_local_min>, and C<re_local_extremum>. C<re_range>
matches data in a specified range of relative and/or absolute values. The
other three match any local extrema: max, min, or both, respectively.

=head1 PATTERNS

=head2 re_range

This creates a pattern that matches a numeric range. It takes its
arguments as key/value pairs, where the keys are among the following:

=over

=item name

The pattern's name, if you wish to later retrieve the matched indices. Default:
no name (and thus no storage).

=item below, above

The upper and lower bounds (respectively) for your pattern. For example, if you
want to match a number between 2 and 5, you would say C<< above => 2,
below => 5 >>. To match any value below the data's average, you would say
C<< below => 'avg' >>.

=item quantifiers

The pattern's quantifiers, an anonymous two-element array with the min and the
max quantifiers. (See L<Scrooge> for a discussion about quantifiers.)
Default: C<[1, 1]>, i.e. matches one and only one element.

=back

For example:

 use Scrooge::PDL;
 my $data = pdl(1,2,3,4,5);
 my $pattern = re_range(above => 0, below => 4);
 my ($matched, $offset) = $pattern->appy($data);

The C<name> and C<quantifiers> keys are basic Scrooge quantified properties,
but C<above> and C<below> are new. These are the numbers or, more generally,
L</Range Strings> that define the region of values to match. Both C<above>
and C<below> are parsed according to C<Scrooge::PDL::parse_range_strings>,
which is documented below under L</Range Strings>.

This pattern constructor expects its arguments as key/value pairs, so it will
croak if you pass an odd number of arguments. If you do not specify values
for C<above> or C<below>, -inf and +inf are used, respectively, which means
they will match any values except C<BAD> values and C<nan>.

=cut

sub re_range {
  
  croak("re_range takes key-value pairs. You gave an odd number of arguments")
    if @_ % 2 == 1;

  my %args = @_;
  
  # XXX add check for valid keys
  
  # Defaults to matching 1 element
  $args{ quantifiers } = [1,1]
    unless exists $args{ quantifiers };
    
  return Scrooge::PDL::Range->new(%args);
}

=head2 re_local_min, re_local_max, re_local_extremum

These three functions create patterns that match a single local minimum, a
single local maximum, or a single point that is either a local minimum or a
local maximum. The resulting patterns match only a single element and do not
perform any smoothing: they determine which point is a local extremum by
comparing the the point in question to the values on its left and right. You
might want to consider smoothing your data using
L<conv1d|PDL::Primitive/conv1d> if it is exceedingly noisy.

The default behavior does not match the end-points of your data. You can
indicate that you want to match either or both ends by specifying a string
for the C<include> key with values C<first>, C<last>, or C<ends>:

 re_local_min(include => 'first');
 re_local_min(include => 'ends');

Here's a more complete example:

 use Scrooge::PDL;
 my $data = dl(1,2,3,2,1;)
 my $pattern = re_local_max;
 my ($matched, $offset) = $pattern->apply($data);
 #      1         2


=cut

sub re_local_extremum {
  croak('re_local_extremum expects zero or two arguments')
    if @_ != 0 and @_ != 2;
  return Scrooge::PDL::Local_Extremum->new(type => 'both', @_);
}

sub re_local_min () {
  croak('re_local_extremum expects zero or two arguments')
    if @_ != 0 and @_ != 2;
  return Scrooge::PDL::Local_Extremum->new(type => 'min', @_);
}

sub re_local_max () {
  croak('re_local_extremum expects zero or two arguments')
    if @_ != 0 and @_ != 2;
  return Scrooge::PDL::Local_Extremum->new(type => 'max', @_);
  
}

=head1 Range Strings

Range strings are meant to give you a flexible yet concise means to
specify numeric ranges. They include notation for data minima and maxima,
standard deviations, range percentages, raw numbers, and arithmetic, and
they have a few special cases that are meant to reduce your typing. For
example this pattern matches within 2 of the average:

 re_range(above => 'avg - 1',
          below => 'avg + 1');

and this pattern matches data that is between 2% and 50% of the data's total
range (max - min):

 # long-winded
 re_range(above => 'min + 2%',
          below => 'min + 50%');
 
 # shorter
 re_range(above => '2%',
          below => '50%');

The symbols allowed in these sorts of expressions are as follows:

=over

=item a number

Any number, taken alone or as part of arithmetic, is simply the value of
that number. For example:

 above => 2,
 above => '2 + 5'

=item avg

The string C<avg> is replaced with the data's average. Note this is not the
same as the value for 50%.

=item min, max

The strings C<min> and C<max> are replaced with the data set's min and max
values, respectively.

=item <number>@

A number followed by the C<@> symbol is considered a multiple of standard
deviations. Two standard deviations below the maximum value would be
C<max - 2@>. 

As a special case, if a standard deviation is expressed as the first element
of a range string, it is added to the data's mean. As such, C<2@> is the
same as C<avg + 2@>, but is B<different> from C<2@ + avg>. Although this can
lead to a confusing lack of symmetry, it generally leads to more concise
expressions. For example, this:

 above => '-1@', below => '1@'

is shorter and easier to read than this:

 above => 'avg - 1@', below => 'avg + 1@'

So as a rule, if it's the first element, it means B<standard deviations from
the mean>, but otherwise refers simply to standard deviations.

=item <number>%

A number followed by the C<%> symbol is considered a per-cent of the data's
width. If the data's min is 50 and the max is 150, 10% would translate to
10.

As with the standard deviation, there is a special case if the percentage is
the first element of a range string. In that case, the data's minimum is
added to the percentage. In this way, C<10% + 3> is the same as C<min + 10%
+ 3>, except that it's more concise. This also means that C<max - 10%> is
the same as C<90%>. Such special casing suffers from the dilema that, for
example, C<10% + min> is not the same as C<min + 10%>, but I expect that the
special cased behavior will prove more helpful than problematic. 

Note that negative percentages as the first entries are B<not> special-cased
to be C<max - percentage>. That is not nearly as sensible to me as negative
indices, so it's not special-cased.

=back

Although 0% == min and 100% == max, 50% does not necessarily equate to
C<avg>. This is because C<50%> = C<min + (max - min) / 2>. Unless your data
is exactly linear, this will not be the same as the average of the data.

=head2 parse_range_strings

C<Scrooge::PDL::parse_range_strings> is the function that implements the
Range String parsing. It takes the data of interest as its first argument,
then as many range strings as you wish to supply. The return values will be
the evaluations of the range strings. At the moment, the evaluations are
implemented with actual string evals, which tends to make people uneasy due
to security reasons. So, if security is a big deal for you (i.e. you allow
unknown users from the internet supply arbitrary ranges), don't use this
module.

=cut

###########################################################
# Name       : parse_range_strings
# Usage      : parse_range_strings($data, $above, $below, ...)
# Purpose    : parse range strings for a given piddle
# Returns    : numeric values for the given range strings
# Parameters : a piddle, then a collection of range strings
# Throws     : if the range string is not eval-able after munging
# Notes      : lots of special casing. See the docs for details

my $looks_like_float = qr/[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?/;

sub parse_range_strings {
  my $data = shift;
  
  # Ensure we have a good input
  croak('parse_range_strings expects first arg to be a piddle')
    unless eval {$data->isa('PDL')};
  
  my ($mean, $st_dev) = $data->stats;
  my ($min, $max) = $data->minmax;
  my $pct = ($max - $min) / 100;
  my @to_return;
  
  # Parse each string in turn
  while (defined (my $range_string = shift @_)) {
    
    # Handle infinity parsing up-front
    if ($range_string =~ /^(-?)inf$/) {
      push @to_return, 1 * $range_string;
      next;
    }
    
    # make a copy so we can modify it yet croak the original if there were
    # errors
    my $original_string = $range_string;
    
    #       Special case handling       #
    # Standard deviations at the start of the string
    $range_string =~ s/^\s*($looks_like_float)\@/\$mean + $1 * \$st_dev/;
    # Percentages at the start of the string
    $range_string =~ s/^\s*($looks_like_float)\%/$min + $1 * \$pct/;
    
    # Replace ... 5@ ... with ... 5 * $st_dev ...
    $range_string =~ s/(\d)\s*\@/$1 * \$st_dev/g;
    
    # Replace ... 5% ... with ... 5 * $pct ...  
    $range_string =~ s/(\d)\s*\%/$1 * \$pct/g;
    
    # Replace ... avg ... with ... $mean ...  
    $range_string =~ s/avg/\$mean/g;
    
    # Replace min and max with $min and $max
    $range_string =~ s/min/\$min/g;
    $range_string =~ s/max/\$max/g;
    
    # Evaluate the result and store it, croaking if we ran into trouble
    push @to_return, eval($range_string);
    croak("parse_range_strings had trouble with range_string $original_string")
      if $@ ne '';
  }
  
  # return all strings in list context
  return @to_return if wantarray;
  
  # return only the first result in scalar context
  return $to_return[0];
}

=head1 CLASSES

The short-name constructors provided above actually create objects of
various classes, as described below. You should only read this section if you
are interested in the details necessary for deriving a class from one of
these classes. If you just wish to use the patterns, the documentation above
should be sufficient.

=head2 Scrooge::PDL::Range

The class underlying L</re_range> is C<Scrooge::PDL::Range>. This class
provides its own C<_prep> and C<_apply> methods, but otherwise inherets from
C<Scrooge::Quantified>.

=over

=item _prep

The purpose of overriding the _prep function of the parent class is to be able
to create the object with the above and below values, as well as to create an
anonymous subroutine that _apply can use to match the data. The user never actually
does anything to _prep, as they only need to interact with it through _apply. 
It takes the parameters of $self and $data, which is supplied by the user through _apply.
The only reason it should croak is if parse_range_strings couldn't parse the args from
the user. 

_prep returns whether the pattern could match or not, as well as returning the location
of the match if one occurred. If the pattern did match the data, it will return 1 and the
location of the match (the location being the index of the match in the list of data). 
Otherwise, it returns 0 for the match and undef for the location. This gets returned to
the _apply method.

=item _apply

The purpose of overwriting _apply is because the only thing we need _apply to do is to 
send the data to the _prep method. _apply does none of the matching and does no
manipulation of data, and this is simply because all of this has to take place in _prep.
_apply returns what the anonymous subroutine in _prep returns to it, effectively making
it a bridge between the user and the _prep method.  
Usage of _apply is quite simple. For example:

  my $data = pdl(1,2,3,4,5);
  my $pattern = eval{re_range(name => 'test', above => 0, below => 4)};
  my ($matched, $offset) = $pattern->apply($data);
  
This will return 1 for $matched, since there is ONE value outside the range, and 4 for $offset
since it is the list index of the location the FIRST match occurred. 

=back

This class also accomodates for quantifiers in the _prep phase, which happens to occur while
parsing the strings. What the quantifiers do is signify to _prep that the user is looking for
a range of values that the subroutine finds. If the quantifiers are not defined in the constructor,
they default to 1. For example:

  $data = pdl(1,2,3,4,5,6,7);
  $pattern = eval{re_range(name => 'test', above => 0, below => 4)};
  my ($matched, $offset) = $pattern->apply($data);
  
This will still return 1 for $matched and 4 for $offset since the quantifiers are not specified 
in the constructor. However, the result is different for the following code:

  $data = pdl(1,2,3,4,5,6,7);
  $pattern = eval{re_range(name => 'test', above => 0, below => 4, quantifiers => [1,3])};
  my ($matched, $offset) = $pattern->apply($data);

Now, rather than $matched being 1, $matched is now 3 since the quantifiers signify the user is
looking for a match that is a minimum of 1 point long and a maximum of 3 points long. The results
would be the same if the quantifiers were [1,4] since 3 is in that range, as well as if the
quantifiers were [2,4] since, again, 3 is in that range. 

This class returns an empty string if the above value is above the below value, so the pattern will
never attempt a match. It will return '0 but true' in the case of a zero-width-assertion, since these
are trivially true. It will return 0 and undef if there was no match, or the length of the match and
the location of the first point that matches if there is a match. This class can only do one match at
a time, so if multiple sections of the data match, the pattern will return the first one it finds. 

=cut

package Scrooge::PDL::Range;
use Scrooge;
use Carp;
use PDL;

our @ISA = qw(Scrooge::Quantified);

__PACKAGE__->add_invocation_guarded_property('subref');

sub _init {
  my $self = shift;
  $self->{above} = '-inf' unless defined $self->{above};
  $self->{below} = 'inf' unless defined $self->{below};
  
  $self->SUPER::_init;
}

###########################################################
# Name       : _prep
# Usage      : $self->_prep($data)
# Purpose    : create an anonymous subroutine that performs the condition check
# Returns    : a True value
# Parameters : $self (implicit), $data
# Throws     : if parse_range_strings had trouble
# Notes      : none atm

sub _prep {
  my ($self) = @_;
  my $data = PDL::Core::topdl($self->data);
 
  # Parse the above and below specifications
  my ($above, $below) = Scrooge::PDL::parse_range_strings(
      $data, $self->{above}, $self->{below}
  );
  
  # It could be the case that the range could be null if above is under below.
  # We retrun false to signify to Scrooge that it never needs to evaluate this. 
  if ($above > $below){
    return '';
  }
  # Build the subroutine reference
  $self->{ subref } = sub {
    my ($left, $right) = @_;
    
    # Zero width assertions are trivially true.
    return '0 but true' if ($left > $right);

    my $sub_piddle = $data->slice("$left:$right");

    # Return a failed match if the match doesn't occur
    # at the given left offset 
    return 0 if $data->at($left) >= $below or $data->at($left) <= $above;

    # Return the length of the whole segment if
    # all of data is within the range. 
    return ($right - $left +1) 
        if all ( ($sub_piddle > $above) & ($sub_piddle < $below) );
    
    # Returns the index of the first point outside the range, which is equal
    # to the length of the match.
    return which( ($sub_piddle < $above) | ($sub_piddle > $below))->at(0);     
    
  };
  
  return $self->SUPER::_prep($data);
}

###########################################################
# Name       : _apply
# Usage      : $self->_init
# Purpose    : invoke the subroutine from prep with left and right offsets
# Returns    : nothing
# Parameters : $self (implicit)
# Throws     : no exceptions
# Notes      : expects keys 'above' and 'below'

sub _apply {
  my $self = shift;
  return $self->{subref}->(@_);
}

=head2 Scrooge::PDL::Local_Extremum

This is the class underlying C<re_local_min>, C<re_local_max>, and 
C<re_local_extremum>. C<Scrooge::PDL::Local_Extremum> is itself derived from
the Scrooge base class, not C<Scrooge::Quantified>, since it only matches a
single element. As such, it overrides C<min_size> and C<max_size> to provide
a fixed size of 1. It overrides C<_init> to verify that there is a value for
the C<include> key (and that it's a valid value), the C<_prep> method to
handle never-match situations (like if there is only one point and neither
end-point is considered to be a local exremum) and ensure that the data is a
piddle, and the C<_apply> method, obviously, to check if the current point
of interest is indeed a local minimum or maximum.

Properties include C<include>, C<type>, 

=cut

package Scrooge::PDL::Local_Extremum;
use Scrooge;
use Carp;
use PDL;

our @ISA = qw(Scrooge);

my @allowed_includes = qw(first last ends neither);
sub _init {
  my $self = shift;
  $self->{include} ||= 'neither';
  croak('include key must be one of ' . join(', ', @allowed_includes)
    . ' but you gave me ' . $self->{include})
    unless grep { $self->{include} eq $_ } @allowed_includes;
}

sub min_size { 1 }
sub max_size { 1 }

sub _prep {
  my ($self) = @_;
  my $data = PDL::Core::topdl($self->data);
  
  # Handle edge cases
  return if $data->nelem == 0;
  return if $data->nelem == 1 and $self->{include} eq 'neither';
  
  return 1;
}

sub _apply{
  my ($self, $l_off) = @_;
  my $type = $self->{type};
  my $piddle = $self->data;
  my $include = $self->{include};
  my $max_element = ($piddle->nelem) - 1;
  
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