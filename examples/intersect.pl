use strict;
use warnings;
use PDL;
use Regex::Engine;


my $data = sin(sequence(100)/10);
$data->slice('37') .= 100;

my ($mean , $std_dev) = $data->stats;

my $regex = re_sub( sub {
    my (undef, $left, $right) = @_;
        # Return undefined so we don't have to deal
    # with zero width assertions
    return '0 but true' if ($left > $right);
    # Should be able to return undef
    
    my $sub_piddle = $data->slice("$left:$right");
    # Return undefined if the match doesn't occur
    # at the given left offset 
    return 0 if ($data->at($left) <= $mean + 2 * $std_dev);
    # Return the length of the whole segment if
    # all of data is outside 2 std. deviations
    # of the mean.
    return ($right - $left +1) 
        if all ( $sub_piddle > $mean + 2 * $std_dev);
    
   # Returns the indices of all values that are
   # greater than 2 std. deviations away from mean
   return which($sub_piddle <= $mean + 2 * $std_dev)->at(0);
});

my ($matched, $offset) = $regex->apply($data);
print "not" if $offset != 37;
print "ok - offset finds crazy value\n";
print "Matched $matched elements, starting from $offset\n";