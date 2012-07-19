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
	build_requires => {
		'Test::More'  => 0.88,
	},
	needs_compiler => 1,
	include_dirs => $inc,
	
);

$build->create_build_script;
