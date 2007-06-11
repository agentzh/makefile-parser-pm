use Test::Base;

use File::Slurp;
use IPC::Run3;

plan tests => 2 * blocks();

my $makefile = 'make-simple.mk';

run {
    my $block = shift;
    my $name = $block->name;
    write_file($makefile, $block->in);
    my ($stdout, @goals);
    if ($block->goals) {
        @goals = split /\s+/, $block->goals;
    }
    run3(
        [$^X, 'script/make-simplest', '-f', $makefile, @goals],
        undef,
        \$stdout,
        undef,
    );
    is(($? >> 8), 0, "$name - process returned the 0 status");
    is $stdout, $block->out,
        "$name - script/make-simplest generated the right output";

};

__DATA__

=== TEST 1: basics
--- in

FOO = world
all: ; @ echo hello $(FOO)

--- out
all:
	@echo hello world



=== TEST 2: canned sequence of commands
--- in
define FOO
  @echo
  -touch
  :
endef

all:
	@$(FOO)
--- out
all:
	@echo
	@-touch
	@:



=== TEST 3: double-colon rules
--- in

all: foo

foo:: bar
	@echo $@ $<

foo:: blah blue
	-echo $^
--- out
all: foo

foo:: bar
	@echo foo bar

foo:: blah blue
	-echo blah blue



=== TEST 4: .DEFAUL_GOAL
--- in
.DEFAULT_GOAL = foo

all: foo
	@echo $<

foo: bah ; :


--- out
foo: bah
	:

all: foo
	@echo foo

