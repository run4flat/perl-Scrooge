package Scrooge::PDL;

use Exporter 'import';
our @EXPORT = qw(re_intersect re_local_extremum re_local_min re_local_max);
use strict;
use warnings;
use Carp;
our $VERSION = 0.01;

=head1 VERSION

This documentation discusses version 0.01 of PDL.pm

=head1 SYNOPSIS



=head1 DESCRIPTION 

This module provides the user with patterns to match data and the classes for each pattern.
The user is currently supplied with 4 basic patterns to call, their names being re_intersect,
re_local_max, re_local_min, and re_local_extremum. re_intersect allows the user to match data 
outside of a range of their choice, and the other three allow the user to find any local extrema
in a set of data. The re_local_extremum exists so the user can match the first of either local
extrema. When a pattern is called, it returns an object of the corresponding class that the user
can then use to match data sets. 

=head1 PATTERNS AND CLASSES

=head2 re_intersect

This is the short-name constructor for an intersection regex. It takes its
arguments as key/value pairs, where the keys are among the following:

=over

=item name

The regex's name, if you wish to later retrieve the matched indices. Default:
no name (and thus no storage).

=item below, above

The upper and lower bounds (respectively) for your regex. For example, if you
want to match a number between 2 and 5, you would say C<above => 2, below => 5>.

=item quantifiers

The regexes quantifiers, an anonymous two-element array with the min and the
max quantifiers. (See L<Scrooge> for a discussion about quantifiers.)
Default: C<[1, 1]>, i.e. matches one and only one element.

=back

The C<name> and C<quantifiers> keys are not new to C<re_intersect>, but C<above>
and C<below> are. These are the expressions that define the region of values to
match. Both C<above> and C<below> take either pure numbers:

 my $two_to_five = re_intersect(above => 2, below => 5);

or string expressions with a special syntax that I will explain shortly:

 my $three_to_five_stdev
   = re_intersect(above => 'avg + 3@',
                  below => 'avg + 5@');

The strings for C<above> and C<below> can involve arithmetic with numeric values
and a few specially parsed symbols and strings. For example this regex matches
within 2 of the average:

 re_intersect(above => 'avg - 1',
              below => 'avg + 1');
 
and this regex matches data that is between 2% and 50% of the data's total
range (max - min):

The symbols allowed in these sorts of expressions are as follows:

=over

=item a number

Any number, taken alone, is simply the value of that number.

Example:

 above => '2 + 5'

=item avg

The string C<avg> is replaced with the data's average 

=back

 Symbol      Meaning
 ---------------------------
 M           the data's mean
 <number>@   multiples of the data's standard deviation
 <number>%   

At the moment, the expressions for C<above> and C<below> are gently massaged can involve any arithm


=cut

sub re_intersect {
  
  croak("re_intersect takes key-value pairs. You gave an odd number of arguments")
    if @_ % 2 == 1;

  my %args = @_;

  # Check to see if 'above' and 'below' exist
  croak("re_intersect expects an 'above' key.")
    unless exists $args{ above };
    
  croak("re_intersect expects a 'below' key.")
    unless exists $args{ below };
    
  # XXX add check for valid keys
  
  # Defaults to matching 1 element
  $args{ quantifiers } = [1,1]
    unless exists $args{ quantifiers };
    
  return Scrooge::PDL::Intersect->new(%args);
}

=head2 Scrooge::PDL::Intersect

This is the classes called by the constructor re_intersect. This class overrides
the _prep and _apply functions of the parent class Scrooge::Quantified.

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
  my $regex = eval{re_intersect(name => 'test', above => 0, below => 4)};
  my ($matched, $offset) = $regex->apply($data);
  
This will return 1 for $matched, since there is ONE value outside the range, and 4 for $offset
since it is the list index of the location the FIRST match occurred. 

=back

This class also accomodates for quantifiers in the _prep phase, which happens to occur while
parsing the strings. What the quantifiers do is signify to _prep that the user is looking for
a range of values that the subroutine finds. If the quantifiers are not defined in the constructor,
they default to 1. For example:

  $data = pdl(1,2,3,4,5,6,7);
  $regex = eval{re_intersect(name => 'test', above => 0, below => 4)};
  my ($matched, $offset) = $regex->apply($data);
  
This will still return 1 for $matched and 4 for $offset since the quantifiers are not specified 
in the constructor. However, the result is different for the following code:

  $data = pdl(1,2,3,4,5,6,7);
  $regex = eval{re_intersect(name => 'test', above => 0, below => 4, quantifiers => [1,3])};
  my ($matched, $offset) = $regex->apply($data);

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

package Scrooge::PDL::Intersect;
use Scrooge;
use Carp;
use PDL;

our @ISA = qw(Scrooge::Quantified);

###########################################################
# Name       : _prep
# Usage      : $self->_prep($data)
# Purpose    : create an anonymous subroutine that performs the condition check
# Returns    : a True value
# Parameters : $self (implicit), $data
# Throws     : if parse_range_strings had trouble
# Notes      : none atm

sub _prep {
  my ($self, $data) = @_;
  $data = PDL::Core::topdl($data);
 
  # Parse the above and below specifications
  my ($above, $below) = Scrooge::PDL::parse_range_strings(
      $data, $self->{above}, $self->{below}
  );
  
  # It could be the case that the intersection could be null if above is under below.
  # We retrun false to signify to the Regex Engine that it never needs to evaluate this. 
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
    
    # Returns the index of the first point outside the range, which is equal to the length
    # of the match.
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



=head2 re_local_extremum, re_local_max, re_local_min

=cut

package Scrooge::PDL;

sub re_local_extremum () {
  return Scrooge::PDL::Local_Extremum->new(type => 'both');

}

sub re_local_min () {
  
  return Scrooge::PDL::Local_Extremum->new(type => 'min');
  
}

sub re_local_max () {
  
  return Scrooge::PDL::Local_Extremum->new(type => 'max');
  
}

=head2 Scrooge::PDL::Local_Extremum

=cut

package Scrooge::PDL::Local_Extremum;
use strict;
use warnings;
use Scrooge;
use Carp;
use PDL;

our @ISA = qw(Scrooge);

sub min_size { 1 }
sub max_size { 1 }
sub _apply{
  my ($self, $l_off) = @_;
  my $type = $self->{type};
  my $piddle = $self->{data};
  my $max_element = ($piddle->nelem) - 1;
  
  # Expand this to handle the edge cases at some point.
  if ($l_off == 0 or $l_off == $max_element){
    return 0;
  };
  
  if ($type eq 'min' or $type eq'both') {
      return 1 if ((($piddle->at($l_off)) < ($piddle->at($l_off + 1))) && 
                   (($piddle->at($l_off)) < ($piddle->at($l_off - 1))));

  };
  
  if ($type eq 'max' or $type eq'both'){
      return 1 if ( (($piddle->at($l_off)) > ($piddle->at($l_off + 1))) && 
                    (($piddle->at($l_off)) > ($piddle->at($l_off - 1))));
  };
}








=head2 NAME

Scrooge::PDL::Intersect - create regexen to match numbers inside a given numeric range

=head2 SYNOPSIS

At the most basic level, package can be used to find values outside of a range of values
as simple as 0 to 4, as in the case below.

 use Scrooge::PDL;
 my $data = pdl(1,2,3,4,5);
 my $regex = eval{re_intersect(name => 'test regex', above => 0, below => 4)};
 my ($matched, $offset) = $regex->appy($data);
 
$matched will have the value of 1 since it found the first value outside the range [0,4]. 
$offset will have the value 4 since that is the location of the match in the data list. 
 
 
 
 
=head2 DESCRIPTION

This package allows the user to match data in sections, rather than just matching the whole set of data. This
should mainly be used for finding data outside of certain ranges, for example outside 2 standard deviations
from the mean of the data. 

=cut




=head2 NAME

Scrooge::PDL::Local_Extremum - create regex to match the local extrema of a set of data

=head2 SYNOPSIS

The user should not have to deal directly with this package, but utilize it by calling
the methods re_local_max, re_local_min and re_local_extremum to operate on the data. Here 
is a quick example of how this package comes into use.

  use Scrooge::PDL;
  my $data = dl(1,2,3,2,1;)
  my $regex = eval{ re_local_max };
  my ($matched, $offset) = $regex->apply($data);
  
$matched will have the value of 1, since the data has a local maximum, and $offset will
have the value of 2, which is the position of the local maximum in the data list. re_local_max
will only match the first local maximum found if any exists. Likewise, re_local_min will only 
match the first local minimum found if any exists. re_local_extremum will match the first 
local minimum OR the first local maximum, whichever comes first in the list of data. 

=head2 DESCRIPTION

This package lets the user match the local extrema of a set of data. This requires the user to 
input data with no noise since it simply compares single points its immediately adjacent points.
The user should never have to deal directly with the code in the package itself, but should user
one of the three subroutines defined in Scrooge::PDL (re_local_extremum, re_local_min, or re_local_max).



=cut



=head2 Range Strings

working here - document more sufficiently.

The following suffixes and strings are converted:

=over

=item num@

=item num%

=item min

=item max

=item avg

=back

=cut

package Scrooge::PDL;

###########################################################
# Name       : parse_range_strings
# Usage      : parse_range_strings($data, $above, $below, ...)
# Purpose    : parse range strings for a given piddle
# Returns    : numeric values for the given range strings
# Parameters : a piddle, then a collection of range strings
# Throws     : if the range string is not eval-able after munging
# Notes      : none, yet

sub parse_range_strings {
  my $data = shift;
  
  # Ensure we have a good input
  croak('parse_range_strings expects first arg to be a piddle')
    unless eval {$data->isa('PDL')};
  
  my ($mean, $st_dev) = $data->stats;
  my ($min, $max) = $data->minmax;
  my $pct = ($max - $min) / 100;
  my @to_return;
  
  # Parse each string in turn; make a copy so we can modify it
  while (defined (my $range_string = shift @_)) {
    my $original_string = $range_string;
    
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
1;

=head1 AUTHOR

Jeff Giegold C<j.giegold@gmail.com>