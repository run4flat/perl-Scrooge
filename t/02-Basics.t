# Runs Basics' test

# Load the basics module:
my $module_name = 'Basics.pm';
if (-f $module_name) {
	require $module_name;
}
elsif (-f "t/$module_name") {
	require "t/$module_name";
}
elsif (-f "t\\$module_name") {
	require "t\\$module_name";
}

use strict;
use warnings;
use Scrooge;
use Test::More tests => 72;
use PDL;

my ($regex, $length, $offset);
my $piddle = sequence(10);
my @array = (0..9);

##################################
# Scrooge::data_length tests - 2 #
##################################

is(Scrooge::data_length(\@array), 10, 'Scrooge::data_length knows how to measure array lengths');
is(Scrooge::data_length($piddle), 10, 'Scrooge::data_length knows how to measure piddle lengths');

###########################################################################
#                        Scrooge::Test::Fail - 4                       #
###########################################################################

# ---( Build and make sure it builds properly, 2 )---
$regex = eval { Scrooge::Test::Fail->new };
is($@, '', 'Test::Fail constructor does not croak');
isa_ok($regex, 'Scrooge::Test::Fail');

# ---( Basic application, 2 )---
($length, $offset) = $regex->apply($piddle);
is($length, undef, 'Test::Fail always fails, returning undef for length');
is($offset, undef, 'Test::Fail always fails, returning undef for offset');


###########################################################################
#                     Scrooge::Test::Fail::Prep - 4                    #
###########################################################################

# ---( Build and make sure it builds properly, 2 )---
$regex = eval { Scrooge::Test::Fail::Prep->new };
is($@, '', 'Test::Fail::Prep constructor does not croak');
isa_ok($regex, 'Scrooge::Test::Fail::Prep');

# ---( Basic application, 2 )---
($length, $offset) = $regex->apply($piddle);
is($length, undef, 'Test::Fail::Prep always fails, returning undef for length');
is($offset, undef, 'Test::Fail::Prep always fails, returning undef for offset');


###########################################################################
#                        Scrooge::Test::All - 6                        #
###########################################################################

# ---( Build and make sure it builds properly, 2 )---
$regex = eval { Scrooge::Test::All->new };
is($@, '', 'Test::All constructor does not croak');
isa_ok($regex, 'Scrooge::Test::All');

# ---( Basic regex application to a piddle, 2 )---
($length, $offset) = $regex->apply($piddle);
is($length, $piddle->nelem, 'Test::All always matches all that it is given');
is($offset, 0, 'Test::All always matches at the start of what it is given');

# ---( Basic regex application to a piddle, 2 )---
($length, $offset) = $regex->apply(\@array);
is($length, scalar(@array), 'Test::All always matches all that it is given');
is($offset, 0, 'Test::All always matches at the start of what it is given');


###########################################################################
#                       Scrooge::Test::Croak - 3                       #
###########################################################################

# ---( Build and make sure it runs properly, 3 )---
$regex = eval { Scrooge::Test::Croak->new };
is($@, '', 'Test::Croak constructor does not croak (that comes during apply)');
isa_ok($regex, 'Scrooge::Test::Croak');
eval{$regex->apply($piddle)};
isnt($@, '', 'Engine croaks when its regex croaks');


###########################################################################
#                    Scrooge::Test::ShouldCroak - 3                    #
###########################################################################

# ---( Build and make sure it runs properly, 3 )---
$regex = eval { Scrooge::Test::ShouldCroak->new };
is($@, '', 'Test::ShouldCroak constructor does not croak (that comes during apply)');
isa_ok($regex, 'Scrooge::Test::ShouldCroak');
eval{$regex->apply($piddle)};
isnt($@, '', 'Engine croaks when regex consumes more than it was given');


###########################################################################
#                       Scrooge::Test::Even - 10                       #
###########################################################################

# ---( Build and make sure it builds properly, 2 )---
$regex = eval { Scrooge::Test::Even->new };
is($@, '', 'Test::Even constructor does not croak');
isa_ok($regex, 'Scrooge::Test::Even');

# ---( Basic regex application, 8 )---
($length, $offset) = $regex->apply($piddle);
is($length, $piddle->nelem, 'Test::Even always matches the longest even length');
is($offset, 0, 'Test::Even always matches at the start of what it is given');
($length, $offset) = $regex->apply($piddle->slice("0:-2"));
is($length, $piddle->nelem - 2, 'Test::Even always matches the longest even length');
is($offset, 0, 'Test::Even always matches at the start of what it is given');
($length, $offset) = $regex->apply($piddle->slice("0:-3"));
is($length, $piddle->nelem - 2, 'Test::Even always matches the longest even length');
is($offset, 0, 'Test::Even always matches at the start of what it is given');
($length, $offset) = $regex->apply($piddle->slice("0:-4"));
is($length, $piddle->nelem - 4, 'Test::Even always matches the longest even length');
is($offset, 0, 'Test::Even always matches at the start of what it is given');


###########################################################################
#                      Scrooge::Test::Exactly - 12                     #
###########################################################################

# ---( Build and make sure it builds ok, 4 )---
$regex = eval{ Scrooge::Test::Exactly->new(N => 5) };
is($@, '', 'Test::Exactly constructor does not croak');
isa_ok($regex, 'Scrooge::Test::Exactly');
# Test that it matches 5 elements:
($length, $offset) = $regex->apply($piddle);
is($length, 5, 'Test::Exactly should match the exact specified number of elements');
is($offset, 0, 'Test::Exactly should always have a matched offset of zero');

# ---( Change to a length that is too long, 2 )---
$regex->set_N(12);
($length, $offset) = eval {$regex->apply($piddle)};
is($length, undef, 'Test::Exactly does not match when data is too short');
is($@, '', 'Failed evaluation does not throw an exception');

# ---( Boundary conditions, 6 )---
$regex->set_N(10);
($length, $offset) = $regex->apply($piddle);
is($length, 10, 'Test::Exactly should match the exact specified number of elements');
is($offset, 0, 'Test::Exactly should always have a matched offset of zero');
$regex->set_N(9);
($length, $offset) = $regex->apply($piddle);
is($length, 9, 'Test::Exactly should match the exact specified number of elements');
is($offset, 0, 'Test::Exactly should always have a matched offset of zero');
$regex->set_N(11);
($length, $offset) = $regex->apply($piddle);
is($length, undef, 'Test::Exactly does not match when data is too short');
is($offset, undef, 'Test::Exactly does not match when data is too short');


###########################################################################
#                       Scrooge::Test::Range - 15                      #
###########################################################################

# ---( Build and make sure it builds properly, 4 )---
$regex = eval { Scrooge::Test::Range->new };
is($@, '', 'Test::Range constructor does not croak');
isa_ok($regex, 'Scrooge::Test::Range');
is($regex->{min_size}, 1, 'Default min_size is 1');
is($regex->{max_size}, 1, 'Default max_size is 1');

# ---( Basic tests, 6 )---
($length, $offset) = $regex->apply($piddle);
is($length, 1, 'Test::Range should match the maximum possible specified number of elements');
is($offset, 0, 'Test::Range should always have a matched offset of zero');
$regex->{max_size} = 5;
($length, $offset) = $regex->apply($piddle);
is($length, 5, 'Test::Range should match the maximum possible specified number of elements');
is($offset, 0, 'Test::Range should always have a matched offset of zero');
$regex->{max_size} = 12;
($length, $offset) = $regex->apply($piddle);
is($length, 10, 'Test::Range should match the maximum possible specified number of elements');
is($offset, 0, 'Test::Range should always have a matched offset of zero');

# ---( Min-length tests, 5 )---
$regex->{min_size} = 10;
($length, $offset) = $regex->apply($piddle);
is($length, 10, 'Test::Range should match the maximum possible specified number of elements');
is($offset, 0, 'Test::Range should always have a matched offset of zero');
$regex->{min_size} = 11;
($length, $offset) = eval{ $regex->apply($piddle) };
is($@, '', 'Failed Test::Range match does not throw an exception');
is($length, undef, 'Test::Range should not match if data is smaller than min');
is($offset, undef, 'Test::Range should not match if data is smaller than min');


###########################################################################
#                  Scrooge::Test::Exactly::Offset - 13                 #
###########################################################################

# ---( Build and make sure it builds properly, 5 )---
$regex = eval { Scrooge::Test::Exactly::Offset->new };
is($@, '', 'Test::Exactly::Offset constructor does not croak');
isa_ok($regex, 'Scrooge::Test::Exactly::Offset');
is($regex->min_size, 1, 'Default min_size is 1');
is($regex->max_size, 1, 'Default max_size is 1');
is($regex->{offset}, 0, 'Default offset is 0');

# ---( Compare with Test::Exactly, 1 )---
my $exact_regex = Scrooge::Test::Exactly->new(N => 5);
$regex = Scrooge::Test::Exactly::Offset->new(N => 5);
is_deeply([$exact_regex->apply($piddle)], [$regex->apply($piddle)],
	, 'Test::Exactly::Offset agrees with basic Test::Exactly');

# ---( Nonzero offset, 4 )---
$regex->set_offset(2);
($length, $offset) = $regex->apply($piddle);
is($length, 5, 'Test::Exactly::Offset matches specified length');
is($offset, 2, 'Test::Exactly::Offset matches specified offset');
# corner case:
$regex->set_offset(5);
($length, $offset) = $regex->apply($piddle);
is($length, 5, 'Test::Exactly::Offset matches specified corner-case length');
is($offset, 5, 'Test::Exactly::Offset matches specified corner-case offset');

# ---( Failing situations, 3 )---
$regex->set_offset(6);
($length, $offset) = $regex->apply($piddle);
is($length, undef, 'Test::Exactly::Offset fails at corner-case');
# make sure it doesn't croak if offset is huge
$regex->set_offset(20);
($length, $offset) = eval{$regex->apply($piddle)};
is($@, '', 'Huge offset does not make Test::Exactly::Offset croak');
is($offset, undef, 'Test::Exactly::Offset fails for overly large offset');

