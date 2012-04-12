use ExtUtils::MakeMaker;
use strict;
use warnings;
use PDL::Core::Dev;
use Config;

my $pack = [qw(MSER.pm.PL MSER PDL::Regex::MSER)];
my %hash = pdlpp_stdargs($pack);

$hash{VERSION_FROM}="Regex.pm";

## Required for Perl 5.14.1 ##
$hash{CCFLAGS} .= $Config{ccflags};

# Make it install my module files:
#$hash{PM} = {
#	'Regex.pm'	=> 'blib/lib/PDL/Regex.pm',
#	'
#};

WriteMakefile(%hash);

sub MY::postamble {
	pdlpp_postamble($pack);
}



__END__


# These are lifted from PDL::Core::Dev, but use a less redundant style:
my $inc = join(' ', PDL_INCLUDE, ($PDL::Config{MALLOCDBG}->{include} || ()));
my $libs = [$PDL::Config{MALLOCDBG}->{libs} || ()];

WriteMakefile(
    NAME            => 'PDL::Regex',
    VERSION_FROM    => 'Regex.pm',
    PL_FILES        => {'MSER.pm.PL' => [qw(MSER.pm MSER.xs)]},
    INC             => $inc,
    LIBS            => $libs,
);
