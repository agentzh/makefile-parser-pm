package Makefile::AST::Evaluator;

use strict;
use warnings;

#use Smart::Comments;
my $Parent;
our %Required;
my %Making;
our ($Quiet, $JustPrint);

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
    ### marking target as updated: $target
    $self->{updated}->{$target} = 1;
}

sub is_updated ($$) {
    my ($self, $target) = @_;
    $self->{updated}->{$target};
}

sub make ($$) {
    my ($self, $target) = @_;
    if ($Making{$target}) {
        warn "$0: Circular $target <- $target ".
            "dependency dropped.\n";
        return 'UP_TO_DATE';
    } else {
        $Making{$target} = 1;
    }
    my $retval;
    my @rules = $self->ast->apply_explicit_rules($target);
    ### number of explicit rules: scalar(@rules)
    if (@rules == 0) {
        delete $Making{$target};
        return $self->make_by_rule($target => undef);
    }
    for my $rule (@rules) {
        my $ret;
        ### explicit rule for: $target
        ### explicit rule: $rule->as_str
        if (!$rule->has_command) {
            ## THERE!!!
            $ret = $self->make_implicitly($target);
            ### make_implicitly returned: $ret
            $retval = $ret if !$retval || $ret eq 'REBUILT';
        }
        # XXX unconditional?
        $ret = $self->make_by_rule($target => $rule);
        ### make_by_rule returned: $ret
        $retval = $ret if !$retval || $ret eq 'REBUILT';
    }
    delete $Making{$target};
    return $retval;
}

sub make_implicitly ($$) {
    my ($self, $target) = @_;
    my $rule = $self->ast->apply_implicit_rules($target);
    if ($rule) {
    ### implicit rule: $rule->as_str
    }
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
    ### make_by_rule: $goal
    return 'UP_TO_DATE'
        if $self->is_updated($goal) and $rule->colon eq ':';
    if (!$rule) {
        ## HERE!
        ## exists? : -f $goal
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
    ### make by rule: $rule->as_str
    my $out_of_date = !-f $goal;
    my $prereq_rebuilt;
    $Parent = $goal;
    for my $prereq (@{ $rule->normal_prereqs }) {
        # XXX handle order-only prepreqs here
        ### processing rereq: $prereq
        $Required{$prereq} = 1;
        my $res = $self->make($prereq);
        ### make returned: $res
        if ($res and $res eq 'REBUILT') {
            $out_of_date++;
            $prereq_rebuilt++;
        } elsif ($res and $res eq 'UP_TO_DATE') {
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
        ### firing rule's commands: $rule->as_str
        $rule->run_commands($self->ast);
        $self->mark_as_updated($rule->target)
            if $rule->colon eq ':';
        return 'REBUILT'
            if $rule->has_command or $prereq_rebuilt;
    }
    return 'UP_TO_DATE';
}

1;
__END__

