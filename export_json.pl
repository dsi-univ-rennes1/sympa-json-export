#!/bin/perl
# -*- indent-tabs-mode: nil; -*-
# vim:ft=perl:et:sw=4
# $Id$

# O.Salaün: script to generate a JSON file that represents the mailing lists tree
# this JSON file is loaded by a Zimbra Sympa zimlet

use lib split(/:/, $ENV{SYMPALIB} || '');

use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;

use Conf;
use Sympa::Crash;    # Show traceback.
use Sympa::Language;
use Sympa::List;
use Sympa::Log;
use Sympa::Scenario;
use Data::Dumper;

# Specific requirements
use JSON;

my %options;
GetOptions(\%main::options, 'help|h','robot=s','visibility_as_email=s');

if ($main::options{'help'}) {
    pod2usage(0);
}

## Load Sympa.conf
unless (defined Conf::load()) {
    printf STDERR
        "Unable to load sympa configuration, file %s or one of the vhost robot.conf files contain errors. Exiting.\n",
        Conf::get_sympa_conf();
    exit 1;
}

foreach my $arg ('robot','visibility_as_email') {
    unless (defined $main::options{$arg}) {
        die "Missing argument: $arg\n";
    }
}

my $log = Sympa::Log->instance;
$log->{level} = $Conf::Conf{'log_level'};
$log->openlog($Conf::Conf{'syslog'}, $Conf::Conf{'log_socket_type'});


# Recursively select topics to export
sub select_topics {
    my $topics = shift;
    my $robot = shift;
    my $email_to_evaluate_visibility = shift;
    my %topics_tree;
    
    while (my ($id_topic, $topic) = each %$topics) {
        my $result = Sympa::Scenario->new($robot, 'topics_visibility', name => $topic->{visibility})->authz(
                'md5',
                {   'topicname'   => $id_topic,
                    'sender'      => $email_to_evaluate_visibility
                }
        );
        # We check if 'visibility_as_email' may view this topic
        # If not topic is excluded from generated JSON file
        next unless (ref($result) eq 'HASH' && $result->{'action'} =~ /do_it/);
        my %topic_tree = ('type' => 'topic', 'description' => $topic->{'current_title'});
        
        if (defined $topic->{'sub'}) {
            $topic_tree{'children'} = select_topics($topic->{'sub'}, $robot, $email_to_evaluate_visibility);
        }
        $topics_tree{$id_topic} = \%topic_tree;
    }
    
    return \%topics_tree;
}

# Return the list_tree entry for a given list topic
sub get_topic_node {
    my $tree = shift;
    my $list_topics = shift;

    if ($#{$list_topics} < 0) {
        return $tree;   
    }
    my $subtree = $tree->{'children'}{$list_topics->[0]};
    if (defined $subtree) {
        shift @{$list_topics};
        
        return get_topic_node($subtree, $list_topics);
    }else {
        printf "ERROR : manque topic %s/%s\n", $list_topics->[0];
        return undef;
    }
}

# Reorganize %list_tree to turn 'children' nodes into arrayrefs
sub reorganize_tree {
    my $tree = shift;
    my $level = shift || 1;
    
    if (defined $tree->{'children'}) {
        my $reorg_children = [];
        while (my ($key, $child) = each %{$tree->{'children'}}) {
            push @{$reorg_children}, reorganize_tree($child, $level+1);
        }
        $tree->{'children'} = $reorg_children;
    }
    return $tree;        
}

my %list_tree = ('type' => 'root', 'description' => Conf::get_robot_conf($main::options{'robot'}, 'title'));
my %topics = Sympa::Robot::load_topics($main::options{'robot'});
$list_tree{'children'} = select_topics(\%topics,
                                        $main::options{'robot'},
                                        $main::options{'visibility_as_email'});

# Load topics.conf
#print Data::Dumper::Dumper(\%topics);

# Go through all lists
my $all_lists     = Sympa::List::get_lists($main::options{'robot'});
foreach my $list (@{$all_lists || []}) {
    next unless $list->{'admin'}{'status'} eq 'open';
    
    # We check if 'visibility_as_email' may view this list
    # If not list is excluded from generated JSON file
    my $result = Sympa::Scenario->new($list, 'visibility')->authz(
            'md5',
            {   'sender'      => $main::options{'visibility_as_email'} }
        );

    my $action;
    my $reason;
    if (ref($result) eq 'HASH') {
        $action = $result->{'action'};
        $reason = $result->{'reason'};
    }
    next unless ($action =~ /do_it/);
       
    my @topics = @{$list->{'admin'}{'topics'} || []};
    
    next if ($#topics < 0);

    #printf "%s : visibility=%s ; topics=%s\n",$list->{'name'}, $list->{'admin'}{'visibility'}{'name'}, join(',', @topics);
       
    my %list_node = ('type' => 'list', 'email' => $list->get_list_address(), 'description' => $list->{'admin'}{'subject'}." (".$list->get_total()." membres)");
    foreach my $topic (@topics) {
        my @list_topics = split '/', $topic;
        my $node = get_topic_node(\%list_tree, \@list_topics);
        
        if (defined $node) {
            $node->{'children'}{$list->get_list_address()} = \%list_node;
        }
    }
}

#print Data::Dumper::Dumper(\%list_tree);

my $new_list_tree = reorganize_tree(\%list_tree);

my $json = JSON->new->allow_nonref;
 
my $json_text   = $json->encode( $new_list_tree );
my $perl_scalar = $json->decode( $json_text );
 
print $json->pretty->encode( $perl_scalar ); # pretty-printing

exit 0;

__END__

=encoding utf-8

=head1 NAME

export_json.pl - generate a JSON file that represents the mailing lists tree

=head1 SYNOPSIS

S<C<export_json.pl> C<--robot> I<lists.my.fqdn>  I<file> C<--visibility_as_email> I>anybody@my.fqdn> > I</var/www/html/fqdn_lists.json>>


=head1 DESCRIPTION

Alias_manager is a program that helps in installing aliases for newly
created lists and deleting aliases for closed lists. 

Alias management is performed only if it was setup in F</etc/sympa/sympa.conf>
(C<sendmail_aliases> configuration parameter).

Administrators using MTA functionalities to manage aliases (i.e.
virtual_regexp and transport_regexp with postfix) can disable alias
management by setting
C<sendmail_aliases> configuration parameter to C<none>.

=head1 OPTIONS

=over 4

=item C<add> I<listname> I<domain> [ I<file> ]

Add the set of aliases for the mailing list I<listname> in the
domain I<domain>.

=item C<del> I<listname> I<domain> [ I<file> ]

Remove the set of aliases for the mailing list I<listname> in the
domain I<domain>.

=back

=head1 FILES

F<$SENDMAIL_ALIASES> sendmail aliases file.

=head1 DOCUMENTATION

export_json.pl generates a JSON file that represents the mailing lists tree.
This JSON file is loaded by a Zimbra Sympa zimlet.

=head1 HISTORY

This program was originally written by:

=over 4

=item Olivier Salaün

=back

=head1 LICENSE

You may distribute this software under the terms of the GNU General
Public License Version 2.  For more details see F<README> file.

Permission is granted to copy, distribute and/or modify this document
under the terms of the GNU Free Documentation License, Version 1.1 or
any later version published by the Free Software Foundation; with no
Invariant Sections, no Front-Cover Texts and no Back-Cover Texts.  A
copy of the license can be found under
L<http://www.gnu.org/licenses/fdl.html>.


=cut
