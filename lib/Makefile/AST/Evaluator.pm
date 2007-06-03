package Makefile::AST::Evaluator;

use strict;
use warnings;

#use Smart::Comments;
my $Parent;
our %Required;

sub new ($$) {
    my $class = ref $_[0] ? ref shift : shift;
    my $ast = shift;
    return bless {
        ast     => $ast,
        updated => {},
    }, $class;
}

sub ast ($) { $_[0]->{ast} }

sub mark_as_updated ($$) {
    my ($self, $target) = @_;
    $self->{updated}->{$target} = 1;
}

sub is_updated ($$) {
    my ($self, $target) = @_;
    $self->{updated}->{$target};
}

sub make ($$) {
    my ($self, $target) = @_;
    my $retval;
    my @rules = $self->ast->apply_explicit_rules($target);
    ### @rules
    for my $rule (@rules) {
        if (! @{ $rule->commands }) {
            $retval = $self->make_implicitly($target);
        } else {
            $retval = $self->make_by_rule($target => $rule);
        }
    }
    return $retval;
}

sub make_implicitly ($$) {
    my ($self, $target) = @_;
    my $rule = $self->ast->apply_implicit_rules($target);
    my $retval = $self->make_by_rule($target => $rule);
    if ($retval eq 'REBUILT') {
        for my $target ($rule->other_targets) {
            $self->mark_as_updated($target);
        }
    }
    return $retval;
}

sub make_by_rule ($$$) {
    my ($self, $goal, $rule) = @_;
    ### make by rule: $rule
    return 'REBUILT' if $self->is_updated($goal);
    if (!$rule) {
        if (-f $goal) {
            return 'UP_TO_DATE';
        } else {
            if ($Required{$goal}) {
                my $msg =
                    "$0: *** No rule to make target `$goal'";
                if (defined $Parent) {
                    $msg .=
                        ", needed by `$Parent'";
                }
                die "$msg.  Stop.\n";
            } else {
                return 'UP_TO_DATE';
            }
        }
    }
    my $out_of_date = !-f $goal;
    $Parent = $goal;
    for my $prereq (@{ $rule->normal_prereqs }) {
        # XXX handle order-only prepreqs here
        $Required{$prereq} = 1;
        my $res = $self->make($prereq);
        if ($res eq 'REBUILT') {
            $out_of_date = 1;
        } elsif ($res eq 'UP_TO_DATE') {
            if (!$out_of_date) {
                if (-M $prereq < -M $goal) {
                    ### prereq file is newer: $prereq
                    $out_of_date = 1;
                }
            }
        } else {
            die "Unexpected returned value: $res";
        }
    }
    if ($out_of_date) {
        $rule->run_commands($self->ast);
        $self->mark_as_updated($rule->target);
        return 'REBUILT';
    }
    return 'UP_TO_DATE';
}

1;
