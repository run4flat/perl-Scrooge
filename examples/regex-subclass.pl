=head1 Regex Subclass

=cut

use PDL::Regex;
package Regex::Engine::Intersect;
use strict;
use warnings;
use Method::Signatures;
use Carp;

our @ISA=qw(Regex::Engine::Quantified);
# Override _init, _prep, _apply, 
# _init: parsing of the string into an abstract structure.
# _prep: take abstract structure and turn into hard numbers, construct a subroutine, eval it, then store it. 
# _apply: invoke subroutine with left and right offsets. 
# write some sort of re_intersect and re_union (functions, not methods).

#Override _init: Ignoring for now
###########################################################
# Name       : _init
# Usage      : $self->_init
# Purpose    : parse the range strings into an op tree
# Returns    : nothing
# Parameters : $self (implicit)
# Throws     : no exceptions
# Notes      : expects keys 'above' and 'below'

#method _init(){
#   Parent class handles quantifiers
#   $self->SUPER::_init;
  
#   XXX 
#}


###########################################################
# Name       : _prep
# Usage      : $self->_prep($data)
# Purpose    : create an anonymous subroutine that performs the condition check
# Returns    : a True value
# Parameters : $self (implicit), $data
# Throws     : no exceptions
# Notes      : none atm

method _prep($data){
  my $above = $self->{ above };
  my $below = $self->{ below };
  
  # It could be the case that the intersection could be null if above is under below.
  # We retrun false to signify to the Regex Engine that it never needs to evaluate this. 
  if ($above < $below){
    return '';
  }
    
  #Build the subroutine reference
  $self->{ subref } = sub {
    my ($left, $right) = @_;
    
    # XXX pick up here. 
    
  };
}

###########################################################
# Name       : _apply
# Usage      : $self->_init
# Purpose    : invoke the subroutine from prep with left and right offsets
# Returns    : nothing
# Parameters : $self (implicit)
# Throws     : no exceptions
# Notes      : expects keys 'above' and 'below'



###########################################################
# Name       : re_intersect
# Usage      : re_intersect(above=>'5', below=>'9@')
# Purpose    : create an intersect regular expression
# Returns    : the regex object
# Parameters : key value pairs: name, quantifiers, above, below
# Throws     : if given an odd number of arguments
#            : if not given an 'above' or 'below'
# Notes      : defaults to quantifier of length 1



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
    
  return Regex::Engine::Intersect->new(%args);
}
