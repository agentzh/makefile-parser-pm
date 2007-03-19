use strict;
use inc::Module::Install;

name            ('Makefile-Parser');
perl_version    ('5.004');
all_from        ('lib/Makefile/Parser.pm');

install_script  ('script/plmake');

requires        ('Text::Balanced');
requires        ('List::MoreUtils');
requires        ('File::Spec');
requires        ('Cwd');

build_requires  ('Test::More');

auto_install;
WriteAll;

