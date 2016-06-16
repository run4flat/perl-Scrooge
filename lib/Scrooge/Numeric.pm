use strict;
use warnings;

package Scrooge::Numeric;
use Carp;

sub parse_interval_string {
	my ($class, $interval_string) = @_;
	
	croak("No interval string") if not $interval_string;
	
	# Make sure we have the delimiters, separated by a comma
	my @items = split /([()\[\],])/, $interval_string;
	# First thing (before the opening bracket) is empty, so shift it off
	shift @items;
	croak("Invalid interval `$interval_string'")
		unless @items == 5;
	croak("Interval `$interval_string' does not begin with [ or (")
		unless $items[0] eq '(' or $items[0] eq '[';
	croak("Interval `$interval_string' does not end with ] or )")
		unless $items[4] eq ')' or $items[4] eq ']';
	croak("Interval `$interval_string' does not separate the endpoints with a comma")
		unless $items[2] eq ',';
	
	# Parse what they gave and return a structured hash with the results
	return {
		left_delim  => $items[0],
		left_spec   => $class->parse_endpoint_string($items[1]),
		right_delim => $items[4],
		right_spec  => $class->parse_endpoint_string($items[3]),
	};
}

our %property_descriptions = (
	m     => 'minimum (not including inf)',
	M     => 'maximum (not including inf)',
	x     => 'minimum (possibly including inf)',
	X     => 'maximum (possibly including inf)',
	'@'   => 'average',
	stdev => 'standard deviation',
);

my $matches_unsigned_float = qr/[0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?/;
sub parse_endpoint_string {
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
				croak("Unable to parse endpoint string starting at `$string'");
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
			croak("Unable to parse endpoint string starting at `$string'");
		}
		
		# Look for next operator
		$extract_sign->();
		
		# Croak on trailing operators
		croak("Found trailing `" . ($sign > 0 ? '+' : '-')
			. "' in endpoint string") if $sign and not $string;
		
		# Croak on no operators but more material
		croak("Operator expected in endpoint string starting at `$string'")
			if $string and not $sign;
	}
	return $spec;
}

# Takes an endpoint hashref and a dataset properties hashref, and produces a
# single number representing the endpoint for the given dataset.
sub evaluate_endpoint {
	my ($class, $endpoint, $dataset_properties) = @_;
	
	# Return +-inf if specified
	return $endpoint->{inf} * 'inf' if exists $endpoint->{inf};
	
	# Compute the range, if needed
	my $range = 0;
	if (exists $endpoint->{pct}) {
		croak('endpoint needs the dataset min and max, but m and M are not specified')
			unless exists $dataset_properties->{m}
			and exists $dataset_properties->{M};
		$range = $dataset_properties->{M} - $dataset_properties->{m};
	}
	
	# Compute the endpoint value
	my $value_to_return = 0;
	while (my ($k, $v) = each %$endpoint) {
		# Raw and pct values require special handling
		if ($k eq 'raw') {
			$value_to_return += $v;
		}
		elsif ($k eq 'pct') {
			$value_to_return += $v * $range / 100;
		}
		# All other keys should have associated values in the given
		# dataset properties and can be handled uniformly.
		elsif (exists $property_descriptions{$k}) {
			croak("endpoint needs dataset $property_descriptions{$k}, "
				. "but $k is not specified") if not exists $dataset_properties->{$k};
			$value_to_return += $v * $dataset_properties->{$k};
		}
		else {
			croak("Invalid key in endpoint specification `$k'");
		}
	}
	
	return $value_to_return;
}

# Creates a subref that takes a single scalar and quickly computes if
# the scalar falls within the given range.
use Scalar::Util;
sub build_interval_check_subref {
	my ($class, $interval, $dataset_properties) = @_;
	for my $k (qw(left_delim left_spec right_delim right_spec)) {
		croak("interval does not contain $k") unless exists $interval->{$k};
	}
	# Get the left and right end points
	my $left_spec = $interval->{left_spec};
	croak("left spec of interval is not a hashref")
		unless ref($left_spec) and ref($left_spec) eq ref({});
	my $left = $class->evaluate_endpoint($left_spec, $dataset_properties);
	
	my $right_spec = $interval->{right_spec};
	croak("right spec of interval is not a hashref")
		unless ref($right_spec) and ref($right_spec) eq ref({});
	my $right = $class->evaluate_endpoint($right_spec, $dataset_properties);
	
	# Check the brackets and construct the proper inequality
	my $l_bracket = $interval->{left_delim};
	my $l_eq
		= $l_bracket eq '(' ? '<'
		: $l_bracket eq '[' ? '<='
		: croak("interval has bad left delimiter `$l_bracket'");
	my $r_bracket = $interval->{right_delim};
	my $r_eq
		= $r_bracket eq ')' ? '<'
		: $r_bracket eq ']' ? '<='
		: croak("interval has bad right delimiter `$r_bracket'");
	
	# Create the subref using a strinig evaluation.
	my $subref = eval qq{
#line @{[__LINE__+1, __FILE__]}
		sub {
			my \$value = shift;
			return 0 if not Scalar::Util::looks_like_number(\$value);
			return (\$left $l_eq \$value and \$value $r_eq \$right);
		}
	};
	
	return $subref;
}

1;

__END__

=head1 NAME

Scrooge::Numeric - providing overridable numeric interval parsing methods

=head1 SYNOPSIS

 # Parse an endpoint string
 my $endpoint_struct = Scrooge::Numeric->parse_endpoint_string('5-3$');
 
 $endponit_struct is a hashref with elements:
   raw    => 5
   stdev  => -3
 
 # Parse an interval
 my $interval_struct
   = Scrooge::Numeric->parse_interval_string '[5%, 95% + 3)';
 
 $interval_struct is a hashref with elements
   left_delim => '['
   left_spec => {
       pct => 5
   }
   right_delim => ')'
   right_spec => {
       pct => 95
       raw => 3
   }

=head1 DESCRIPTION

You may want to create a pattern that matches numeric data lying within a
certain interval. I certainly do, and I wanted a flexible scheme for
specifying my intervals. I also wanted to use this scheme for lots of
different kinds of patterns, so I abstracted the interval parsing into its
own module. I also wanted it to be reasonably easy to override, so I
made my parsing functions class methods.

This module provides class methods for parsing interval and endpoint
strings, and class methods for evaluating endpoints and intervals given 
a dataset's properties. C<parse_interval_string> takes an interval string
and returns a hashref with interval delimiters and endpoint hashes.
C<parse_endpoint_string> takes a string that specifies an endpoint and
creates the hash representing that endpoint. C<evaluate_endpoint>
takes an endpoint hashref and a hashref with dataset properties and
numerically evaluates the endpoint. Finally, C<build_interval_check_subref>
takes an interval hashref and a hashref with dataset properties and
returns a curried function that can quickly evaluate if a given scalar
value falls within the given range.

=over

=item parse_interval_string

This class method takes a single string that specifies an interval and returns
a hashref representing the range. The range string uses mathematical interval
notation (which happens to be described by ISO 31-11). Here are some
examples, with the interval described using inequalities on the left, and
interval notation on the right:

 5 <  x <  10      (5, 10)
 5 <= x <  10      [5, 10)
 5 <  x <= 10      (5, 10]
 5 <= x <= 10      [5, 10]

A simple example of use would be

 my $interval = Scrooge::Numeric->parse_interval_string '(5, 10]';

The expected form of the interval string is:

 <bracket> <expression> <comma> <expression> <bracket>.

What constitutes a valid expression is dictated by C<parse_endpoint_string>,
described below.

The returned hashref is suitable for feeding into C<build_interval_check_subref>,
along with a hashref of dataset properties, as described below. If you wish
to inspect the interval yourself, the returned hash has four keys: C<left_spec>,
C<left_delim>, C<right_spec>, and C<right_delim>. The values associated with the
left and right delimiter keys are one-character strings containing the
delimiter bracket. The values associated with left and right specs are
hashrefs dictating the structure of the endpoint, as described in
C<parse_endpoint_string>.

The first bracket must be either C<(> or C<[> while the second bracket
must be eitiher C<)> or C<]>, or this method will croak with one of
these:

 Interval `<interval_string>' does not begin with [ or (
 Interval `<interval_string>' does not end with ] or )

If you do not include the comma, you will get this error message:

 Interval `<interval_string>' does not separate the endpoints with a comma

=item build_interval_check_subref

Creates a subref that can be used to check if a scalar falls within the
specified range. It expects an interval hashref and a hashref describing
the properties of the dataset. The expected keys of the properties hashref
and their interpretation are described below under C<evaluate_endpoint>.
The returned subref evaluates individual scalars and returns a boolean
value that indicates whether or not the scalar falls within the given range.

If your interval does not contain one of the four required keys (as returned
by C<parse_interval_string>), you will get this error message:

 interval does not contain <key>

If your interval does not use a proper left delimiter (it must be either
C<(> or C<[>), you will get an error such as

 interval has bad left delimiter `<left_delim>'

and similar for a bad right delimiter (which must be either C<)> or C<]>).
If you (somehow) pass an interval containing a left or right endpoint
specification, but it is no a hash, you will get an error message such as

 right spec of interval is not a hashref

=item evaluate_endpoint

Takes an endpoint hashref and a hashref of dataset properties and computes
a real number that can be used for numeric comparisons. The expected
dataset properties are:

 x      minimum, possibly including -inf
 X      maximum, possibly including inf
 m      minimum, excluding -inf
 M      maximum, excluding inf
 @      average
 stdev  standard deviation

You will need to compute these values for your given dataset and construct
a hashref with the given keys in order to utilize this function.

Generally, if the endpoint does not use the specified key, you do not
need to include the information in your dataset properties hashref. One
exception is that and endpoint with the C<pct> key needs the C<m> and
C<M> dataset properties to compute the dataset's range. Another exception
is that if the endpoint includes the C<inf> key, it does not pay any
attention to the dataset properties (or any of the other endpoint
properties, for that matter).

If your dataset properties fail to included a key used by the endpoint,
this method will croak saying

 endpoint needs dataset <value> but <key> is not specified

If the endpoint contains an invalid key, this will croak saying

 Invalid key in endpoint specification `<key>'

=item parse_endpoint_string

Takes an endpoint string and produces and endpoint hashref suitable for
use in C<evaluate_endpoint>. The endpoint string is an arithmetic
expression involving addition and subtraction of symbols, raw numbers,
and suffixed numbers. (Multiplication and division is not supported.)

Valid symbols and the dataset property they refer to include

 x    minimum, possibly including -inf
 X    maximum, possibly including inf
 m    minimum, excluding -inf
 M    maximum, excluding inf
 @    average
 inf  infinite (need not be specified)

Valid suffixes include

 %  percent of M - m
 $  standard deviations

Raw numbers are also allowed.

For example, if you wanted an endpoint referring to that is 10% away from
the dataset's minimum (a minimum that might be -inf), you would use
the string C<x + 10%>. If the dataset's true minimum is -inf, then this
evaluates to C<-inf>. Otherwise it gives the same result as C<m + 10%>.
So if your data's minimum was 1 and the maximum was 101, then this should
ultimately resolve to the value 11. As another example, two standard
deviations above the average would be notated as C<@ + 2$>. The maximum
less 7.2 would be notated as C<M - 7.2>.

Note that C<@> refers to the mean, and it is distinct from C<m+50%>,
which is the midpoint of the data's range. There is as yet no notation
for the dataset's median or mode, though I am not opposed to adding such
notation if requested.

Each symbol or suffix is associated with a key in the returned endpoint
hashref. The keys associated with each symbol or suffix include

 input     output
 x         x
 X         X
 m         m
 M         M
 inf       inf
 @         @
 $         stdev
 %         pct
 <number>  raw

So the string C<m + 5% + 2.3$ - 4> results in a hashref with keys

 {
   m     =>  1,
   pct   =>  5,
   stdev =>  2.3,
   raw   => -4,
 }

The I<symbols> listed above are not suffixes, and attempting to use one as
a suffix will give an error:

 Cannot use `<symbol>' as a suffix in range string

You can get around this by having repetitions of the symbol (C<m+m>),
but why would you do that? If your endpoint string has a trailing
operator (either C<+> or C<->), you will get an error like

 Found trailing `+' in endpoint string

and if you use an unknown symbol or suffix, or an unsupported operator,
you will get the error 

 Unable to parse endpoint string starting at `<rest-of-string>'

and if you forget to place an addition or subtraction symbol between two
terms, you will get the error

 Operator expected in endpoint string starting at `<rest-of-string>'

=back

=cut
