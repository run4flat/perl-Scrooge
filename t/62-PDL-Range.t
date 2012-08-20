use strict;
use warnings;
use Test::More skip_all => 'none at the moment';
	#tests => 0;
use PDL;
use Scrooge::PDL;

my $data = sequence(21) + 5;

