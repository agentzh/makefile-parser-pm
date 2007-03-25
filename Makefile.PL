use strict;
use inc::Module::Install;

name            ('Makefile-Parser');
perl_version    ('5.004');
all_from        ('lib/Makefile/Parser.pm');

install_script  ('script/plmake');

requires        ('Text::Balanced');
requires        ('List::Util');
requires        ('List::MoreUtils');
requires        ('File::Spec');
requires        ('Class::Accessor::Fast');
requires        ('Cwd');

use_test_base;

auto_install;
WriteAll;

