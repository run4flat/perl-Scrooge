use strict;
use warnings;
use Scrooge;

# Role for situations involving more than one data set.
package Scrooge::Role::Subdata;
use Carp;
use Exporter qw( import );
our @EXPORT_OK = qw(_init verify_subdata prep_all_data);

=head2 Scrooge::Role::Subdata

This is not actually a class: it is a role. As a role, it provides methods
that can be used by other classes, but not through inheritance.

Scrooge::Role::Subdata provides the functionality for building a
grouped pattern for which the children patterns get different data subsets.
It provides a C<prep_all_data> method that works properly for named data subsets,
as well as methods to verify the the C<subset_names> key including a stock
C<_init> method. If your class needs to create its own versions of C<_init>
(and therefore cannot import it), you can instead import and use the
C<verify_subdata> method.

To give an idea of just how simple this makes things, the entire
implementation of C<Scrooge::Subdata::Sequence> is this:

 package Scrooge::Subdata::Sequence;
 our @ISA = qw(Scrooge::Sequence);
 Scrooge::Role::Subdata->import qw(_init prep_all_data);

This role provides the following methods, any and all of which can be pulled
into consuming classes:

=over

=item _init

This role method invokes the parent class's C<_init> method followed by
C<Scrooge::Role::Subdata::verify_subdata>. If you do not import this method
into your class, be sure to invoke C<verify_subdata> in your
class's C<_init> method.

=cut

sub _init {
	my $self = shift;
	
	# Find the first base class with an _init method and invoke it
	no strict 'refs';
	my $class = ref($self);
	my $isa = $class . '::ISA';
	for my $base_class (@$isa) {
		if (my $subref = $base_class->can('_init')) {
			$subref->($self);
			last;
		}
	}
	
	# Invoke this role's data verification method
	Scrooge::Role::Subdata::verify_subdata($self);
}

=item verify_subdata

This role method performs a basic verification of the internal keys needed
for the C<prep_all_data> method to function. It is meant to be invoked during a
consuming class's initialization, after the C<_init> method of
L<Scrooge::Grouped> has been run. It can croak for one of two reasons:

 Subset patterns must supply subset_names

means you did not provide a collection of subset names to the pattern
constructor, and

 Number of subset names must equal the number of patterns

means you provided a list of subset names, but that list does not have the
same length as the actual number of patterns.

=cut

sub verify_subdata {
	my $self = shift;
	# Make sure user supplied subset_names
	croak("Subset patterns must supply subset_names")
		unless defined $self-> { subset_names };
	# number of subset_names == number of patterns
	croak("Number of subset names must equal the number of patterns")
		unless @{ $self-> { subset_names }} == @{ $self-> { patterns }};
}


=item prep_all_data

The C<prep_all_data> method of Scrooge::Grouped prepares each child pattern with
the same dataset before invoking the C<prep> method on each of them. This role
changes that behavior and prepares each child pattern with differet datasets
based on the tag associated with that pattern, and the data associated with
that tag.

=cut

# Should only need to override _prep_all_data
sub prep_all_data {
	my $self = shift;
	my $data = $self->data;
	
	# Call the prep function for each of them, keeping track of all those
	# that succeed. Notice that I capture errors and continue because every
	# single pattern needs to run its prep method in order for it to be 
	# safe for it to call its cleanup method.
	my @succeeded;
	my @cache_keys;
	my @patterns = @{ $self->{ patterns }};
	my @subset_names = @{ $self->{ subset_names }};
	for my $i (0..$#patterns) {
		# Make sure we have a valid name:
		croak("Subset name $subset_names[$i] not found")
			unless exists $data-> { $subset_names[$i] };
		
		my $cache_key = $patterns[$i]->add_data($data->{$subset_names[$i]});
		my $successful_prep = $patterns[$i]->prep_data;
		
		# Make sure the min size is not too large:
		if ($successful_prep) {
			if ($patterns[$i]->min_size <= Scrooge::data_length($data)
			) {
				push @succeeded, $patterns[$i];
				push @cache_keys, $cache_key;
			}
		}
	}
	
	return \@succeeded, \@cache_keys;
}

package Scrooge::Subdata::Sequence;
our @ISA = qw(Scrooge::Sequence);
Scrooge::Role::Subdata->import (qw(_init prep_all_data));

package Scrooge::Subdata::And;
our @ISA = qw(Scrooge::And);
Scrooge::Role::Subdata->import (qw(_init prep_all_data));

package Scrooge::Subdata::Or;
our @ISA = qw(Scrooge::Or);
Scrooge::Role::Subdata->import (qw(_init prep_all_data));

=head2 Scrooge::Subdata::Or

=head2 Scrooge::Subdata::And

=head2 Scrooge::Subdata::Sequence

These classes subclass L</Scrooge::Or>, L</Scrooge::And>, and
L</Scrooge::Sequence> and mix-in the L</Scrooge::Role::Subdata> role. The
difference between these classes and their parent classes is that they use
the C<prep_all_data> and C<_init> methods from C<Scrooge::Role::Subdata>.

=cut

