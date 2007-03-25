package Makefile::Parser::GmakeDB;

use strict;
use warnings;

#use Smart::Comments;
use List::Util qw( first );
use MDOM::Document::Gmake;
use Makefile::AST;

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
    my ($var_origin, $rule, $orig_lineno);
    for my $elem ($dom->elements) {
        ## elem class: $elem->class
        ## elem lineno: $elem->lineno
        next if $elem->isa('MDOM::Token::Whitespace');
        if ($elem->isa('MDOM::Assignment')) {
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
                ### LHS: $name
                ### RHS: $rhs
                my $var = Makefile::AST::Variable->new({
                    name   => $name,
                    flavor => $flavor,
                    origin => $var_origin,
                    value  => \@value_tokens,
                });
                $ast->add_var($var);
                undef $var_origin;
            }
        }
        elsif ($elem =~ /^#\s+(automatic|makefile|default|environment)/) {
            $var_origin = $1;
        }
        elsif ($elem =~ /^#\s+.*\(from `\S+', line (\d+)\)/) {
            $orig_lineno = $1;
        }
        elsif ($elem->isa('MDOM::Rule::Simple')) {
            my $targets = $elem->targets;
            my $colon   = $elem->colon;
            my $prereqs = $elem->prereqs;
            my $command = $elem->command;
            my $target = join '', @$targets; # XXX solve refs?
            my @prereqs = split /\s+/, join '', @$prereqs; # XXX solve refs?
            map { $_ = "$_" } @$prereqs;
            if ($target !~ /\s/ and $target !~ /\%/ and !@prereqs) {
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
                        @prereqs = ('%' . $fst);
                    }
                } else {
                    ## found suffix rule rule/1: $target
                    $target = '%' . $fst;
                }
            }
            if ($target =~ /\%/) {
                ## implicit rule found: $target
                my $targets = [split /\s+/, $target];
                $rule = Makefile::AST::Rule::Implicit->new({
                            targets => $targets,
                            order_prereqs => [],
                            normal_prereqs => \@prereqs,
                            commands => [defined $command ? $command : ()],
                            colon => $colon,
                        });
                $ast->add_implicit_rule($rule);
            } else {
                $rule = Makefile::AST::Rule->new({
                    target => $target,
                    order_prereqs  => [],
                    normal_prereqs => \@prereqs,
                    commands => [defined $command ? $command : ()],
                    colon    => $colon,
                });
                $ast->add_explicit_rule($rule);
            }
        } elsif ($elem->isa('MDOM::Command')) {
            if (!$rule) {
                die "command not allowed here";
            } else {
                #my @tokens = map { "$_" } $elem->elements;
                #my @tokens = $elem
                #shift @tokens if $tokens[0] eq "\t";
                #pop @tokens if $tokens[-1] eq "\n";
                #push @{ $rule->{commands} }, \@tokens;
                my $first = $elem->first_element;
                ## $first
                $elem->remove_child($first) if $first->class eq 'MDOM::Token::Separator';
                $rule->add_command($elem->clone); # XXX why clone?
            }
        }
    }
    $ast;
}

1;
