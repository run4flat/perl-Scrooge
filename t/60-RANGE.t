use strict;
use warnings;
use Test::More tests => 8;
use PDL;
use Regex::Engine::Range;

########################
# Constructor tests: 3 #
########################

my $two_to_five = eval{re_intersect(name => 'test regex', above => '2', below => '5')};
is($@, '', 'Basic constructor does not croak');
isa_ok($two_to_five, 'Regex::Engine::Intersect');
is($two_to_five->{name}, 'test regex', 'Constructor correctly interprets name');


########################
# Basic Match Tests: 5 #
########################
my $data = 4;
my $regex = re_intersect(above => 2, below => 5);
my ($matched, $offset) = $regex->apply($data);
isnt($matched, undef, 'two_to_five matched piddle "4"'); # Check to see if regex matched piddle
is($matched, 1); # Check to see if 1 value was matched
is($offset, 0); #  Check to see if 0 values are out of range

$data = 7;
$regex = re_intersect(above => 2, below => 5);
($matched, $offset) = $regex->apply($data);
is($matched, undef, 'two_to_five could not match piddle "7"'); # Check to see if regex did not match
is($offset, 1); # Check to see if the one point was a part of the offset

__END__
$data = sin(sequence(100)/10);
$data->slice('37') .= 100;

$regex = Regex::Engine::Intersect::re_intersect(above => 2, below => 1000);
($matched, $offset) = $regex->apply($data);
print "not " if not defined $offset or $offset != 37;
print "ok - offset finds crazy value\n";

$regex = Regex::Engine::Intersect::re_intersect(above => 'avg + 2@', below => 1000);
($matched, $offset) = $regex->apply($data);
print "not " if not defined $offset or $offset != 37;
print "ok - offset finds crazy value\n";