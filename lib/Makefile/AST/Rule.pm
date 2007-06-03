package Makefile::AST::Rule;

use strict;
use warnings;

#use Smart::Comments;
use base 'Makefile::AST::Rule::Base';
use MDOM::Util 'trim_tokens';

__PACKAGE__->mk_accessors(qw{
    stem target other_targets
});

sub run_command ($$) {
    my ($self, $ast, $raw_cmd) = @_;

    ### $raw_cmd
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
    if (!$silent) {
        print "$cmd\n";
    }
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

sub run_commands ($$) {
    my ($self, $ast) = @_;
    $ast->add_auto_var(
        '@' => $self->target,
        '<' => ($self->normal_prereqs)[0], # XXX better solutions?
        '*' => $self->stem,
        { replace => 0 }
    );
    for my $cmd (@{ $self->commands }) {
        $self->run_command($ast, $cmd);
    }
}

1;
