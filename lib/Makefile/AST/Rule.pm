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
sub as_str ($) {
    my $self = shift;
    my $order_part = '';
    ## as_str: order_prereqs: $self->order_prereqs
    if (@{ $self->order_prereqs }) {
        $order_part = " | " . join(" ",@{ $self->order_prereqs });
    }
    ### colon: $self->colon
    my $str = $self->target . " " .
            $self->colon . " " .
            join(" ", @{ $self->normal_prereqs }) . "$order_part ; " .
            join("", map { "[$_]" } @{ $self->commands });
    $str =~ s/\n+//g;
    $str =~ s/  +/ /g;
    $str;
}

sub run_command ($$) {
    my ($self, $ast, $raw_cmd,
        $silent, $tolerant, $critical) = @_;

    ## $raw_cmd
    my @tokens = $raw_cmd->elements;

    # try to recognize modifiers:
    my $modifier;
    while (@tokens) {
        if ($tokens[0]->class eq 'MDOM::Token::Whitespace') {
            shift @tokens;
            next;
        }
        last unless $tokens[0]->class eq 'MDOM::Token::Modifier';
        $modifier = shift @tokens;
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
    }
    local $. = $raw_cmd->lineno;
    ## TOKENS (BEFORE): @tokens
    my $cmd = $ast->solve_refs_in_tokens(\@tokens);
    ### cmd after solve (1): $cmd

    $cmd =~ s/^\s+|\s+$//gs;
    return if $cmd eq '';
    ### cmd after modifier extraction: $cmd
    ### critical (+): $critical
    ### tolerant (-): $tolerant
    ### silent (@): $silent
    if ($cmd =~ /(?<!\\)\n/sm) {
        # it seems to be a canned sequence of commands
        # XXX This is a hack to get things work
        my @cmd = split /(?<!\\)\n/, $cmd;
        my @new_cmd;
        for (@cmd) {
            s/^\s+|\s+$//g;
            require MDOM::Document::Gmake;
            @tokens = MDOM::Document::Gmake::_tokenize_command($_);
            ### Reparsed cmd tokens: @tokens
            my $cmd = MDOM::Command->new;
            $cmd->__add_elements(@tokens);
            # XXX upper-level's modifiers should take in
            #  effect in the recursive calls:
            $self->run_command($ast, $cmd, $silent, $tolerant, $critical);
        }
        return; # cut here
    }
    while (1) {
        if ($cmd =~ s/^\s*\+//) {
            # XXX is this the right thing to do?
            $critical = 1;
        } elsif ($cmd =~ s/^\s*-//) {
            $tolerant = 1;
        } elsif ($cmd =~ s/^\s*\@//) {
                $silent = 1;
        } else {
            last;
        }
    }
    $cmd =~ s/^\s+|\s+$//gs;
    return if $cmd eq '';

    if (!$Makefile::AST::Evaluator::Quiet &&
            (!$silent || $Makefile::AST::Evaluator::JustPrint)) {
        print "$cmd\n";
    }
    if (! $Makefile::AST::Evaluator::JustPrint) {
        system($ast->eval_var_value('SHELL'), '-c', $cmd);
        if ($? != 0) {
            my $retval = $? >> 8;
            my $target = $ast->eval_var_value('@');
            if (!$Makefile::AST::Evaluator::IgnoreErrors &&
                    (!$tolerant || $critical)) {
                # XXX better handling for tolerance
                die "$::MAKE: *** [$target] Error $retval\n";
            } else {
                warn "$::MAKE: [$target] Error $retval (ignored)\n";
            }
        }
    }
}

sub run_commands ($$) {
    my ($self, $ast) = @_;
    my @normal_prereqs = @{ $self->normal_prereqs };
    my @order_prereqs = @{ $self->order_prereqs };
    ## @normal_prereqs
    ## @order_prereqs
    ### run_commands: target: $self->target
    ### run_commands: Stem: $self->stem
    $ast->add_auto_var(
        '@' => [$self->target],
        '<' => [$normal_prereqs[0]], # XXX better solutions?
        '*' => [$self->stem],
        '^' => [join(" ", List::MoreUtils::uniq(@normal_prereqs))],
        '+' => [join(" ", @normal_prereqs)],
        '|' => [join(" ", List::MoreUtils::uniq(@order_prereqs))],
        # XXX add more automatic vars' defs here
    );
    ### auto $*: $ast->get_var('*')
    for my $cmd (@{ $self->commands }) {
        $Makefile::AST::Evaluator::CmdRun = 1;
        $self->run_command($ast, $cmd);
    }
}

1;
