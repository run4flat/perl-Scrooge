=head1 NAME

Scrooge::Grammar - providing an interface for inheritable Scrooge grammars

=head1 SYNOPSIS

 package My::Find::Foo;
 use Scrooge::Grammar;
 
 SEQ TOP => qw(alpha beta);       # alpha then beta
 AND preface => qw(first second); # first and second
 OR choice => qw(foo bar);        # foo or bar
 
 # Now I can match against a data structure
 my $match_info = My::Find::Foo->match($data_structure, 'My::Actions');
 
 package My::Revised::Foo;
 use Scrooge::Grammar;
 our @ISA = 'My::Find::Foo';
 
 # Override foo extraction
 pattern extract_foo => scr::arr::interval '[-10, 10]';
 
 # Match against a data structure with revised foo identification
 my $match_info = My::Revised::Foo->match($data_structure, 'My::Actions');

=head1 DESCRIPTION

Scrooge patterns can be powerful, but they become unweildy for complex
patterns. If you find yourself running into any of the problems listed
below, you should consider using C<Scrooge::Grammar> to build your
complex grammars. C<Scrooge::Grammar> uses Perl packages to create named
patterns and subpatterns. C<Scrooge::Grammar> uses package inheritance
to allow you to create a new grammar from an existing grammar, and then
to override named subpatterns. C<Scrooge::Grammar> even lets you specify
separate packages with actions that get invoked when named patterns are
matched. This lets you destructure complex data in different ways using
the same grammar, but distinct action sets.

Why not just use a complex Scrooge pattern? Writing a test suite for a
complex pattern is difficult since you need to provide a way for your
test suite to get an exact copy of your pattern. Testing subpatterns in
isolation is even more difficult. If you want to have two similar
complex patterns that differ only in a subpattern definition, you need
to build an entirely new pattern, and testing this is also difficult and
repetitive. If you want to have two similar patterns that match
identical data structures but destructures the data differently, you
need to create whole new patterns. And finally, the naive way of
building patterns of increasing complexity is to try to "scale-up" the
simple way: deeply nested function calls and data structures, or forward
declarations. C<Scrooge::Grammar> provides an architecture to easily
solve all of these problems.

When you say C<use Scrooge::Grammar>, your package gets a handful keywords
that make it easy to declare named patterns that can be overridden in
derived grammars, and which can invoke actions with an associated
action class. The main keywords are C<SEQ>, C<AND>, and C<OR>. Each of
these take a pattern name followed by a collection of pattern names and/or
Scrooge pattern objects.

=head1 ISSUES AND IDEAS

=over

=item IDEA

Allow a string SUPER, or similar, which refers to the parent pattern by
the same name.

=item IDEA

Provide keywords such as C<extends> to indicate inheritance. Provide
pattern modifiers akin to Moose's C<around>, etc.

=item IDEA

Use Class::MOP to implement all of this in a cleaner way?

=item ISSUE

Even after a switch to Sub::Exporter, Scrooge pattern generators are
going to import methods into the current package. These need to be
cleaned out of the grammar during some sort of package finalization
step, akin to namespace::clean.

=cut

package Scrooge::Grammar;
use Scrooge ();
use strict;
use warnings;
use Sub::Install;

sub import {
	my ($self_class, @args) = @_;
	my ($package) = caller;
	
	# Install the DSL for creating Scrooge grammars
	Sub::Install::install_sub({
		code => \&SEQ,
		into => $package,
		as   => 'SEQ',
	});
	Sub::Install::install_sub({
		code => \&AND,
		into => $package,
		as   => 'AND',
	});
	Sub::Install::install_sub({
		code => \&OR,
		into => $package,
		as   => 'OR',
	});
	{
		no strict 'refs';
		push @{$package . '::ISA'}, 'Scrooge::Grammar::Base';
	}
}

# Create a new sequence rule under the given name
sub SEQ {
	my ($name, @patterns) = @_;
	my ($package) = caller;
	Sub::Install::install_sub({
		code => sub {
			my ($grammar, $action_set) = @_;
			croak($package . '::' . "$name must be invoked as a package method")
				if not defined $grammar;
			my @patterns = $grammar->_assemble_patterns($action_set, @patterns);
			# If the action set knows how to $name, then create a Grammar sequence
			return Scrooge::Grammar::Sequence->new(patterns => \@patterns,
				action_set => $action_set, name => $name)
					if $action_set and $action_set->can($name);
			# Othewise use a usual sequence
			return Scrooge::Sequence->new(name => $name, patterns => \@patterns);
		},
		into => $package,
		as   => $name,
	});
}

# Create a new "and" rule under the given name
sub AND {
	my ($name, @patterns) = @_;
	my ($package) = caller;
	Sub::Install::install_sub({
		code => sub {
			my ($grammar, $action_set) = @_;
			croak($package . '::' . "$name must be invoked as a package method")
				if not defined $grammar;
			my @patterns = $grammar->_assemble_patterns($action_set, @patterns);
			# If the action set knows how to $name, then create a Grammar And
			return Scrooge::Grammar::And->new(patterns => \@patterns,
				action_set => $action_set, name => $name)
					if $action_set and $action_set->can($name);
			# Othewise use a usual sequence
			return Scrooge::And->new(name => $name, patterns => \@patterns);
		},
		into => $package,
		as   => $name,
	});
}

# Create a new "or" rule under the given name
sub OR {
	my ($name, @patterns) = @_;
	my ($package) = caller;
	Sub::Install::install_sub({
		code => sub {
			my ($grammar, $action_set) = @_;
			croak($package . '::' . "$name must be invoked as a package method")
				if not defined $grammar;
			my @patterns = $grammar->_assemble_patterns($action_set, @patterns);
			# If the action set knows how to $name, then create a Grammar Or
			return Scrooge::Grammar::Or->new(patterns => \@patterns,
				action_set => $action_set, name => $name)
					if $action_set and $action_set->can($name);
			# Othewise use a usual sequence
			return Scrooge::Or->new(name => $name, patterns => \@patterns);
		},
		into => $package,
		as   => $name,
	});
}

# The base class for all grammars (not grammar patterns; those are below)
package Scrooge::Grammar::Base;
use Carp;
use Safe::Isa;

# default match class method
sub match {
	my ($grammar, $data, $action_set) = @_;
	my $pattern = $grammar->TOP($action_set);
	
	return $pattern->match($data);
}

# Default TOP pattern croaks: they need to supply this
sub TOP {
	my $grammar = shift;
	croak("Grammar $grammar does not provide a TOP pattern");
}

# _assemble_patterns calls named patterns and returns a list of bona-fide
# Scrooge patterns that can be wrapped in the appropriate container class.
sub _assemble_patterns {
	my ($grammar, $action_set, @patterns) = @_;
	my @to_return;
	for my $pattern (@patterns) {
		if (defined $pattern and not ref($pattern)) {
			if ($grammar->can($pattern)) {
				push @to_return, $grammar->$pattern($action_set);
			}
			else {
				croak("Grammar $grammar does not have named pattern $pattern");
			}
		}
		elsif ($pattern->$_isa('Scrooge')) {
			push @to_return, $pattern;
		}
		else {
			croak("Bad pattern $pattern");
		}
	}
	return @to_return;
}

package Scrooge::Grammar::Sequence;
our @ISA = qw(Scrooge::Sequence);
sub apply {
	my ($self, $match_info) = @_;
	my $consumed = $self->SUPER::apply($match_info);
	if ($consumed) {
		my $action_set = $self->{action_set};
		my $name = $self->{name};
		$action_set->$name($match_info, $consumed)
			if $action_set->can($name);
	}
	return $consumed;
}

package Scrooge::Grammar::And;
our @ISA = qw(Scrooge::And);
sub apply {
	my ($self, $match_info) = @_;
	my $consumed = $self->SUPER::apply($match_info);
	if ($consumed) {
		my $action_set = $self->{action_set};
		my $name = $self->{name};
		$action_set->$name($match_info, $consumed)
			if $action_set->can($name);
	}
	return $consumed;
}

package Scrooge::Grammar::Or;
our @ISA = qw(Scrooge::Or);
sub apply {
	my ($self, $match_info) = @_;
	my $consumed = $self->SUPER::apply($match_info);
	if ($consumed) {
		my $action_set = $self->{action_set};
		my $name = $self->{name};
		$action_set->$name($match_info, $consumed)
			if $action_set->can($name);
	}
	return $consumed;
}

1;
