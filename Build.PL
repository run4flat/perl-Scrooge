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
		'Test::More'  => 0.88,
	},
	
);

$build->create_build_script;
