# Make sure that re_any works as advertised, and that quantifiers
# also work as advertised.
use strict;
use warnings;
use Test::More tests => 8;
use Scrooge;
use PDL;

my $data = sequence(20);

# ---( Explicit Constructor: 3 )---

# Check that the explicit constructor works:
$@ = '';
my $explicit = eval {Scrooge::Any->new(quantifiers => [1,1])};
is($@, '', 'Scrooge::Any->new does not croak');
isa_ok($explicit, 'Scrooge::Any') or diag($@);
my ($matched, $offset) = $explicit->apply($data);
is($matched, 1, 'Properly interprets single-element quantifier');
is($offset, 0, 'Correctly identified first element as matching');

# ---( Simple Constructor, No Quantifiers: 3 )---

# Make sure the simple constructor works and uses quantifiers [1,1]
$@ = '';
my $simple = eval {re_any()};
is($@, '', 're_any does not croak');
isa_ok($simple, 'Scrooge::Any');
($matched, $offset) = $simple->apply($data);
is($matched, 1, 'Simple constructor defaults to a single-element match');
is($offset, 0, 'Simple constructor correctly identified first element as matching');

# ---( Simple Constructor, quantifiers: N )---

# Good handling of quantifiers, including larger-than 100%, less than
# 0%, too large, too small, etc

# working here

# ---( Simple Constructor, named: N )---



# ---( Simple Constructor, named and quantified: N )---


