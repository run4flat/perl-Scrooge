# Make sure that ANY works as advertised.
use strict;
use warnings;
use Test::More tests => 6;
use PDL::Regex;
use PDL;

my $data = sequence(20);

# ---( Explicit Constructor: 3 )---

# Check that the explicit constructor works:
my $explicit = eval {NRE::Any->_new(quantifiers => [1,1])};
isa_ok($explicit, 'NRE::Any');
my ($matched, $offset) = $explicit->apply($data);
is($matched, 1, 'Properly interprets single-element quantifier');
is($offset, 0, 'Correctly identified first element as matching');

# ---( Simple Constructor, No Quantifiers: 3 )---

# Make sure the simple constructor works and uses quantifiers [1,1]
my $simple = eval {NRE::ANY()};
isa_ok($simple, 'NRE::Any');
($matched, $offset) = $simple->apply($data);
is($matched, 1, 'Simple constructor defaults to a single-element match');
is($offset, 0, 'Simple constructor correctly identified first element as matching');

# ---( Simple Constructor, quantifiers: N )---

# working here

# ---( Simple Constructor, named: N )---



# ---( Simple Constructor, named and quantified: N )---


