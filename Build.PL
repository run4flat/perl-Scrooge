use Module::Build;
use strict;
use warnings;
use PDL::Core::Dev;

my $inc = PDL_INCLUDE;
# Strip off the leading -I:
$inc =~ s/^-I//;

my $build = Module::Build->new(
	module_name => 'Regex::Engine',
	license  => 'perl',
	requires => {
		perl					=> '5.6.1',
		PDL						=> 2,
	},
	needs_compiler => 1,
	PL_files => {
		'lib/Regex/Engine/MSER.pm.PL'
			=> ['lib/Regex/Engine/MSER.xs', 'lib/Regex/Engine/MSER.pm'],
	},
	include_dirs => $inc,
	
);

$build->create_build_script;
