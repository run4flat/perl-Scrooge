###########################################################################
#                        Scrooge::Test::Tracker                        #
###########################################################################

# Provides a way to install functions into a package that tracks the
# function call order and croaking behavior, and preserving the calling
# context. It stores the resulting call order in the package global
# @call_structure for easy access, although it is your job to clear that out
# with every test. Also, it imports warnings, strictures, Test::More, and
# Data::Dumper into the calling package to reduce boilerplate.
#
# Importing this module in a way that you can run prove from within the
# testing directory is a little tricky. You should try something like this:
#
# 
#     my $module_name = 'Tracker.pm';
#     if (-f $module_name) {
#         require $module_name;
#     }
#     elsif (-f "t/$module_name") {
#         require "t/$module_name";
#     }
#     elsif (-f "t\\$module_name") {
#         require "t\\$module_name";
#     }
#     else {
#         die "Unable to load $module_name";
#     }
#
# To install trackers, you should have already defined the parent class by
# assigning to @ISA. You then specify the functions that you want tracked:
#
#     package My::Test::Class;
#     our @ISA = ('PDL');
#     Tracker::track( qw(at slice) );
#
# After constructing an object of the new class, you will be able to run
# 'at' and 'slice', and their function calls will be recorded.
#
# Tracked functions always shift off $self from the argument stack. Then,
# they return the result of the following:
#
#     $self->SUPER::<funcname>(@_);
#
# You can provide your own calling code if you do not want the parent
# class's function called. Simply provide a first argument that is an
# anonymous hash with funcname => 'code-string':
#
#     Tracker::track({slice => 'return 0'}, qw(is));
#
#

package Tracker;

use Carp 'croak';
use Data::Dumper;
use strict;
use warnings;

sub track {
	my ($package) = caller(0);
	my $parent_class = eval '$' . $package . '::ISA[0]';
	
	# Basic package setup:
	eval qq{
		package $package;
		warnings->import();
		strict->import();
		Test::More->import();
		Data::Dumper->import();
		PDL->import();
	};
	
	# Unpack any code fragments:
	my %code_fragment_for;
	%code_fragment_for = %{shift @_} if ref ($_[0]) and ref($_[0]) eq 'HASH';
	
	# Run through all the functions
	for my $subname (@_, keys %code_fragment_for) {
		my $code_fragment = $code_fragment_for{$subname}
			|| '$self->SUPER::' . $subname . '(@_)';
		eval qq{
			
			package $package;
			
			sub $subname {
				my \$self = shift;
				
				# Backup the calls:
				my \@copy = our \@call_structure;
				\@call_structure = ();
				
				# Eval the function in the same context as the caller:
				my (\@to_return, \$to_return);
				if (wantarray) {
					\@to_return = eval{$code_fragment};
				}
				elsif (defined wantarray) {
					\$to_return = eval{$code_fragment};
				}
				else {
					eval{$code_fragment};
				}
				
				# Note if we croaked and recroak:
				if (\$@) {
					# Add this function's call entry:
					\@call_structure = (\@copy, -$subname => [\@call_structure]);
					die \$@;
				}
				
				# Otherwise return the result:
				\@call_structure = (\@copy, $subname => [\@call_structure]);
				return \@to_return if wantarray;
				return \$to_return if defined wantarray;
				return;
			}
		};
		# Make sure everything worked correctly:
		croak ("Problem in package $package with code fragment for $subname: $@") if $@;
	}
}

1;
