use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'Wosbee::Admin',
    license             => 'perl',
    dist_author         => q{Henrik Ahlgren <pablo@seestieto.pl>},
    dist_version_from   => 'lib/Wosbee/Admin.pm',
    build_requires => {
        'Test::More' => 0,
        'HTML::TableExtract' => 0,
        'LWP::UserAgent' => 0,
        'Text::CSV::Encoded' => 0
    },
    add_to_cleanup      => [ 'Wosbee-Admin-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
