=head1 NAME

Scrooge::Grammar - providing an interface for inheritable Scrooge grammars

=head1 SYNOPSIS

 package My::Find::Foo;
 use Scrooge::Grammar; # provides the 'pattern' function, which
                       # builds the closure-based functions
 use Scrooge::Arrays;
 sequential TOP => qw(preface extract_foo);
 simultaneous preface => qw(first second);
 one_of 
 # Scrooge pattern closure: pattern
 # SEQ: sequence, series, chain, run
 # AND: simultaneous, every
 # OR : any, one_of, choose, pick
 pattern preface => scr::arr::seq(
     scr::arr::start,     # anchor at start
     scr::arr::any '10%', # up to the first 10% of the data's length
 );
 pattern extract_foo => scr::arr::interval '[-5, 5]';
 
 __PACKAGE__->check;   # not necessary, but checks that grammar is complete
 __PACKAGE__->cleanup; # cleans up the namespace; call when done
 
 # Now I can match against a data structure
 my $match_info = My::Find::Foo->match($data_structure);
 
 package My::Revised::Foo;
 use Scrooge::Grammars;
 extends 'My::Find::Foo';
 
 # Override foo extraction
 pattern extract_foo => scr::arr::interval '[-10, 10]';
 
 # Match against a data structure with revised foo identification
 my $match_info = My::Revised::Foo->match($data_structure);

=head1 DESCRIPTION

At the moment, this is merely a sketch without an implementation. However,
I think that it is a workable sketch, something that can be implemented and
which will achieve the desired flexibility.

This would work by creating package methods whose sole job is to return a
Scrooge pattern. Thus C<< My::Find::Foo->match >> performs something
roughly equivalent to this:

 sub match {
     my ($grammar, $data) = @_;
     my $TOP = $grammar->TOP();
     return $TOP->match($data);
 }

For example, this line of code:

 sequential peak_with_sides => qw(left peak right);

would create a function with approximately this structure:

 my $peak_with_sides = Scrooge::Grammar::sequence(
  'left', 'peak', 'right', 
 );
 sub peak_with_sides { $peak_with_sides }

During the prep stage, the package of the current grammar and action set
will be part of the match_info. The grammar package will be used to identify
and collect the child patterns. During the apply stage, if a sub-pattern
matches successfully, any actions from the action package that share the
same name will be called.

This allows for grammar inheritance because the function C<peak_with_sides>
can be overridden in child classes!


=cut

1;
