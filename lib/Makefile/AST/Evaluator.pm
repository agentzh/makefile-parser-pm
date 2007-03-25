package Makefile::AST::Evaluator;

use strict;
use warnings;
use constant {
    UP_TO_DATE => 1,
    REBUILT    => 2,
};

#use Smart::Comments;

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
    for my $rule (@rules) {
        if (! @{ $rule->commands }) {
            $retval = $self->make_implicitly($target);
        } else {
            $retval = $self->make_by_rule($rule);
        }
    }
    return $retval;
}

sub make_implicitly ($$) {
    my ($self, $target) = @_;
    my $rule = $self->ast->apply_implicit_rules($target);
    my $retval = $self->make_by_rule($rule);
    if ($retval == REBUILT) {
        for my $target ($rule->other_targets) {
            $self->mark_as_updated($target);
        }
    }
    return $retval;
}

sub make_by_rule ($$) {
    my ($self, $rule) = @_;
    ### make by rule: $rule
    my $goal = $rule->target;
    return REBUILT if $self->is_updated($goal);
    if (!$rule) {
        if (-f $goal) {
            return UP_TO_DATE;
        } else {
            die "No rule to build target $goal";
        }
    }
    my $out_of_date = !-f $goal;
    for my $prereq (@{ $rule->normal_prereqs }) {
        # XXX handle order-only prepreqs here
        my $res = $self->make($prereq);
        if ($res == REBUILT) {
            $out_of_date = 1;
        } elsif ($res == UP_TO_DATE) {
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
        return REBUILT;
    }
    return UP_TO_DATE;
}

1;
