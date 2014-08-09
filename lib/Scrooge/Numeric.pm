use strict;
use warnings;

package Scrooge::Numeric;
use Carp;

sub parse_range_string_pair {
	my ($class, $range_string) = shift;
	
	# Make sure we have the delimiters, separated by a comma
	my @items = split /([()\[\],])/, $range_string;
	croak("Invalid bracketed range `$range_string'")
		unless @items == 5;
	croak("Bracketed range `$range_string' does not begin with [ or (")
		unless $items[0] eq '(' or $items[0] eq '[';
	croak("Bracketed range `$range_string' does not end with ] or )")
		unless $items[4] eq ')' or $items[4] eq ']';
	croak("Bracketed range `$range_string' does not separate the range with a comma")
		unless $items[2] eq ',';
	
	# Parse what they gave and return a structured hash with the results
	return {
		left_delim  => $items[0],
		left_spec   => $class->parse_range_string($items[1]),
		right_delim => $items[4],
		right_spec  => $class->parse_range_string($items[3]),
	};
}

my $looks_like_float = qr/[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?/;
sub parse_range_string {
	my $original = my $string = $_[1];
	
	# Strip out all spaces
	$string =~ s/\s+//g;
	# Add a positive sign for the first term, if necessary
	$string = '+' . $string if $string =~ /^[\dmMxX\@i\$]/;
	
	my $spec = {};
	
	# Strip off pieces one at a time
	my $found;
	while($string) {
		# average, min, max
		if ($string =~ s/^(([+-])([\@mMxX]))//) {
			$spec->{$3}++ if $2 eq '+';
			$spec->{$3}-- if $2 eq '-';
		}
		# infinite
		elsif ($string =~ s/(([+-])inf)//) {
			$spec->{inf}++ if $2 eq '+';
			$spec->{inf}-- if $2 eq '-';
		}
		# standard deviation
		elsif ($string =~ s/^(([+-])\$)//) {
			$spec->{stdev}++ if $2 eq '+';
			$spec->{stdev}-- if $2 eq '-';
		}
		elsif ($string =~ s/^(($looks_like_float)\$)//) {
			$spec->{stdev} += $2;
		}
		# percentage range
		elsif ($string =~ s/^(($looks_like_float)%)//) {
			$spec->{pct} += $2;
		}
		# normal number
		elsif ($string =~ s/^($looks_like_float)//) {
			$spec->{raw} += $1;
		}
		else {
			croak("Unable to parse range string `$original' ending with `$string'");
		}
		my $most_recent = $1;
		croak("In range string, `$most_recent' must be followed by '+' or '-' but is followed by `$string'")
			unless $string =~ /^([+-]|$)/;
	}
	return $spec;
}
