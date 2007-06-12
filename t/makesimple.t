use Test::Base;

use File::Slurp;
use IPC::Run3;
use Cwd;

use lib '/home/agentz/mdom-gmake/t/lib';
use Test::Make::Util;

plan tests => 3 * blocks();

my $makefile = 'makesimple.tmp.mk';

my $saved_cwd = cwd;

run {
    my $block = shift;
    my $name = $block->name;
    chdir $saved_cwd;
    system('rm -rf t/tmp');
    system('mkdir t/tmp');
    chdir 't/tmp';
    write_file($makefile, $block->in);
    my ($stdout, $stderr, @goals);
    if ($block->goals) {
        @goals = split /\s+/, $block->goals;
    }
    my $touch = $block->touch;
    if ($touch) {
        for my $file (split /\s+/, $touch) {
            touch($file);
        }
    }
    run3(
        [$^X, "$saved_cwd/script/makesimple", '-f', $makefile, @goals],
        undef,
        \$stdout,
        \$stderr,
    );
    is(($? >> 8), 0, "$name - process returned the 0 status");
    is $stdout, $block->out,
        "$name - script/makesimple generated the right output";
    is $stderr, $block->err,
        "$name - script/makesimple generated the right error";

};

__DATA__

=== TEST 1: basics
--- in

FOO = world
all: ; @ echo hello $(FOO)

--- out
all:
	@echo hello world
--- err



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
--- err



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

--- err
makesimple: *** No rule to make target `bar', needed by `foo'.  Ignored.
makesimple: *** No rule to make target `blah', needed by `foo'.  Ignored.
makesimple: *** No rule to make target `blue', needed by `foo'.  Ignored.



=== TEST 4: double-colon rules (no warnings)
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

--- touch: bar blah blue
--- err



=== TEST 5: .DEFAUL_GOAL
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

--- err
makesimple: *** No rule to make target `bah', needed by `foo'.  Ignored.



=== TEST 6: order-only prereqs
--- in

all : a b \
    | c \
; echo

--- out
all: a b | c
	echo

--- err
makesimple: *** No rule to make target `a', needed by `all'.  Ignored.
makesimple: *** No rule to make target `b', needed by `all'.  Ignored.
makesimple: *** No rule to make target `c', needed by `all'.  Ignored.



=== TEST 7: multi-target rules
--- in
foo bar: a.h

foo: blah ; echo $< > $@

--- out
foo: blah a.h
	echo blah > foo

bar: a.h

--- err
makesimple: *** No rule to make target `blah', needed by `foo'.  Ignored.
makesimple: *** No rule to make target `a.h', needed by `foo'.  Ignored.



=== TEST 8: pattern rules (no match)
--- in
all: foo.x bar.w

%.x: %.h
	touch $@

%.w: %.hpp ; $(CC)

--- out
all: foo.x bar.w

--- err
makesimple: *** No rule to make target `foo.x', needed by `all'.  Ignored.
makesimple: *** No rule to make target `bar.w', needed by `all'.  Ignored.



=== TEST 9: pattern rules (no warnings)
--- in
all: foo.x bar.w

%.x: %.h
	touch $@

%.w: %.hpp ; $(CC)

--- touch: foo.x bar.w
--- out
all: foo.x bar.w

--- err



=== TEST 10: pattern rules (with match)
--- in
all: foo.x bar.w

%.x: %.h
	touch $@

%.w: %.hpp ; echo '$(CC)'

--- touch: foo.h bar.hpp
--- out
all: foo.x bar.w

foo.x: foo.h
	touch foo.x

bar.w: bar.hpp
	echo ''
--- err



=== TEST 11: target-specific variables
--- in

FOO = foo
default: all any
all: FOO += one
all: FOO += two
all: BAR = bar
all: FOO += three
all: BAR += baz
all: ; @echo $(FOO); echo $(BAR)
any: ; @echo $(FOO); echo $(BAR) end

--- out
default: all any

all:
	@echo foo one two three; echo bar baz

any:
	@echo foo; echo  end

--- err



=== TEST 12: ditto (override cmd line vars)
--- in

all: override FOO = foo
all: ; @echo $(FOO)
--- goals:  FOO=cmd
--- out
all:
	@echo foo
--- err



=== TEST 13: ditto (cmd line vars) (2)
--- in

all: FOO = foo
all: ; @echo $(FOO)
--- goals:  FOO=cmd
--- out
all:
	@echo cmd
--- err

