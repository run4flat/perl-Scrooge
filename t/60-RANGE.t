use strict;
use warnings;
use Test::More tests => 3;
use PDL;
use Regex::Engine::Range;

########################
# Constructor tests: 3 #
########################

my $two_to_five = eval{re_intersect(name => 'test regex', above => '2', below => '5')};
is($@, '', 'Basic constructor does not croak');
isa_ok($two_to_five, 'Regex::Engine::Intersect');
is($two_to_five->{name}, 'test regex', 'Constructor correctly interprets name');


#######################
# 