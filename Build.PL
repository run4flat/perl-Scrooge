use Module::Build;
use strict;
use warnings;
use PDL::Core::Dev;

# These are lifted from PDL::Core::Dev, but use a less redundant style:
#my @inc = (PDL_INCLUDE, ($PDL::Config{MALLOCDBG}->{include} || ()) );

my $inc = PDL_INCLUDE;
# Strip off the leading -I:
$inc =~ s/^-I//;

my $build = Module::Build->new(
	module_name => 'PDL::Regex',
	license  => 'perl',
	requires => {
		perl					=> '5.6.1',
		PDL						=> 2,
	},
	needs_compiler => 1,
	PL_files => {
		'lib/PDL/Regex/MSER.pm.PL'
			=> ['lib/PDL/Regex/MSER.xs', 'lib/PDL/Regex/MSER.pm'],
	},
#	include_dirs => \@inc,
	include_dirs => $inc,
#	extra_linker_flags => $PDL::Config{MALLOCDBG}->{libs},
	
);

$build->create_build_script;
