package Makefile::AST::Rule;

use strict;
use warnings;

#use Smart::Comments;
use base 'Makefile::AST::Rule::Base';
use MDOM::Util 'trim_tokens';
use List::MoreUtils;

__PACKAGE__->mk_accessors(qw{
    stem target other_targets
});

# XXX: generate description for the rule
sub as_str ($$) {
    my $self = shift;
    my $order_part = '';
    ### as_str: order_prereqs: $self->order_prereqs
    if (@{ $self->order_prereqs }) {
        $order_part = " | " . join(" ",@{ $self->order_prereqs });
    }
    my $str = $self->target . " " .
            $self->colon . " " .
            join(" ", @{ $self->normal_prereqs }) . "$order_part ; " .
            join("", map { "[$_]" } @{ $self->commands });
    $str =~ s/\n+//g;
    $str =~ s/  +/ /g;
    $str;
}

sub run_command ($$) {
    my ($self, $ast, $raw_cmd) = @_;

    ## $raw_cmd
    my @tokens = $raw_cmd->elements;
    my ($silent, $tolerant, $critical);
    while ($tokens[0]->class eq 'MDOM::Token::Modifier') {
        my $modifier = shift @tokens;
        if ($modifier eq '+') {
            # XXX is this the right thing to do?
            $critical = 1;
        } elsif ($modifier eq '-') {
            $tolerant = 1;
        } elsif ($modifier eq '@') {
            $silent = 1;
        } else {
            die "Unknown modifier: $modifier";
        }
        trim_tokens(\@tokens);
    }
    local $. = $raw_cmd->lineno;
    my $cmd = $ast->solve_refs_in_tokens(\@tokens);
    $cmd =~ s/^\s+|\s+$//gs;
    return if $cmd eq '';
    ### command: $cmd
    if (!$Makefile::AST::Evaluator::Quiet &&
            (!$silent || $Makefile::AST::Evaluator::JustPrint)) {
        print "$cmd\n";
    }
    if (! $Makefile::AST::Evaluator::JustPrint) {
        system($ast->eval_var_value('SHELL'), '-c', $cmd);
        if ($? != 0) {
            my $retval = $? >> 8;
            # XXX better error message
            if (!$Makefile::AST::Evaluator::IgnoreErrors &&
                    (!$tolerant || $critical)) {
                # XXX better handling for tolerance
                die "$::MAKE: *** [all] Error $retval\n";
            } else {
                my $target = $ast->get_var('@')->value->[0];
                warn "$::MAKE: [$target] Error $retval (ignored)\n";
            }
        }
    }
}

sub run_commands ($$) {
    my ($self, $ast) = @_;
    my @normal_prereqs = @{ $self->normal_prereqs };
    my @order_prereqs = @{ $self->order_prereqs };
    ### @normal_prereqs
    ### @order_prereqs
    $ast->add_auto_var(
        '@' => [$self->target],
        '<' => [$normal_prereqs[0]], # XXX better solutions?
        '*' => [$self->stem],
        '^' => [join(" ", List::MoreUtils::uniq(@normal_prereqs))],
        '+' => [join(" ", @normal_prereqs)],
        '|' => [join(" ", List::MoreUtils::uniq(@order_prereqs))],
        # XXX add more automatic vars' defs here
    );
    ## auto $^: $ast->get_var('^')
    for my $cmd (@{ $self->commands }) {
        $Makefile::AST::Evaluator::CmdRun = 1;
        $self->run_command($ast, $cmd);
    }
}

1;
