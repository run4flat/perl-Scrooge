use Module::Build;
use strict;
use warnings;

my $build = Module::Build->new(
	module_name => 'Scrooge',
	license  => 'perl',
	requires => {
		perl        => '5.6.1',
		'Safe::Isa' => 1,
		'Sub::Install' => 0.9,
	},
	build_requires => {
		# need 0.94 for subtests
		# need 0.95 for implicit done_testing within subtests
		'Test::More'  => 0.95,
	},
	
);

$build->create_build_script;
