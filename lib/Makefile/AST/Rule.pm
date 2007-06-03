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
    my $str = $self->target .
            $self->colon .
            join(" ", @{ $self->normal_prereqs }) . ";" .
            join("", map { "[$_]" } @{ $self->commands });
    $str =~ s/\n+//g;
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
    if (!$Makefile::Evaluator::Quiet &&
            (!$silent || $Makefile::Evaluator::JustPrint)) {
        print "$cmd\n";
    }
    if (! $Makefile::Evaluator::JustPrint) {
        system($ast->eval_var_value('SHELL'), '-c', $cmd);
        if ($? != 0) {
            my $retval = $? >> 8;
            # XXX better error message
            warn "$cmd returns nonzero status: $retval";
            if (!$tolerant or $critical) {
                # XXX better handling for tolerance
                die " Stop.\n";
            }
        }
    }
}

sub run_commands ($$) {
    my ($self, $ast) = @_;
    my @nprereqs = @{ $self->normal_prereqs };
    $ast->add_auto_var(
        '@' => [$self->target],
        '<' => [$nprereqs[0]], # XXX better solutions?
        '*' => [$self->stem],
        '^' => [List::MoreUtils::uniq(@nprereqs)],
        # XXX add more automatic vars' defs here
    );
    ### auto $^: $ast->get_var('^')
    for my $cmd (@{ $self->commands }) {
        $self->run_command($ast, $cmd);
    }
}

1;
