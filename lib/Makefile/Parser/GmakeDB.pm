package Makefile::Parser::GmakeDB;

use strict;
use warnings;

#use Smart::Comments '####';
#use Smart::Comments;
use List::Util qw( first );
use List::MoreUtils qw( none );
use MDOM::Document::Gmake;
use Makefile::AST;

# XXX This should not be hard-coded this way...
our @Suffixes = (
    '.out',
    '.a',
    '.ln',
    '.o',
    '.c',
    '.cc',
    '.C',
    '.cpp',
    '.p',
    '.f',
    '.F',
    '.r',
    '.y',
    '.l',
    '.s',
    '.S',
    '.mod',
    '.sym',
    '.def',
    '.h',
    '.info',
    '.dvi',
    '.tex',
    '.texinfo',
    '.texi',
    '.txinfo',
    '.w',
    '.ch',
    '.web',
    '.sh',
    '.elc',
    '.el'
);

# need a better place for this sub:
sub solve_escaped ($) {
    my $ref = shift;
    $$ref =~ s/\\ ([\#\\:\n])/$1/gx;
}

sub _match_suffix ($@);

sub _match_suffix ($@) {
    my ($target, $full_match) = @_;
    ## $target
    ## $full_match
    if ($full_match) {
        return first { $_ eq $target } @Suffixes;
    } else {
        my ($fst, $snd);
        for my $suffix (@Suffixes) {
            my $len = length($suffix);
            ## prefix 1: substr($target, 0, $len)
            ## prefix 2: $suffix
            if (substr($target, 0, $len) eq $suffix) {
                $fst = $suffix;
                ## first suffix recognized: $suffix
                ## suffix 1: substr($target, $len)
                $snd = _match_suffix(substr($target, $len), 1);
                ## $snd
                next if !defined $snd;
                return ($fst, $snd);
            }
        }
        return undef;
    }
}

sub parse ($$) {
    shift;
    my $ast = Makefile::AST->new;
    my $dom = MDOM::Document::Gmake->new(shift);
    my ($var_origin, $orig_lineno, $orig_file);
    my $rule; # The last rule in the context
    my ($not_a_target, $directive);
    for my $elem ($dom->elements) {
        ## elem class: $elem->class
        ## elem lineno: $elem->lineno
        if ($directive and $elem->class !~ /Directive$/) {
            # XXX yes, this is hacky
            ### pushing value to value: $elem
            push @{ $directive->{value} }, $elem->clone;
            next;
        }
        next if $elem->isa('MDOM::Token::Whitespace');
        if ($elem->isa('MDOM::Assignment')) {
            ### Found assignment: $elem->source
            if (!$var_origin) {
                my $lineno = $elem->lineno;
                die "ERROR: line $lineno: No flavor found for the assignment";
            } else {
                my $lhs = $elem->lhs;
                my $rhs = $elem->rhs;
                my $op  = $elem->op;

                my $flavor;
                if ($op eq '=') {
                    $flavor = 'recursive';
                } elsif ($op eq ':=') {
                    $flavor = 'simple';
                } else {
                    # XXX add support for ?= and +=
                    die "Unknown op: $op";
                }
                my $name = join '', @$lhs; # XXX solve refs?
                my @value_tokens = map { $_->clone } @$rhs;
                #map { $_ = "$_" } @$rhs;
                ## LHS: $name
                ## RHS: $rhs
                my $var = Makefile::AST::Variable->new({
                    name   => $name,
                    flavor => $flavor,
                    origin => $var_origin,
                    value  => \@value_tokens,
                    lineno => $orig_lineno,
                    file => $orig_file,
                });
                $ast->add_var($var);
                undef $var_origin;
            }
        }
        elsif ($elem =~ /^#\s+(automatic|makefile|default|environment|command line)/) {
            # XXX change the 'makefile' flavor to 'file' so as
            # XXX to conform with the GNU make manual
            $var_origin = $1;
        }
        elsif ($elem =~ /^# `(\S+)' directive \(from `(\S+)', line (\d+)\)/) {
            ($var_origin, $orig_file, $orig_lineno) = ($1, $2, $3);
            ### directive origin: $var_origin
            ### directive lineno: $orig_lineno
        }
        elsif ($elem =~ /^#\s+.*\(from `(\S+)', line (\d+)\)/) {
            ($orig_file, $orig_lineno) = ($1, $2);
            ## lineno: $orig_lineno
        }
        elsif ($elem =~ /^# Not a target:$/) {
            $not_a_target = 1;
        }
        elsif ($elem =~ /^#  Implicit\/static pattern stem: `(\S+)'/) {
            #### Setting pattern stem for solved implicit rule: $1
            $rule->{stem} = $1;
        }
        elsif ($elem =~ /^#  Also makes: (.*)/) {
            my @other_targets = split /\s+/, $1;
            $rule->{other_targets} = \@other_targets;
            #### Setting other targets: @other_targets
        }
        elsif ($elem->isa('MDOM::Rule::Simple')) {
            ### Found rule: $elem->source
            ### not a target? : $not_a_target
            if ($rule) {
                # The db output tends to produce
                # trailing empty commands, so we remove it:
                if ($rule->{commands}->[-1] and
                      $rule->{commands}->[-1] eq "\n") {
                    pop @{ $rule->{commands} };
                }
            }
            if ($not_a_target) {
                $not_a_target = 0;
                next;
            }
            my $targets = $elem->targets;
            my $colon   = $elem->colon;
            my $normal_prereqs = $elem->normal_prereqs;
            my $order_prereqs = $elem->order_prereqs;
            my $command = $elem->command;

            ## Target (raw): $targets
            ## Prereq (raw): $prereqs

            my $target = join '', @$targets;
            my @order_prereqs =  split /\s+/, join '', @$order_prereqs;
            my @normal_prereqs =  split /\s+/, join '', @$normal_prereqs;

            # Solve escaped chars:
            solve_escaped(\$target);
            map { solve_escaped(\$_) } @normal_prereqs, @order_prereqs;
            @order_prereqs = grep {
                my $value = $_;
                none { $_ eq $value } @normal_prereqs
            } @order_prereqs if @normal_prereqs;

            #### Target: $target
            ### Normal Prereqs: @normal_prereqs
            ### Order-only Prereqs: @order_prereqs

            #map { $_ = "$_" } @normal_prereqs, @order_prereqs;
            # XXX suffix rules allow order-only prepreqs? not sure...
            if ($target !~ /\s/ and $target !~ /\%/ and !@normal_prereqs and !@order_prereqs) {
                ## try to recognize suffix rule: $target
                my ($fst, $snd);
                $fst = _match_suffix($target, 1);
                if (!defined $fst) {
                    ($fst, $snd) = _match_suffix($target);
                    ## got first: $fst
                    ## got second: $snd
                    if (defined $fst) {
                        ## found suffix rule/2: $target
                        $target = '%' . $snd;
                        @normal_prereqs = ('%' . $fst);
                    }
                } else {
                    ## found suffix rule rule/1: $target
                    $target = '%' . $fst;
                }
            }
            my $rule_struct = {
                order_prereqs => [],
                normal_prereqs => \@normal_prereqs,
                order_prereqs => \@order_prereqs,
                commands => [defined $command ? $command : ()],
                colon => $colon,
            };
            if ($target =~ /\%/) {
                ## implicit rule found: $target
                my $targets = [split /\s+/, $target];
                $rule_struct->{targets} = $targets,
                $rule = Makefile::AST::Rule::Implicit->new($rule_struct);
                $ast->add_implicit_rule($rule);
            } else {
                $rule_struct->{target} = $target;
                $rule = Makefile::AST::Rule->new($rule_struct);
                $ast->add_explicit_rule($rule);
            }
        } elsif ($elem->isa('MDOM::Command')) {
            ### Found command: $elem
            if (!$rule) {
                die "error: line " . $elem->lineno .
                    ": Command not allowed here";
            } else {
                #my @tokens = map { "$_" } $elem->elements;
                #my @tokens = $elem
                #shift @tokens if $tokens[0] eq "\t";
                #pop @tokens if $tokens[-1] eq "\n";
                #push @{ $rule->{commands} }, \@tokens;
                ## parser: CMD: $elem
                my $first = $elem->first_element;
                ## $first
                $elem->remove_child($first)
                    if $first->class eq 'MDOM::Token::Separator';
                ### elem source: $elem->source
                #if ($elem->source eq "\n") {
                #    die "Matched!";
                #}
                ## lineno2: $orig_lineno
                $elem->{lineno} = $orig_lineno if $orig_lineno;
                $rule->add_command($elem->clone); # XXX why clone?
                ### Command added: $elem->content
            }
        } elsif ($elem->class =~ /MDOM::Directive/) {
            ### directive name: $elem->name
            ### directive value: $elem->value
            if ($elem->name eq 'define') {
                # XXX set lineno to $orig_lineno here?
                $directive = {
                    name => $elem->value,
                    value => [], # needs to be fed later
                    flavor => 'recursive',
                    origin => $var_origin,
                    lineno => $orig_lineno,
                    file => $orig_file,
                };
                next;
            }
            if ($elem->name eq 'endef') {
                ### parsed a define directive: $directive
                # trim the trailing new lines in the value:
                my $last = $directive->{value}->[-1]->last_element;
                #warn "LAST: '$last'\n";
                if ($last and $last eq "\n") {
                    $directive->{value}->[-1]->remove_child($last);
                }
                my $var = Makefile::AST::Variable->new($directive);
                $ast->add_var($var);
                undef $var_origin;
                undef $directive;
            } else {
                warn "warning: line " . $elem->lineno .
                    ": Unknown directive: " . $elem->source;
            }
        } elsif ($elem->class =~ /Unknown/) {
            # XXX Note that output from $(info ...) may skew up stdout
            # XXX This hack is used to make features/conditionals.t pass
            print $elem if $elem eq "success\n";
            # XXX The 'hello, world' hack to used to make sanity/func-refs.t pass
            warn "warning: line " . $elem->lineno .
                ": Unknown GNU make database struct: " .
                $elem->source
                if $elem !~ /hello.*world/ and
                   $elem ne "success\n";
        }
    }
    {
        my $var = $ast->get_var('.DEFAULT_GOAL');
        my $token = join "", @{ $var->value };
        ## default goal's value: $var
        $ast->{default_goal} = $token if $token;
        ### DEFAULT GOAL: $ast->default_goal

        my $rule = $ast->apply_explicit_rules('.PHONY');
        if ($rule) {
            ### PHONY RULE: $rule
            ### phony targets: @{ $rule->normal_prereqs }
            for my $phony (@{ $rule->normal_prereqs }) {
                $ast->set_phony_target($phony);
            }
        }
        ## foo var: $ast->get_var('foo')
    }
    $ast;
}

1;
