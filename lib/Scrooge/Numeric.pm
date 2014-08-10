use strict;
use warnings;

package Scrooge::Numeric;
use Carp;

sub parse_range_string_pair {
	my ($class, $range_string) = @_;
	
	croak("No range string") if not $range_string;
	
	# Make sure we have the delimiters, separated by a comma
	my @items = split /([()\[\],])/, $range_string;
	# First thing (before the opening bracket) is empty, so shift it off
	shift @items;
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

my $matches_unsigned_float = qr/[0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?/;
sub parse_range_string {
	my $original = my $string = $_[1];
	my $spec = {};
	
	# Handle initial whitespace and/or sign
	my $sign;
	my $extract_sign = sub {
		undef($sign);
		# Strip initial whitespace
		$string =~ s/^\s+//;
		if ($string =~ s/^\+\s*//) {
			# positive sign
			$sign = +1;
		}
		elsif ($string =~ s/^-\s*//) {
			# negative sign
			$sign = -1;
		}
	};
	$extract_sign->();
	$sign ||= +1;
	
	# Strip off pieces one at a time
	while($string) {
		# Looks like it starts with a float?
		if ($string =~ s/^($matches_unsigned_float)//) {
			my $float = $sign * $1;
			
			# Check for bad suffixes
			if ($string =~ /^([\@mMxX])/) {
				croak("Cannot use `$1' as a suffix in range string");
			}
			elsif ($string =~ /^inf/) {
				croak("Cannot use `inf' as a suffix in range string");
			}
			
			# Check for allowed suffixes
			if ($string =~ s/^\$//) {
				$spec->{stdev} += $float;
			}
			# percentage range
			elsif ($string =~ s/^%//) {
				$spec->{pct} += $float
			}
			# normal number (no suffix)
			elsif ($string =~ s/^(?=\s*[+-]|$)//) {
				$spec->{raw} += $float;
			}
			else {
				croak("Unable to parse range string starting at `$string'");
			}
		}
		# average, min, max, inf
		elsif ($string =~ s/^([\@mMxX]|inf)//) {
			$spec->{$1} += $sign;
		}
		# standard deviation
		elsif ($string =~ s/^\$//) {
			$spec->{stdev} += $sign;
		}
		else {
			croak("Unable to parse range string starting at `$string'");
		}
		
		# Look for next operator
		$extract_sign->();
		
		# Croak on trailing operators
		croak("Found trailing `" . ($sign > 0 ? '+' : '-')
			. "' in range string") if $sign and not $string;
		
		# Croak on no operators but more material
		croak("Operator expected in range string starting at `$string'")
			if $string and not $sign;
	}
	return $spec;
}
