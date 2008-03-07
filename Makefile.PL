use strict;
use lib '.';
use inc::Module::Install;

name            ('Makefile-Parser');
perl_version    ('5.004');
all_from        ('lib/Makefile/Parser.pm');

install_script  ('script/plmake');
install_script  ('script/pgmake-db');
install_script  ('script/makesimple');

requires        ('Text::Balanced');
requires        ('List::Util');
requires        ('List::MoreUtils');
requires        ('File::Spec');
requires        ('Class::Accessor::Fast');
requires        ('Cwd');
requires        ('Makefile::DOM' => '0.001');

use_test_base;

auto_install;
WriteAll;

