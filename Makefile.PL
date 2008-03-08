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

build_requires  ('Test::More'      => '0.62');
build_requires  ('IPC::Run3'       => '0.036');
build_requires  ('File::Temp'      => '0.16');
build_requires  ('File::Spec'      => '3.12');
build_requires  ('Cwd'             => '3.12');
build_requiers  ('FindBin'         => '1.47');

use_test_base;

auto_install;
WriteAll;

