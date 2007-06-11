package Makefile::AST::Evaluator;

use strict;
use warnings;

#use Smart::Comments;
#use Smart::Comments '####';
use File::stat;
use Class::Trigger qw(firing_rule);

# XXX put these globals to some better place
our (
    $Quiet, $JustPrint, $IgnoreErrors,
    $AlwaysMake, $Question);

sub new ($$) {
    my $class = ref $_[0] ? ref shift : shift;
    my $ast = shift;
    return bless {
        ast     => $ast,
        updated => {},
        mtime_cache => {},  # this is better for the AST?
        parent_target => undef,
        targets_making => {},
        required_targets => {},
    }, $class;
}

sub ast ($) { $_[0]->{ast} }

sub mark_as_updated ($$) {
    my ($self, $target) = @_;
    ### marking target as updated: $target
    $self->{updated}->{$target} = 1;
}

# XXX this should be moved to the AST
sub is_updated ($$) {
    my ($self, $target) = @_;
    $self->{updated}->{$target};
}

# update the mtime cache with -M $file
sub update_mtime ($$@) {
    my ($self, $file, $cache) = @_;
    $cache ||= $self->{mtime_cache};
    if (-e $file) {
        my $stat = stat $file or
            die "$::MAKE: *** stat failed on $file: $!\n";
        ### set mtime for file: $file
        ### mtime: $stat->mtime
        return ($cache->{$file} = $stat->mtime);
    } else {
        ## file not found: $file
        return ($cache->{$file} = undef);
    }
}

# get -M $file from cache (if any) or set the cache
#  key-value pair otherwise
sub get_mtime ($$) {
    my ($self, $file) = @_;
    my $cache = $self->{mtime_cache};
    if (!exists $cache->{$file}) {
        # set the cache
        return $self->update_mtime($file, $cache);
    }
    return $cache->{$file};
}

sub set_required_target ($$) {
    my ($self, $target) = @_;
    $self->{required_targets}->{$target} = 1;
}

sub is_required_target ($$) {
    my ($self, $target) = @_;
    $self->{required_targets}->{$target};
}

sub make ($$) {
    my ($self, $target) = @_;
    return 'UP_TO_DATE'
        if $self->is_updated($target);
    my $making = $self->{targets_making};
    if ($making->{$target}) {
        warn "$::MAKE: Circular $target <- $target ".
            "dependency dropped.\n";
        return 'UP_TO_DATE';
    } else {
        $making->{$target} = 1;
    }
    my $retval;
    my @rules = $self->ast->apply_explicit_rules($target);
    ### number of explicit rules: scalar(@rules)
    if (@rules == 0) {
        ### no rule matched the target: $target
        ### trying to make implicitly here...
        my $ret = $self->make_implicitly($target);
        delete $making->{$target};
        if (!$ret) {
            return $self->make_by_rule($target => undef);
        } else {
            return $ret;
        }
    }
    # run the double-colon rules serially or run the
    # single matched single-colon rule:
    for my $rule (@rules) {
        my $ret;
        ### explicit rule for: $target
        ### explicit rule: $rule->as_str
        if (!$rule->has_command) { # XXX is this really necessary?
            ### The explicit rule has no command, so
            ### trying to make implicitly...
            $ret = $self->make_implicitly($target);
            $retval = $ret if !$retval || $ret eq 'REBUILT';
        }
        $ret = $self->make_by_rule($target => $rule);
        ### make_by_rule returned: $ret
        $retval = $ret if !$retval || $ret eq 'REBUILT';
    }
    delete $making->{$target};

    # postpone the timestamp propagation until all individual
    # rules have been updated:
    $self->update_mtime($target);

    $self->mark_as_updated($target);

    return $retval;
}

sub make_implicitly ($$) {
    my ($self, $target) = @_;
    if ($self->ast->is_phony_target($target)) {
        ### make_implicitly skipped target since it's phony: $target
        return undef;
    }
    my $rule = $self->ast->apply_implicit_rules($target);
    if (!$rule) {
        return undef;
    }
    ### implicit rule: $rule->as_str
    my $retval = $self->make_by_rule($target => $rule);
    if ($retval eq 'REBUILT') {
        for my $target ($rule->other_targets) {
            $self->mark_as_updated($target);
        }
    }
    return $retval;
}

sub make_by_rule ($$$) {
    my ($self, $target, $rule) = @_;
    ### make_by_rule (target): $target
    return 'UP_TO_DATE'
        if $self->is_updated($target) and $rule->colon eq ':';
    # XXX the parent should be passed via arguments or local vars
    my $parent = $self->{parent_target};
    ## Retrieving parent target: $parent
    if (!$rule) {
        ## HERE!
        ## exists? : -f $target
        if (-f $target) {
            return 'UP_TO_DATE';
        } else {
            if ($self->is_required_target($target)) {
                my $msg =
                    "$::MAKE: *** No rule to make target `$target'";
                if (defined $parent) {
                    $msg .=
                        ", needed by `$parent'";
                }
                print STDERR "$msg.";
                if ($Makefile::AST::Runtime) {
                    die "  Stop.\n";
                } else {
                    warn "  Ignored.\n";
                    $self->mark_as_updated($target);
                    return 'UP_TO_DATE';
                }
            } else {
                return 'UP_TO_DATE';
            }
        }
    }
    ### make_by_rule (rule): $rule->as_str
    ### stem: $rule->stem

    # XXX solve pattern-specific variables here...

    # enter pads for target-specific variables:
    # XXX in order to solve '+=' and '?=',
    # XXX we actually should NOT call enter pad
    # XXX directly here...
    my $saved_stack_len = $self->ast->pad_stack_len;
    $self->ast->enter_pad($rule->target);
    ## pad stack: $self->ast->{pad_stack}->[0]

    my $target_mtime = $self->get_mtime($target);
    my $out_of_date =
        $self->ast->is_phony_target($target) ||
        !defined $target_mtime;
    my $prereq_rebuilt;
    ## Setting parent target to: $target
    $self->{parent_target} = $target;
    # process normal prereqs:
    for my $prereq (@{ $rule->normal_prereqs }) {
        # XXX handle order-only prepreqs here
        ### processing prereq: $prereq
        $self->set_required_target($prereq);
        my $res = $self->make($prereq);
        ### make returned: $res
        if ($res and $res eq 'REBUILT') {
            $out_of_date++;
            $prereq_rebuilt++;
        } elsif ($res and $res eq 'UP_TO_DATE') {
            if (!$out_of_date) {
                if ($self->get_mtime($prereq) > $target_mtime) {
                    ### prereq file is newer: $prereq
                    $out_of_date = 1;
                }
            }
        } else {
            die "make_by_rule: Unexpected returned value for prereq $prereq: $res";
        }
    }
    # process order-only prepreqs:
    for my $prereq (@{ $rule->order_prereqs }) {
        ## process order-only prereq: $prereq
        $self->set_required_target($prereq);
        $self->make($prereq);
    }
    $self->{parent_target} = undef;
    if ($AlwaysMake || $out_of_date) {
        my @ast_cmds = $rule->prepare_commands($self->ast);
        $self->call_trigger('firing_rule', $rule, \@ast_cmds);
        if (!$Question) {
            ### firing rule's commands: $rule->as_str
            $rule->run_commands(@ast_cmds);
        }
        $self->mark_as_updated($rule->target)
            if $rule->colon eq ':';
        if (my $others = $rule->other_targets) {
            # mark "other targets" as updated too:
            for my $other (@$others) {
                ### marking "other target" as updated: $other
                $self->mark_as_updated($other);
            }
        }
        $self->ast->leave_pad(
            $self->ast->pad_stack_len - $saved_stack_len
        );
        #### AST Commands: @ast_cmds
        return 'REBUILT'
            if @ast_cmds or $prereq_rebuilt;
    }
    $self->ast->leave_pad(
        $self->ast->pad_stack_len - $saved_stack_len
    );
    return 'UP_TO_DATE';
}

1;
__END__

