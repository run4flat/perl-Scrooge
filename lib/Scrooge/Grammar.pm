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

When you say C<use Scrooge::Grammar>, your package gets a handful keywords
that make it easy to declare named patterns that can be overridden in
derived grammars, and which can invoke actions with an associated
action class.

More description will go in here after I've fleshed things out a bit.

IDEA: allow a string SUPER which refers to the parent pattern by the
same name, or a pattern scr::grm::super, which would actually be a simple
placeholder for the grammar's argument list since the grammar would have
to do some machinery behind the scenes.


=cut

package Scrooge::Grammar;
use Scrooge;
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
			my @patterns = $grammar->_assemble_patterns($action_set, @patterns);
			# If the action set knows how to $name, then create a Grammar sequence
			return Scrooge::Grammar::Sequence->new(patterns => \@patterns,
				action_set => $action_set, action => $name)
					if $action_set and $action_set->can($name);
			# Othewise use a usual sequence
			return Scrooge::Sequence->new(patterns => \@patterns);
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
			my @patterns = $grammar->_assemble_patterns($action_set, @patterns);
			# If the action set knows how to $name, then create a Grammar And
			return Scrooge::Grammar::And->new(patterns => \@patterns,
				action_set => $action_set, action => $name)
					if $action_set and $action_set->can($name);
			# Othewise use a usual sequence
			return Scrooge::And->new(patterns => \@patterns);
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
			my @patterns = $grammar->_assemble_patterns($action_set, @patterns);
			# If the action set knows how to $name, then create a Grammar Or
			return Scrooge::Grammar::Or->new(patterns => \@patterns,
				action_set => $action_set, action => $name)
					if $action_set and $action_set->can($name);
			# Othewise use a usual sequence
			return Scrooge::Or->new(patterns => \@patterns);
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
		my $action_name = $self->{action};
		$action_set->$action_name($match_info, $consumed)
			if $action_set->can($action_name);
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
		my $action_name = $self->{action};
		$action_set->$action_name($match_info, $consumed)
			if $action_set->can($action_name);
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
		my $action_name = $self->{action};
		$action_set->$action_name($match_info, $consumed)
			if $action_set->can($action_name);
	}
	return $consumed;
}

1;
