# BEGIN BPS TAGGED BLOCK {{{
#
# COPYRIGHT:
#
# This software is Copyright (c) 1996-2007 Best Practical Solutions, LLC
#                                          <jesse@bestpractical.com>
#
# (Except where explicitly superseded by other copyright notices)
#
#
# LICENSE:
#
# This work is made available to you under the terms of Version 2 of
# the GNU General Public License. A copy of that license should have
# been provided with this software, but in any event can be snarfed
# from www.gnu.org.
#
# This work is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
# 02110-1301 or visit their web page on the internet at
# http://www.gnu.org/copyleft/gpl.html.
#
#
# CONTRIBUTION SUBMISSION POLICY:
#
# (The following paragraph is not intended to limit the rights granted
# to you to modify and distribute this software under the terms of
# the GNU General Public License and is only of importance to you if
# you choose to contribute your changes and enhancements to the
# community by submitting them to Best Practical Solutions, LLC.)
#
# By intentionally submitting any modifications, corrections or
# derivatives to this work, or any other work intended for use with
# Request Tracker, to Best Practical Solutions, LLC, you confirm that
# you are the copyright holder for those contributions and you grant
# Best Practical Solutions,  LLC a nonexclusive, worldwide, irrevocable,
# royalty-free, perpetual, license to use, copy, create derivative
# works based on those contributions, and sublicense and distribute
# those contributions and any derivatives thereof.
#
# END BPS TAGGED BLOCK }}}
# Major Changes:

# - Decimated ProcessRestrictions and broke it into multiple
# functions joined by a LUT
# - Semi-Generic SQL stuff moved to another file

# Known Issues: FIXME!

# - ClearRestrictions and Reinitialization is messy and unclear.  The
# only good way to do it is to create a RT::Model::TicketCollection->new Object.

=head1 name

  RT::Model::TicketCollection - A collection of Ticket objects


=head1 SYNOPSIS

  use RT::Model::TicketCollection;
  my $tickets = RT::Model::TicketCollection->new( current_user => $CurrentUser );

=head1 description

   A collection of RT::Model::TicketCollection.

=head1 METHODS


=cut

use strict;
use warnings;

package RT::Model::TicketCollection;
use base qw/RT::SearchBuilder/;
no warnings qw(redefine);

use RT::Model::CustomFieldCollection;
use Jifty::DBI::Collection::Unique;
use Text::Naming::Convention qw/renaming/;

# Override jifty default
sub implicit_clauses { }

# Configuration Tables:

# FIELD_METADATA is a mapping of searchable Field name, to Type, and other
# metadata.

our %FIELD_METADATA = (
    Status           => [ 'ENUM', ],                            #loc_left_pair
    Queue            => [ 'ENUM' => 'Queue', ],                 #loc_left_pair
    Type             => [ 'ENUM', ],                            #loc_left_pair
    Creator          => [ 'ENUM' => 'User', ],                  #loc_left_pair
    LastUpdatedBy  => [ 'ENUM' => 'User', ],                    #loc_left_pair
    Owner            => [ 'WATCHERFIELD' => 'owner', ],         #loc_left_pair
    EffectiveId     => [ 'INT', ],                              #loc_left_pair
    Id               => [ 'ID', ],                             #loc_left_pair
    InitialPriority => [ 'INT', ],                              #loc_left_pair
    FinalPriority   => [ 'INT', ],                              #loc_left_pair
    Priority         => [ 'INT', ],                             #loc_left_pair
    TimeLeft        => [ 'INT', ],                              #loc_left_pair
    TimeWorked      => [ 'INT', ],                              #loc_left_pair
    TimeEstimated   => [ 'INT', ],                              #loc_left_pair
                                                                               
    Linked       => ['LINK'],                                   #loc_left_pair
    LinkedTo    => [ 'LINK' => 'To' ],                          #loc_left_pair
    LinkedFrom   => [ 'LINK' => 'From' ],                       #loc_left_pair
    MemberOf     => [ 'LINK' => To => 'MemberOf', ],            #loc_left_pair
    DependsOn    => [ 'LINK' => To => 'DependsOn', ],           #loc_left_pair
    RefersTo     => [ 'LINK' => To => 'RefersTo', ],            #loc_left_pair
    HasMember   => [ 'LINK' => From => 'MemberOf', ],           #loc_left_pair
    DependentOn  => [ 'LINK' => From => 'DependsOn', ],         #loc_left_pair
    DependedOnBy => [ 'LINK' => From => 'DependsOn', ],         #loc_left_pair
    ReferredToBy => [ 'LINK' => From => 'RefersTo', ],          #loc_left_pair
    Told            => [ 'DATE'         => 'Told', ],           #loc_left_pair
    Starts          => [ 'DATE'         => 'starts', ],         #loc_left_pair
    Started         => [ 'DATE'         => 'Started', ],        #loc_left_pair
    Due             => [ 'DATE'         => 'Due', ],            #loc_left_pair
    Resolved        => [ 'DATE'         => 'resolved', ],       #loc_left_pair
    LastUpdated    => [ 'DATE'         => 'last_updated', ],    #loc_left_pair
    Created         => [ 'DATE'         => 'Created', ],        #loc_left_pair
    Subject         => [ 'STRING', ],                           #loc_left_pair
    Content         => [ 'TRANSFIELD', ],                       #loc_left_pair
    ContentType    => [ 'TRANSFIELD', ],                        #loc_left_pair
    Filename        => [ 'TRANSFIELD', ],                       #loc_left_pair
    TransactionDate => [ 'TRANSDATE', ],                        #loc_left_pair
    Requestor       => [ 'WATCHERFIELD' => 'requestor', ],      #loc_left_pair
    Requestors      => [ 'WATCHERFIELD' => 'requestor', ],      #loc_left_pair
    Cc              => [ 'WATCHERFIELD' => 'cc', ],             #loc_left_pair
    AdminCc         => [ 'WATCHERFIELD' => 'admin_cc', ],       #loc_left_pair
    Watcher         => [ 'WATCHERFIELD', ],                      #loc_left_pair
    QueueCc          => [ 'WATCHERFIELD' => 'Cc'      => 'Queue', ], #loc_left_pair
    QueueAdminCc     => [ 'WATCHERFIELD' => 'AdminCc' => 'Queue', ],  #loc_left_pair
    QueueWatcher     => [ 'WATCHERFIELD' => undef     => 'Queue', ], #loc_left_pair
    CustomFieldValue => [ 'CUSTOMFIELD', ],                     #loc_left_pair
    CustomField      => [ 'CUSTOMFIELD', ],                     #loc_left_pair
    CF               => [ 'CUSTOMFIELD', ],                     #loc_left_pair
    Updated          => [ 'TRANSDATE', ],                       #loc_left_pair
    RequestorGroup  => [ 'MEMBERSHIPFIELD' => 'requestor', ],   #loc_left_pair
    CcGroup         => [ 'MEMBERSHIPFIELD' => 'cc', ],          #loc_left_pair
    AdminCcGroup   => [ 'MEMBERSHIPFIELD' => 'admin_cc', ],     #loc_left_pair
    WatcherGroup     => [ 'MEMBERSHIPFIELD', ],                 #loc_left_pair
);

# support _ name conventions as well
for my $field ( keys %FIELD_METADATA ) {
    $FIELD_METADATA{ renaming( $field, { convention => '_' } ) } =
      $FIELD_METADATA{$field};
}


# Mapping of Field type to Function
our %dispatch = (
    ENUM            => \&_enum_limit,
    INT             => \&_int_limit,
    ID              => \&_id_limit,
    LINK            => \&_link_limit,
    DATE            => \&_date_limit,
    STRING          => \&_string_limit,
    TRANSFIELD      => \&_trans_limit,
    TRANSDATE       => \&_trans_date_limit,
    WATCHERFIELD    => \&_watcher_limit,
    MEMBERSHIPFIELD => \&_watcher_membership_limit,
    CUSTOMFIELD     => \&_custom_field_limit,
);
our %can_bundle = ();    # WATCHERFIELD => "yes", );

# Default entry_aggregator per type
# if you specify OP, you must specify all valid OPs
my %DefaultEA = (
    INT  => 'AND',
    ENUM => {
        '='  => 'OR',
        '!=' => 'AND'
    },
    DATE => {
        '='  => 'OR',
        '>=' => 'AND',
        '<=' => 'AND',
        '>'  => 'AND',
        '<'  => 'AND'
    },
    STRING => {
        '='        => 'OR',
        '!='       => 'AND',
        'LIKE'     => 'AND',
        'NOT LIKE' => 'AND'
    },
    TRANSFIELD   => 'AND',
    TRANSDATE    => 'AND',
    LINK         => 'OR',
    LINKFIELD    => 'AND',
    target       => 'AND',
    base         => 'AND',
    WATCHERFIELD => {
        '='        => 'OR',
        '!='       => 'AND',
        'LIKE'     => 'OR',
        'NOT LIKE' => 'AND'
    },

    CUSTOMFIELD => 'OR',
);

# Helper functions for passing the above lexically scoped tables above
# into Tickets_Overlay_SQL.
sub columns    { return \%FIELD_METADATA }
sub dispatch   { return \%dispatch }
sub can_bundle { return \%can_bundle }

# Bring in the clowns.


our @SORTcolumns = qw(id status
    queue subject
    owner created due starts started
    told
    resolved last_updated priority time_worked time_left);

=head2 sort_fields

Returns the list of fields that lists of tickets can easily be sorted by

=cut

sub sort_fields {
    my $self = shift;
    return (@SORTcolumns);
}


# BEGIN SQL STUFF *********************************

sub clean_slate {
    my $self = shift;
    $self->SUPER::clean_slate(@_);
    delete $self->{$_} foreach qw(
        _sql_cf_alias
        _sql_group_members_aliases
        _sql_object_cfv_alias
        _sql_role_group_aliases
        _sql_transalias
        _sql_trattachalias
        _sql_u_watchers_alias_for_sort
        _sql_u_watchers_aliases
        _sql_current_user_can_see_applied
    );
}

=head1 Limit Helper Routines

These routines are the targets of a dispatch table depending on the
type of field.  They all share the same signature:

  my ($self,$field,$op,$value,@rest) = @_;

The values in @rest should be suitable for passing directly to
Jifty::DBI::limit.

Essentially they are an expanded/broken out (and much simplified)
version of what ProcessRestrictions used to do.  They're also much
more clearly delineated by the type of field being processed.

=head2 _id_limit

Handle ID field.

=cut

sub _id_limit {
    my ( $sb, $field, $op, $value, @rest ) = @_;

    return $sb->_int_limit( $field, $op, $value, @rest )
      unless $value eq '__Bookmarked__';

    die "Invalid operator $op for __Bookmarked__ search on $field"
      unless $op =~ /^(=|!=)$/;

    my @bookmarks = do {
        my $tmp = $sb->current_user->user_object->first_attribute('Bookmarks');
        $tmp = $tmp->content if $tmp;
        $tmp ||= {};
        grep $_, keys %$tmp;
    };

    return $sb->_sql_limit(
        column    => $field,
        operator => $op,
        value    => 0,
        @rest,
    ) unless @bookmarks;

    # as bookmarked tickets can be merged we have to use a join
    # but it should be pretty lightweight
    my $tickets_alias = $sb->join(
        type => 'left',
        alias1 => 'main',
        column1 => 'id',
        table2 => 'Tickets',
        column2 => 'effective_id',
    );
    $sb->_open_paren;
    my $first = 1;
    my $ea = $op eq '=' ? 'OR' : 'AND';
    foreach my $id ( sort @bookmarks ) {
        $sb->_sql_limit(
            alias    => $tickets_alias,
            column    => 'id',
            operator => $op,
            value    => $id,
            $first ? (@rest) : ( entry_aggregator => $ea )
        );
    }
    $sb->_close_paren;
}



=head2 _enum_limit

Handle Fields which are limited to certain values, and potentially
need to be looked up from another class.

This subroutine actually handles two different kinds of fields.  For
some the user is responsible for limiting the values.  (i.e. Status,
Type).

For others, the value specified by the user will be looked by via
specified class.

Meta Data:
  name of class to lookup in (Optional)

=cut

sub _enum_limit {
    my ( $sb, $field, $op, $value, @rest ) = @_;

    # SQL::Statement changes != to <>.  (Can we remove this now?)
    $op = "!=" if $op eq "<>";

    die "Invalid Operation: $op for $field"
        unless $op eq "="
            or $op eq "!=";

    my $meta = $FIELD_METADATA{$field};
    if ( defined $meta->[1] && defined $value && $value !~ /^\d+$/ ) {
        my $class = "RT::Model::" . $meta->[1];
        my $o     = $class->new();
        $o->load($value);
        $value = $o->id;
    }
    $sb->_sql_limit(
        column   => $field,
        value    => $value,
        operator => $op,
        @rest,
    );
}

=head2 _int_limit

Handle fields where the values are limited to integers.  (For example,
priority, time_worked.)

Meta Data:
  None

=cut

sub _int_limit {
    my ( $sb, $field, $op, $value, @rest ) = @_;

    die "Invalid Operator $op for $field"
        unless $op =~ /^(=|!=|>|<|>=|<=)$/;

    $sb->_sql_limit(
        column   => $field,
        value    => $value,
        operator => $op,
        @rest,
    );
}

=head2 _link_limit

Handle fields which deal with links between tickets.  (MemberOf, DependsOn)

Meta Data:
  1: Direction (From, To)
  2: Link type (MemberOf, DependsOn, RefersTo)

=cut

sub _link_limit {
    my ( $sb, $field, $op, $value, @rest ) = @_;

    my $meta = $FIELD_METADATA{$field};
    die "Invalid Operator $op for $field"
        unless $op =~ /^(=|!=|IS|IS NOT)$/io;

    my $is_negative = 0;
    if ( $op eq '!=' || $op =~ /\bNOT\b/i ) {
        $is_negative = 1;
    } 
    my $is_null = 0;
    $is_null = 1 if !$value || $value =~ /^null$/io;
    
    my $direction = $meta->[1] || '';
    my ( $matchfield, $linkfield ) = ( '', '' );
    if ( $direction eq 'To' ) {
        ( $matchfield, $linkfield ) = ( "target", "base" );
    } elsif ( $direction eq 'From' ) {
        ( $matchfield, $linkfield ) = ( "base", "target" );
    } elsif ($direction) {
        die "Invalid link direction '$direction' for $field\n";
    }
    else {
        $sb->open_paren;

        $sb->_link_limit( 'LinkedTo', $op, $value, @rest );
        $sb->_link_limit(
            'LinkedFrom',
            $op, $value, @rest,
            entry_aggregator => (
                ( $is_negative && $is_null ) || ( !$is_null && !$is_negative )
              ) ? 'OR' : 'AND',
        );
        $sb->close_paren;
        return;
    }
 

    my $is_local = 1;
    if ( $is_null ) {
        $op = ( $op =~ /^(=|IS)$/ ) ? 'IS' : 'IS NOT';
    } elsif ( $value =~ /\D/ ) {
        $is_local = 0;
    }
    $matchfield = "local_$matchfield" if $is_local;

    #For doing a left join to find "unlinked tickets" we want to generate a query that looks like this
    #    SELECT main.* FROM Tickets main
    #        left join Links Links_1 ON (     (Links_1.Type = 'MemberOf')
    #                                      AND(main.id = Links_1.local_target))
    #        WHERE Links_1.local_base IS NULL;

    if ($is_null) {
        my $linkalias = $sb->join(
            type    => 'left',
            alias1  => 'main',
            column1 => 'id',
            table2  => RT::Model::LinkCollection->new,
            column2 => 'local_' . $linkfield
        );
        $sb->SUPER::limit(
            leftjoin => $linkalias,
            column   => 'type',
            operator => '=',
            value    => $meta->[2],
        ) if $meta->[2];
        $sb->_sql_limit(
            @rest,
            alias       => $linkalias,
            column      => $matchfield,
            operator    => $op,
            value       => 'NULL',
            quote_value => 0,
        );
    } else {
        my $linkalias = $sb->join(
            type    => 'left',
            alias1  => 'main',
            column1 => 'id',
            table2  => RT::Model::LinkCollection->new,
            column2 => 'local_' . $linkfield
        );
        $sb->SUPER::limit(
            leftjoin => $linkalias,
            column   => 'type',
            operator => '=',
            value    => $meta->[2],
        ) if $meta->[2];
        $sb->SUPER::limit(
            leftjoin => $linkalias,
            column   => $matchfield,
            operator => '=',
            value    => $value,
        );
        $sb->_sql_limit(
            @rest,
            alias       => $linkalias,
            column      => $matchfield,
            operator    => $is_negative ? 'IS' : 'IS NOT',
            value       => 'NULL',
            quote_value => 0,
        );
    }
}

=head2 _date_limit

Handle date fields.  (Created, LastTold..)

Meta Data:
  1: type of link.  (Probably not necessary.)

=cut

sub _date_limit {
    my ( $sb, $field, $op, $value, @rest ) = @_;

    die "Invalid date Op: $op"
        unless $op =~ /^(=|>|<|>=|<=)$/;

    my $meta = $FIELD_METADATA{$field};
    die "Incorrect Meta Data for $field"
        unless ( defined $meta->[1] );

    my $date = RT::DateTime->new_from_string($value);

    if ( $op eq "=" ) {

        # if we're specifying =, that means we want everything on a
        # particular single day.  in the database, we need to check for >
        # and < the edges of that day.

        $date->truncate(to => 'day')->set_time_zone('server');
        my $daystart = $date->iso;
        my $dayend = $date->add(days => 1)->iso;

        $sb->open_paren;

        $sb->_sql_limit(
            column   => $meta->[1],
            operator => ">=",
            value    => $daystart,
            @rest,
        );

        $sb->_sql_limit(
            column   => $meta->[1],
            operator => "<=",
            value    => $dayend,
            @rest,
            entry_aggregator => 'AND',
        );

        $sb->close_paren;

    } else {
        $sb->_sql_limit(
            column   => $meta->[1],
            operator => $op,
            value    => $date->iso,
            @rest,
        );
    }
}

=head2 _string_limit

Handle simple fields which are just strings.  (subject,Type)

Meta Data:
  None

=cut

sub _string_limit {
    my ( $sb, $field, $op, $value, @rest ) = @_;

    # FIXME:
    # Valid Operators:
    #  =, !=, LIKE, NOT LIKE

    $sb->_sql_limit(
        column         => $field,
        operator       => $op,
        value          => $value,
        case_sensitive => 0,
        @rest,
    );
}

=head2 _trans_date_limit

Handle fields limiting based on Transaction Date.

The inpupt value must be in a format parseable by Time::ParseDate

Meta Data:
  None

=cut

# This routine should really be factored into translimit.
sub _trans_date_limit {
    my ( $sb, $field, $op, $value, @rest ) = @_;

    # See the comments for TransLimit, they apply here too

    unless ( $sb->{_sql_transalias} ) {
        $sb->{_sql_transalias} = $sb->join(
            alias1  => 'main',
            column1 => 'id',
            table2  => RT::Model::TransactionCollection->new,
            column2 => 'object_id',
        );
        $sb->SUPER::limit(
            alias            => $sb->{_sql_transalias},
            column           => 'object_type',
            value            => 'RT::Model::Ticket',
            entry_aggregator => 'AND',
        );
    }

    my $date = RT::DateTime->new_from_string($value);

    $sb->open_paren;
    if ( $op eq "=" ) {

        # if we're specifying =, that means we want everything on a
        # particular single day.  in the database, we need to check for >
        # and < the edges of that day.

        $date->truncate(to => 'day')->set_time_zone('server');
        my $daystart = $date->iso;
        my $dayend = $date->add(days => 1)->iso;

        $sb->_sql_limit(
            alias          => $sb->{_sql_transalias},
            column         => 'created',
            operator       => ">=",
            value          => $daystart,
            case_sensitive => 0,
            @rest
        );
        $sb->_sql_limit(
            alias          => $sb->{_sql_transalias},
            column         => 'created',
            operator       => "<=",
            value          => $dayend,
            case_sensitive => 0,
            @rest,
            entry_aggregator => 'AND',
        );

    }

    # not searching for a single day
    else {

        #Search for the right field
        $sb->_sql_limit(
            alias          => $sb->{_sql_transalias},
            column         => 'created',
            operator       => $op,
            value          => $date->iso,
            case_sensitive => 0,
            @rest
        );
    }

    $sb->close_paren;
}

=head2 _trans_limit

Limit based on the content of a transaction or the content_type.

Meta Data:
  none

=cut

sub _trans_limit {

    # Content, content_type, Filename

    # If only this was this simple.  We've got to do something
    # complicated here:

    #Basically, we want to make sure that the limits apply to
    #the same attachment, rather than just another attachment
    #for the same ticket, no matter how many clauses we lump
    #on. We put them in TicketAliases so that they get nuked
    #when we redo the join.

    # In the SQL, we might have
    #       (( content = foo ) or ( content = bar AND content = baz ))
    # The AND group should share the same Alias.

    # Actually, maybe it doesn't matter.  We use the same alias and it
    # works itself out? (er.. different.)

    # Steal more from _ProcessRestrictions

    # FIXME: Maybe look at the previous FooLimit call, and if it was a
    # TransLimit and entry_aggregator == AND, reuse the Aliases?

    # Or better - store the aliases on a per subclause basis - since
    # those are going to be the things we want to relate to each other,
    # anyway.

    # maybe we should not allow certain kinds of aggregation of these
    # clauses and do a psuedo regex instead? - the problem is getting
    # them all into the same subclause when you have (A op B op C) - the
    # way they get parsed in the tree they're in different subclauses.

    my ( $self, $field, $op, $value, @rest ) = @_;

    unless ( $self->{_sql_transalias} ) {
        $self->{_sql_transalias} = $self->join(
            alias1  => 'main',
            column1 => 'id',
            table2  => RT::Model::TransactionCollection->new,
            column2 => 'object_id',
        );
        $self->SUPER::limit(
            alias            => $self->{_sql_transalias},
            column           => 'object_type',
            value            => 'RT::Model::Ticket',
            entry_aggregator => 'AND',
        );
    }
    unless ( defined $self->{_sql_trattachalias} ) {
        $self->{_sql_trattachalias} = $self->_sql_join(
            type    => 'left',                                 # not all txns have an attachment
            alias1  => $self->{_sql_transalias},
            column1 => 'id',
            table2  => RT::Model::AttachmentCollection->new,
            column2 => 'transaction_id',
        );
    }

    $self->open_paren;

    #Search for the right field
    if ( $field eq 'content'
        and RT->config->get('DontSearchFileAttachments') )
    {
        $self->_sql_limit(
            alias            => $self->{_sql_trattachalias},
            column           => 'filename',
            operator         => 'IS',
            value            => 'NULL',
            subclause        => 'contentquery',
            entry_aggregator => 'AND',
        );
        $self->_sql_limit(
            alias          => $self->{_sql_trattachalias},
            column         => $field,
            operator       => $op,
            value          => $value,
            case_sensitive => 0,
            @rest,
            entry_aggregator => 'AND',
            subclause        => 'contentquery',
        );
    } else {
        $self->_sql_limit(
            alias            => $self->{_sql_trattachalias},
            column           => $field,
            operator         => $op,
            value            => $value,
            case_sensitive   => 0,
            entry_aggregator => 'AND',
            @rest
        );
    }

    $self->close_paren;

}

=head2 _watcher_limit

Handle watcher limits.  (requestor, CC, etc..)

Meta Data:
  1: Field to query on



=cut

sub _watcher_limit {
    my $self  = shift;
    my $field = shift;
    my $op    = shift;
    my $value = shift;
    my %rest  = (@_);

    my $meta  = $FIELD_METADATA{$field};
    my $type  = $meta->[1] || '';
    my $class = $meta->[2] || 'ticket';
    

    # owner was ENUM field, so "owner = 'xxx'" allowed user to
    # search by id and name at the same time, this is workaround
    # to preserve backward compatibility
    if ( lc $field eq 'owner' && !$rest{subkey} && $op =~ /^!?=$/ ) {
        my $o = RT::Model::User->new;
        $o->load($value);
        $self->_sql_limit(
            column   => 'owner',
            operator => $op,
            value    => $o->id,
            %rest,
        );
        return;
    }
    $rest{subkey} ||= 'email';

    my $groups = $self->_role_groupsjoin( type => $type, class => $class );

    $self->open_paren;
    if ( $op =~ /^IS(?: NOT)?$/ ) {
        my $group_members = $self->_group_membersjoin( groups_alias => $groups );

        # to avoid joining the table Users into the query, we just join GM
        # and make sure we don't match records where group is member of itself
        $self->SUPER::limit(
            leftjoin    => $group_members,
            column      => 'group_id',
            operator    => '!=',
            value       => "$group_members.member_id",
            quote_value => 0,
        );
        $self->_sql_limit(
            alias    => $group_members,
            column   => 'group_id',
            operator => $op,
            value    => $value,
            %rest,
        );
    } elsif ( $op =~ /^!=$|^NOT\s+/i ) {

        # reverse op
        $op =~ s/!|NOT\s+//i;

        # XXX: we have no way to build correct "Watcher.X != 'Y'" when condition
        # "X = 'Y'" matches more then one user so we try to fetch two records and
        # do the right thing when there is only one exist and semi-working solution
        # otherwise.
        my $users_obj = RT::Model::UserCollection->new;
        $users_obj->limit(
            column   => $rest{subkey},
            operator => $op,
            value    => $value,
        );
        $users_obj->rows_per_page(2);
        my @users = @{ $users_obj->items_array_ref };

        my $group_members = $self->_group_membersjoin( groups_alias => $groups );
        if ( @users <= 1 ) {
            my $uid = 0;
            $uid = $users[0]->id if @users;
            $self->SUPER::limit(
                leftjoin => $group_members,
                alias    => $group_members,
                column   => 'member_id',
                value    => $uid,
            );
            $self->_sql_limit(
                %rest,
                alias    => $group_members,
                column   => 'id',
                operator => 'IS',
                value    => 'NULL',
            );
        } else {
            $self->SUPER::limit(
                leftjoin    => $group_members,
                column      => 'group_id',
                operator    => '!=',
                value       => "$group_members.member_id",
                quote_value => 0,
            );
            my $users = $self->join(
                type    => 'left',
                alias1  => $group_members,
                column1 => 'member_id',
                table2  => RT::Model::UserCollection->new,
                column2 => 'id',
            );
            $self->SUPER::limit(
                leftjoin       => $users,
                alias          => $users,
                column         => $rest{subkey},
                operator       => $op,
                value          => $value,
                case_sensitive => 0,
            );
            $self->_sql_limit(
                %rest,
                alias    => $users,
                column   => 'id',
                operator => 'IS',
                value    => 'NULL',
            );
        }
    } else {
        my $group_members = $self->_group_membersjoin(
            groups_alias => $groups,
            new          => 0,
        );

        my $users = $self->{'_sql_u_watchers_aliases'}{$group_members};
        unless ($users) {
            $users = $self->{'_sql_u_watchers_aliases'}{$group_members} = $self->new_alias( RT::Model::UserCollection->new );
            $self->SUPER::limit(
                leftjoin    => $group_members,
                alias       => $group_members,
                column      => 'member_id',
                value       => "$users.id",
                quote_value => 0,
            );
        }

        # we join users table without adding some join condition between tables,
        # the only conditions we have are conditions on the table iteslf,
        # for example Users.email = 'x'. We should add this condition to
        # the top level of the query and bundle it with another similar conditions,
        # for example "Users.email = 'x' OR Users.email = 'Y'".
        # To achive this goal we use own subclause for conditions on the users table.
        $self->SUPER::limit(
            %rest,
            subclause      => '_sql_u_watchers_' . $users,
            alias          => $users,
            column         => $rest{'subkey'},
            value          => $value,
            operator       => $op,
            case_sensitive => 0,
        );

        # A condition which ties Users and Groups (role groups) is a left join condition
        # of CachedGroupMembers table. To get correct results of the query we check
        # if there are matches in CGM table or not using 'cgm.id IS NOT NULL'.
        $self->_sql_limit(
            %rest,
            alias    => $group_members,
            column   => 'id',
            operator => 'IS NOT',
            value    => 'NULL',
        );
    }
    $self->close_paren;
}

sub _role_groupsjoin {
    my $self = shift;
    my %args = ( new => 0, class => 'ticket', type => '', @_ );
    return $self->{'_sql_role_group_aliases'}
      { $args{'class'} . '-' . $args{'type'} }
      if $self->{'_sql_role_group_aliases'}
          { $args{'class'} . '-' . $args{'type'} }
          && !$args{'new'};
    

    # we always have watcher groups for ticket, so we use INNER join
    my $groups = $self->join(
        alias1           => 'main',
        column1          => $args{'class'} eq 'queue' ? 'queue' : 'id', 
        table2           => RT::Model::GroupCollection->new,
        column2          => 'instance',
        entry_aggregator => 'AND',
    );
    $self->SUPER::limit(
        leftjoin => $groups,
        alias    => $groups,
        column   => 'domain',
        value => 'RT::Model::'
          . renaming( $args{'class'}, { convention => 'UpperCamelCase' } )
          . '-Role',
    );
    $self->SUPER::limit(
        leftjoin => $groups,
        alias    => $groups,
        column   => 'type',
        value    => $args{'type'},
    ) if $args{'type'};

    $self->{'_sql_role_group_aliases'}{ $args{'class'} . '-' . $args{'type'} } =
      $groups
        unless $args{'new'};

    return $groups;
}

sub _group_membersjoin {
    my $self = shift;
    my %args = ( new => 1, groups_alias => undef, @_ );

    return $self->{'_sql_group_members_aliases'}{ $args{'groups_alias'} }
        if $self->{'_sql_group_members_aliases'}{ $args{'groups_alias'} }
            && !$args{'new'};

    my $alias = $self->join(
        type             => 'left',
        alias1           => $args{'groups_alias'},
        column1          => 'id',
        table2           => RT::Model::CachedGroupMemberCollection->new,
        column2          => 'group_id',
        entry_aggregator => 'AND',
    );

    $self->{'_sql_group_members_aliases'}{ $args{'groups_alias'} } = $alias
        unless $args{'new'};

    return $alias;
}

=head2 _watcherjoin

Helper function which provides joins to a watchers table both for limits
and for ordering.

=cut

sub _watcherjoin {
    my $self = shift;
    my $type = shift || '';

    my $groups = $self->_role_groupsjoin( type => $type );
    my $group_members = $self->_group_membersjoin( groups_alias => $groups );

    # XXX: work around, we must hide groups that
    # are members of the role group we search in,
    # otherwise them result in wrong NULLs in Users
    # table and break ordering. Now, we know that
    # RT doesn't allow to add groups as members of the
    # ticket roles, so we just hide entries in CGM table
    # with member_id == group_id from results
    $self->SUPER::limit(
        leftjoin    => $group_members,
        column      => 'group_id',
        operator    => '!=',
        value       => "$group_members.member_id",
        quote_value => 0,
    );
    my $users = $self->join(
        type    => 'left',
        alias1  => $group_members,
        column1 => 'member_id',
        table2  => RT::Model::UserCollection->new,
        column2 => 'id',
    );
    return ( $groups, $group_members, $users );
}

=head2 _watcher_membership_limit

Handle watcher membership limits, i.e. whether the watcher belongs to a
specific group or not.

Meta Data:
  1: Field to query on

SELECT DISTINCT main.*
FROM
    Tickets main,
    Groups Groups_1,
    CachedGroupMembers CachedGroupMembers_2,
    Users Users_3
WHERE (
    (main.effective_id = main.id)
) AND (
    (main.Status != 'deleted')
) AND (
    (main.Type = 'ticket')
) AND (
    (
	(Users_3.email = '22')
	    AND
	(Groups_1.domain = 'RT::Model::Ticket-Role')
	    AND
	(Groups_1.Type = 'requestor_group')
    )
) AND
    Groups_1.instance = main.id
AND
    Groups_1.id = CachedGroupMembers_2.group_id
AND
    CachedGroupMembers_2.member_id = Users_3.id
order BY main.id ASC
LIMIT 25

=cut

sub _watcher_membership_limit {
    my ( $self, $field, $op, $value, @rest ) = @_;
    my %rest = @rest;

    $self->open_paren;

    my $groups       = $self->new_alias( RT::Model::GroupCollection->new );
    my $groupmembers = $self->new_alias( RT::Model::CachedGroupMemberCollection->new );
    my $users        = $self->new_alias( RT::Model::UserCollection->new );
    my $memberships  = $self->new_alias( RT::Model::CachedGroupMemberCollection->new );

    if ( ref $field ) {    # gross hack
        my @bundle = @$field;
        $self->open_paren;
        for my $chunk (@bundle) {
            ( $field, $op, $value, @rest ) = @$chunk;
            $self->_sql_limit(
                alias    => $memberships,
                column   => 'group_id',
                value    => $value,
                operator => $op,
                @rest,
            );
        }
        $self->close_paren;
    } else {
        $self->_sql_limit(
            alias    => $memberships,
            column   => 'group_id',
            value    => $value,
            operator => $op,
            @rest,
        );
    }

    # {{{ Tie to groups for tickets we care about
    $self->_sql_limit(
        alias            => $groups,
        column           => 'domain',
        value            => 'RT::Model::Ticket-Role',
        entry_aggregator => 'AND'
    );

    $self->join(
        alias1  => $groups,
        column1 => 'instance',
        alias2  => 'main',
        column2 => 'id'
    );

    # }}}

    # If we care about which sort of watcher
    my $meta = $FIELD_METADATA{$field};
    my $type = ( defined $meta->[1] ? $meta->[1] : undef );

    if ($type) {
        $self->_sql_limit(
            alias            => $groups,
            column           => 'type',
            value            => $type,
            entry_aggregator => 'AND'
        );
    }

    $self->join(
        alias1  => $groups,
        column1 => 'id',
        alias2  => $groupmembers,
        column2 => 'group_id'
    );

    $self->join(
        alias1  => $groupmembers,
        column1 => 'member_id',
        alias2  => $users,
        column2 => 'id'
    );

    $self->join(
        alias1  => $memberships,
        column1 => 'member_id',
        alias2  => $users,
        column2 => 'id'
    );

    $self->close_paren;

}

=head2 _custom_field_decipher

Try and turn a CF descriptor into (cfid, cfname) object pair.

=cut

sub _custom_field_decipher {
    my ( $self, $string ) = @_;

    my ( $queue, $field, $column ) = ( $string =~ /^(?:(.+?)\.)?{(.+)}(?:\.(.+))?$/ );
    $field ||= ( $string =~ /^{(.*?)}$/ )[0] || $string;

    my $cf;
    if ($queue) {
        my $q = RT::Model::Queue->new;
        $q->load($queue);

        if ( $q->id ) {

            # $queue = $q->name; # should we normalize the queue?
            $cf = $q->custom_field($field);
        } else {
            Jifty->log->warn("Queue '$queue' doesn't exist, parsed from '$string'");
            $queue = 0;
        }

    } else {
        $queue = '';
        my $cfs =
          RT::Model::CustomFieldCollection->new( current_user => $self->current_user );
        $cfs->limit( column => 'name', value => $field );
        $cfs->limit_to_lookup_type('RT::Model::Queue-RT::Model::Ticket');

        # if there is more then one field the current user can
        # see with the same name then we shouldn't return cf object
        # as we don't know which one to use
        $cf = $cfs->first;
        if ( $cf ) {
            $cf = undef if $cfs->next;
        }
    }

    return ( $queue, $field, $cf, $column );
}

=head2 _custom_field_join

Factor out the join of custom fields so we can use it for sorting too

=cut

sub _custom_field_join {
    my ( $self, $cfkey, $cfid, $field ) = @_;

    # Perform one join per CustomField
    if (   $self->{_sql_object_cfv_alias}{$cfkey}
        || $self->{_sql_cf_alias}{$cfkey} )
    {
        return ( $self->{_sql_object_cfv_alias}{$cfkey}, $self->{_sql_cf_alias}{$cfkey} );
    }

    my ( $TicketCFs, $CFs );
    if ($cfid) {
        $TicketCFs = $self->{_sql_object_cfv_alias}{$cfkey} = $self->join(
            type    => 'left',
            alias1  => 'main',
            column1 => 'id',
            table2  => RT::Model::ObjectCustomFieldValueCollection->new,
            column2 => 'object_id',
        );
        $self->SUPER::limit(
            leftjoin         => $TicketCFs,
            column           => 'custom_field',
            value            => $cfid,
            entry_aggregator => 'AND'
        );
    } else {
        my $ocfalias = $self->join(
            type             => 'left',
            column1          => 'queue',
            table2           => RT::Model::ObjectCustomFieldCollection->new,
            column2          => 'object_id',
            entry_aggregator => 'OR',
        );

        $self->SUPER::limit(
            leftjoin => $ocfalias,
            column   => 'object_id',
            value    => '0',
        );

        $CFs = $self->{_sql_cf_alias}{$cfkey} = $self->join(
            type    => 'left',
            alias1  => $ocfalias,
            column1 => 'custom_field',
            table2  => RT::Model::CustomFieldCollection->new,
            column2 => 'id',
        );

# TODO: XXX this's from 3.8, but tests fail if uncomment it
#        $self->SUPER::limit(
#            leftjoin        => $CFs,
#            entry_aggregator => 'AND',
#            column           => 'lookup_type',
#            value           => 'RT::Model::Queue-RT::Model::Ticket',
#        );
#        $self->SUPER::limit(
#            leftjoin        => $CFs,
#            entry_aggregator => 'AND',
#            column           => 'name',
#            value           => $field,
#        );

        $TicketCFs = $self->{_sql_object_cfv_alias}{$cfkey} = $self->join(
            type    => 'left',
            alias1  => $CFs,
            column1 => 'id',
            table2  => RT::Model::ObjectCustomFieldValueCollection->new,
            column2 => 'custom_field',
        );
        $self->SUPER::limit(
            leftjoin         => $TicketCFs,
            column           => 'object_id',
            value            => 'main.id',
            quote_value      => 0,
            entry_aggregator => 'AND',
        );
    }
    $self->SUPER::limit(
        leftjoin         => $TicketCFs,
        column           => 'object_type',
        value            => 'RT::Model::Ticket',
        entry_aggregator => 'AND'
    );
    $self->SUPER::limit(
        leftjoin         => $TicketCFs,
        column           => 'disabled',
        operator         => '=',
        value            => '0',
        entry_aggregator => 'AND'
    );

    return ( $TicketCFs, $CFs );
}

=head2 _custom_field_limit

Limit based on CustomFields

Meta Data:
  none

=cut

sub _custom_field_limit {
    my ( $self, $_field, $op, $value, %rest ) = @_;

    my $field = $rest{'subkey'} || die "No field specified";

    # For our sanity, we can only limit on one queue at a time

    my ($queue, $cfid, $cf, $column);
    ($queue, $field, $cf, $column) = $self->_custom_field_decipher( $field );
    $cfid = $cf ? $cf->id  : 0 ;
    

    # If we're trying to find custom fields that don't match something, we
    # want tickets where the custom field has no value at all.  Note that
    # we explicitly don't include the "IS NULL" case, since we would
    # otherwise end up with a redundant clause.

    my $null_columns_ok;
    my $fix_op = sub {
        my $op = shift;
        return $op unless RT->config->get('DatabaseType') eq 'Oracle';
        return 'MATCHES'     if $op eq '=';
        return 'NOT MATCHES' if $op eq '!=';
        return $op;
    };
    
    if ( ( $op =~ /^NOT LIKE$/i ) or ( $op eq '!=' ) ) {
        $null_columns_ok = 1;
    }

    my $cfkey = $cfid ? $cfid : "$queue.$field";
    my ( $TicketCFs, $CFs ) = $self->_custom_field_join( $cfkey, $cfid, $field );

    $self->open_paren;

# TODO: XXX this if block doesn't exist in 3.8, but I got test fails if
# comment this.
    if ( $CFs && !$cfid ) {
        $self->SUPER::limit(
            alias            => $CFs,
            column           => 'name',
            value            => $field,
            entry_aggregator => 'AND',
        );
    }

    $self->open_paren;
    $self->open_paren;

     # if column is defined then deal only with it
     # otherwise search in Content and in LargeContent
    if ($column) {
        $self->_sql_limit(
            alias    => $TicketCFs,
            column    => $column,
            operator => ( $column ne 'large_content' ? $op : $fix_op->($op) ),
            value    => $value,
            %rest
            );
    }
    else {
        $self->_sql_limit(
            alias    => $TicketCFs,
            column    => 'content',
            operator => $op,
            
            value    => $value,
            %rest
        );
  
        $self->open_paren;
        $self->open_paren;
        $self->_sql_limit(
            alias           => $TicketCFs,
            column           => 'content',
            operator        => '=',
            value           => '',
            entry_aggregator => 'OR'
        );
        $self->_sql_limit(
            alias           => $TicketCFs,
            column           => 'content',
            operator        => 'IS',
            value           => 'NULL',
            entry_aggregator => 'OR'
        );
        $self->close_paren;
        $self->_sql_limit(
            alias           => $TicketCFs,
            column           => 'large_content',
            operator        => $fix_op->($op),
            value           => $value,
            entry_aggregator => 'AND',
        );
        $self->close_paren;
    }
    $self->close_paren;

    # XXX: if we join via CustomFields table then
    # because of order of left joins we get NULLs in
    # CF table and then get nulls for those records
    # in OCFVs table what result in wrong results
    # as decifer method now tries to load a CF then
    # we fall into this situation only when there
    # are more than one CF with the name in the DB.
    # the same thing applies to order by call.
    # TODO: reorder joins T <- OCFVs <- CFs <- OCFs if
    # we want treat IS NULL as (not applies or has
    # no value)
    $self->_sql_limit(
        alias           => $CFs,
        column           => 'name',
        operator        => 'IS NOT',
        value           => 'NULL',
        quote_value      => 0,
        entry_aggregator => 'AND',
    ) if $CFs;
    $self->close_paren;

    if ($null_columns_ok) {
        $self->_sql_limit(
            alias            => $TicketCFs,
            column           => $column || 'content',
            operator         => 'IS',
            value            => 'NULL',
            quote_value      => 0,
            entry_aggregator => 'OR',
        );
    }

    $self->close_paren;

}

# End Helper Functions

# End of SQL Stuff -------------------------------------------------


=head2 order_by ARRAY

A modified version of the order_by method which automatically joins where
C<alias> is set to the name of a watcher type.

=cut

sub order_by {
    my $self = shift;

    # If we're not forcing the order we don't want to do clever permutations
    # (order_by is an accessor as well as a mutator)
    return $self->SUPER::order_by() unless (@_);

    my @args = ref( $_[0] ) ? @_ : {@_};
    my $clause;
    my @res   = ();
    my $order = 0;
    foreach my $row (@args) {
        if ( $row->{alias} ) {
            push @res, $row;
            next;
        }
        if ( $row->{column} !~ /\./ ) {
            my $meta = $self->columns->{ $row->{column} };
            unless ($meta) {
                push @res, $row;
                next;
            }

            if ( $meta->[0] eq 'ENUM' && ( $meta->[1] || '' ) eq 'Queue' ) {
                my $alias = $self->join(
                    type   => 'left',
                    alias1 => 'main',
                    column1 => $row->{'column'},
                    table2 => 'Queues',
                    column2 => 'id',
                );
                push @res, { %$row, alias => $alias, column => "name" };
            }
            elsif (
                ( $meta->[0] eq 'ENUM' && ( $meta->[1] || '' ) eq 'User' )
                || ( $meta->[0] eq 'WATCHERFIELD'
                    && ( $meta->[1] || '' ) eq 'owner' )
              )
            {
                my $alias = $self->join(
                    type   => 'left',
                    alias1 => 'main',
                    column1 => $row->{'column'},
                    table2 => 'Users',
                    column2 => 'id',
                );
                push @res, { %$row, alias => $alias, column => "name" };
            }
            else {
                push @res, $row;
            }
            next;
        }

        my ( $field, $subkey ) = split /\./, $row->{column}, 2;
        my $meta = $self->columns->{$field};
        if ( defined $meta->[0] && $meta->[0] eq 'WATCHERFIELD' ) {

            # cache alias as we want to use one alias per watcher type for sorting
            my $users = $self->{_sql_u_watchers_alias_for_sort}{ $meta->[1] };
            unless ($users) {
                $self->{_sql_u_watchers_alias_for_sort}{ $meta->[1] } = $users = ( $self->_watcherjoin( $meta->[1] ) )[2];
            }
            push @res, { %$row, alias => $users, column => $subkey };
        } elsif ( defined $meta->[0] && $meta->[0] =~ /CUSTOMFIELD/i ) {
           my ($queue, $field, $cf_obj, $column) = $self->_custom_field_decipher( $subkey );
           my $cfkey = $cf_obj ? $cf_obj->id : "$queue.$field";
           $cfkey .= ".ordering" if !$cf_obj || ($cf_obj->max_values||0) != 1;
            
            my ( $TicketCFs, $CFs ) = $self->_custom_field_join( $cfkey, ($cf_obj ?$cf_obj->id :0), $field );
            $self->_sql_limit(
                alias      => $CFs,
                column      => 'name',
                operator   => 'IS NOT',
                value      => 'NULL',
                quote_value => 1,
                entry_aggregator => 'AND',
            ) if $CFs;
            
            unless ($cf_obj) {

                # For those cases where we are doing a join against the
                # CF name, and don't have a CFid, use Unique to make sure
                # we don't show duplicate tickets.  NOTE: I'm pretty sure
                # this will stay mixed in for the life of the
                # class/package, and not just for the life of the object.
                # Potential performance issue.
                require Jifty::DBI::Collection::Unique;
                Jifty::DBI::Collection::Unique->import;
            }
            my $CFvs = $self->join(
                type    => 'left',
                alias1  => $TicketCFs,
                column1 => 'custom_field',
                table2  => RT::Model::CustomFieldValueCollection->new,
                column2 => 'custom_field',
            );
            $self->SUPER::limit(
                leftjoin         => $CFvs,
                column           => 'name',
                quote_value      => 0,
                value            => $TicketCFs . ".content",
                entry_aggregator => 'AND'
            );

            push @res, { %$row, alias => $CFvs,      column => 'sort_order' };
            push @res, { %$row, alias => $TicketCFs, column => 'content' };
        } elsif ( $field eq "custom" && $subkey eq "ownership" ) {

            # PAW logic is "reversed"
            my $order = "ASC";
            if ( exists $row->{order} ) {
                my $o = delete $row->{order};
                $order = "DESC" if $o =~ /asc/i;
            }

            # Unowned
            # Else

            # Ticket.owner  1 0 0
            my $ownerId = $self->current_user->id;
            push @res, { %$row, column => "owner=$ownerId", order => $order };

            # Unowned Tickets 0 1 0
            my $nobodyId = RT->nobody->id;
            push @res, { %$row, column => "owner=$nobodyId", order => $order };

            push @res, { %$row, column => "priority", order => $order };
        } else {
            push @res, $row;
        }
    }
    return $self->SUPER::order_by(@res);
}


=head2 limit

Takes a paramhash with the fields column, operator, value and description
Generally best called from limit_Foo methods

=cut

sub limit {
    my $self = shift;
    my %args = (
        column      => undef,
        operator    => '=',
        value       => undef,
        description => undef,
        @_
    );
    $args{'description'} = _( "%1 %2 %3", $args{'column'}, $args{'operator'}, $args{'value'} )
        if ( !defined $args{'description'} );

    my $index = $self->next_index;

    # make the TicketRestrictions hash the equivalent of whatever we just passed in;

    %{ $self->{'TicketRestrictions'}{$index} } = %args;

    $self->{'RecalcTicketLimits'} = 1;

    # If we're looking at the effective id, we don't want to append the other clause
    # which limits us to tickets where id = effective id
    if ( $args{'column'} eq 'effective_id'
        && ( !$args{'alias'} || $args{'alias'} eq 'main' ) )
    {
        $self->{'looking_at_effective_id'} = 1;
    }

    if ( $args{'column'} eq 'type'
        && ( !$args{'alias'} || $args{'alias'} eq 'main' ) )
    {
        $self->{'looking_at_type'} = 1;
    }

    return ($index);
}



=head2 limit_queue

limit_Queue takes a paramhash with the fields operator and value.
operator is one of = or !=. (It defaults to =).
value is a queue id or name.


=cut

sub limit_queue {
    my $self = shift;
    my %args = (
        value    => undef,
        operator => '=',
        @_
    );

    #TODO  value should also take queue objects
    if ( defined $args{'value'} && $args{'value'} !~ /^\d+$/ ) {
        my $queue = RT::Model::Queue->new();
        $queue->load( $args{'value'} );
        $args{'value'} = $queue->id;
    }

    # What if they pass in an Id?  Check for isNum() and convert to
    # string.

    #TODO check for a valid queue here

    $self->limit(
        column      => 'queue',
        value       => $args{'value'},
        operator    => $args{'operator'},
        description => join( ' ', _('queue'), $args{'operator'}, $args{'value'}, ),
    );

}



=head2 limit_status

Takes a paramhash with the fields operator and value.
operator is one of = or !=.
value is a status.

RT adds Status != 'deleted' until object has
allow_deleted_search internal property set.
$tickets->{'allow_deleted_search'} = 1;
$tickets->limit_status( value => 'deleted' );

=cut

sub limit_status {
    my $self = shift;
    my %args = (
        operator => '=',
        @_
    );
    $self->limit(
        column      => 'status',
        value       => $args{'value'},
        operator    => $args{'operator'},
        description => join( ' ', _('Status'), $args{'operator'}, _( $args{'value'} ) ),
    );
}



=head2 ignore_type

If called, this search will not automatically limit the set of results found
to tickets of type "Ticket". Tickets of other types, such as "project" and
"approval" will be found.

=cut

sub ignore_type {
    my $self = shift;

    # Instead of faking a Limit that later gets ignored, fake up the
    # fact that we're already looking at type, so that the check in
    # Tickets_Overlay_SQL/from_sql goes down the right branch

    #  $self->limit_type(value => '__any');
    $self->{looking_at_type} = 1;
}



=head2 limit_type

Takes a paramhash with the fields operator and value.
operator is one of = or !=, it defaults to "=".
value is a string to search for in the type of the ticket.



=cut

sub limit_type {
    my $self = shift;
    my %args = (
        operator => '=',
        value    => undef,
        @_
    );
    $self->limit(
        column      => 'type',
        value       => $args{'value'},
        operator    => $args{'operator'},
        description => join( ' ', _('type'), $args{'operator'}, $args{'Limit'}, ),
    );
}




=head2 limit_watcher

  Takes a paramhash with the fields operator, type and value.
  operator is one of =, LIKE, NOT LIKE or !=.
  value is a value to match the ticket\'s watcher email addresses against
  type is the sort of watchers you want to match against. Leave it undef if you want to search all of them


=cut

sub limit_watcher {
    my $self = shift;
    my %args = (
        operator => '=',
        value    => undef,
        type     => undef,
        @_
    );

    #build us up a description
    my ( $watcher_type, $desc );
    if ( $args{'type'} ) {
        $watcher_type = $args{'type'};
    } else {
        $watcher_type = "Watcher";
    }

    $self->limit(
        column      => $watcher_type,
        value       => $args{'value'},
        operator    => $args{'operator'},
        type        => $args{'type'},
        description => join( ' ', _($watcher_type), $args{'operator'}, $args{'value'}, ),
    );
}






=head2 limit_linked_to

limit_linked_to takes a paramhash with two fields: type and target
type limits the sort of link we want to search on

type = { RefersTo, MemberOf, DependsOn }

target is the id or URI of the target of the link

=cut

sub limit_linked_to {
    my $self = shift;
    my %args = (
        target   => undef,
        type     => undef,
        operator => '=',
        @_
    );

    $self->limit(
        column      => 'LinkedTo',
        base        => undef,
        target      => $args{'target'},
        type        => $args{'type'},
        description => _( "Tickets %1 by %2", _( $args{'type'} ), $args{'target'} ),
        operator    => $args{'operator'},
    );
}



=head2 limit_linked_from

limit_LinkedFrom takes a paramhash with two fields: type and base
type limits the sort of link we want to search on


base is the id or URI of the base of the link

=cut

sub limit_linked_from {
    my $self = shift;
    my %args = (
        base     => undef,
        type     => undef,
        operator => '=',
        @_
    );

    # translate RT2 From/To naming to RT3 TicketSQL naming
    my %fromToMap = qw(DependsOn DependentOn
        MemberOf  has_member
        RefersTo  ReferredToBy);

    my $type = $args{'type'};
    $type = $fromToMap{$type} if exists( $fromToMap{$type} );

    $self->limit(
        column      => 'LinkedTo',
        target      => undef,
        base        => $args{'base'},
        type        => $type,
        description => _( "Tickets %1 %2", _( $args{'type'} ), $args{'base'}, ),
        operator    => $args{'operator'},
    );
}


sub limit_member_of {
    my $self      = shift;
    my $ticket_id = shift;
    return $self->limit_linked_to(
        @_,
        target => $ticket_id,
        type   => 'MemberOf',
    );
}


sub limit_has_member {
    my $self      = shift;
    my $ticket_id = shift;
    return $self->limit_linked_from(
        @_,
        base => "$ticket_id",
        type => 'has_member',
    );

}



sub limitdepends_on {
    my $self      = shift;
    my $ticket_id = shift;
    return $self->limit_linked_to(
        @_,
        target => $ticket_id,
        type   => 'DependsOn',
    );

}



sub limit_depended_on_by {
    my $self      = shift;
    my $ticket_id = shift;
    return $self->limit_linked_from(
        @_,
        base => $ticket_id,
        type => 'DependentOn',
    );

}



sub limit_refers_to {
    my $self      = shift;
    my $ticket_id = shift;
    return $self->limit_linked_to(
        @_,
        target => $ticket_id,
        type   => 'RefersTo',
    );

}



sub limit_referred_to_by {
    my $self      = shift;
    my $ticket_id = shift;
    return $self->limit_linked_from(
        @_,
        base => $ticket_id,
        type => 'ReferredToBy',
    );
}




=head2 _next_index

Keep track of the counter for the array of restrictions

=cut

sub next_index {
    my $self = shift;
    return ( $self->{'restriction_index'}++ );
}




sub _init {
    my $self = shift;
    $self->{'RecalcTicketLimits'}      = 1;
    $self->{'looking_at_effective_id'} = 0;
    $self->{'looking_at_type'}         = 0;
    $self->{'restriction_index'}       = 1;
    $self->{'primary_key'}             = "id";
    delete $self->{'items_array'};
    delete $self->{'item_map'};
    delete $self->{'columns_to_display'};
    $self->SUPER::_init(@_);

    $self->_init_sql;

}


sub count {
    my $self = shift;
    $self->_process_restrictions() if ( $self->{'RecalcTicketLimits'} == 1 );
    return ( $self->SUPER::count() );
}


sub count_all {
    my $self = shift;
    $self->_process_restrictions() if ( $self->{'RecalcTicketLimits'} == 1 );
    return ( $self->SUPER::count_all() );
}



=head2 items_array_ref

Returns a reference to the set of all items found in this search

=cut

sub items_array_ref {
    my $self = shift;

    unless ( $self->{'items_array'} ) {

        my $placeholder = $self->_items_counter;
        $self->goto_first_item();
        while ( my $item = $self->next ) {
            push( @{ $self->{'items_array'} }, $item );
        }
        $self->goto_item($placeholder);
        $self->{'items_array'} = $self->items_order_by( $self->{'items_array'} );
    }
    return ( $self->{'items_array'} );
}


sub next {
    my $self = shift;

    $self->_process_restrictions() if ( $self->{'RecalcTicketLimits'} == 1 );

    my $Ticket = $self->SUPER::next;
    return $Ticket unless $Ticket;
    if ( $Ticket->__value('status') eq 'deleted'
        && !$self->{'allow_deleted_search'} )
    {
        return $self->next;
    }
    elsif ( RT->config->get('UseSQLForACLChecks') ) {
    
        # if we found a ticket with this option enabled then
        # all tickets we found are ACLed, cache this fact
        my $key = join ";:;", $self->current_user->id, 'ShowTicket',
          'RT::Model::Ticket-' . $Ticket->id;
        $RT::Principal::_ACL_CACHE->set( $key => 1 );
        return $Ticket;
    }
    elsif ( $Ticket->current_user_has_right('ShowTicket') ) {
        # has rights
        return $Ticket;
    }
    else {

        # If the user doesn't have the right to show this ticket
        return $self->next;
    }
}

sub _do_search {
    my $self = shift;
    $self->current_user_can_see if RT->config->get('UseSQLForACLChecks');
    return $self->SUPER::_do_search(@_);
}

sub _docount {
    my $self = shift;
    $self->current_user_can_see if RT->config->get('UseSQLForACLChecks');
    return $self->SUPER::_docount(@_);
}


sub _roles_can_see {
    my $self = shift;
    my $cache_key = 'Roleshas_right;:;ShowTicket';

    if ( my $cached = $RT::Principal::_ACL_CACHE->fetch($cache_key) ) {
        return %$cached;
    }

    my $ACL = RT::ACL->new(RT->system_user);
    $ACL->limit( column => 'right_name', value => 'ShowTicket' );
    $ACL->limit( column => 'type', operator => '!=', value => 'Group' );
    my $principal_alias = $ACL->join(
        alias1 => 'main',
        column1 => 'principal_id',
        table2 => 'Principals',
        column2 => 'id',
    );
    $ACL->limit( alias => $principal_alias, column => 'disabled', value => 0 );

    my %res = ();
    while ( my $ACE = $ACL->next ) {
        my $role = $ACE->principal_type;
        my $type = $ACE->object_type;
        if ( $type eq 'RT::System' ) {
            $res{$role} = 1;
        }
        elsif ( $type eq 'RT::Model::Queue' ) {
            next if $res{$role} && !ref $res{$role};
            push @{ $res{$role} ||= [] }, $ACE->objectid;
        }
        else {
            Jifty->log->error(
                'ShowTicket right is granted on unsupported object');
        }
    }
    $RT::Principal::_ACL_CACHE->set( $cache_key => \%res );
    return %res;
}
 
sub _directly_can_see_in {
    my $self = shift;
    my $id   = $self->current_user->id;

    my $cache_key = 'User-' . $id . ';:;ShowTicket;:;DirectlyCanSeeIn';
    if ( my $cached = $RT::Principal::_ACL_CACHE->fetch($cache_key) ) {
        return @$cached;
    }

    my $ACL = RT::ACL->new(RT->system_user);
    $ACL->limit( column => 'right_name', value => 'ShowTicket' );
    my $principal_alias = $ACL->join(
        alias1 => 'main',
        column1 => 'principal_id',
        table2 => 'Principals',
        column2 => 'id',
    );
    $ACL->limit( alias => $principal_alias, column => 'disabled', value => 0 );
    my $cgm_alias = $ACL->join(
        alias1 => 'main',
        column1 => 'principal_id',
        table2 => 'CachedGroupMembers',
        column2 => 'group_id',
    );
    $ACL->limit( alias => $cgm_alias, column => 'member_id', value => $id );
    $ACL->limit( alias => $cgm_alias, column => 'disabled', value => 0 );

    my @res = ();
    while ( my $ACE = $ACL->next ) {
        my $type = $ACE->object_type;
        if ( $type eq 'RT::System' ) {

            # If user is direct member of a group that has the right
            # on the system then he can see any ticket
            $RT::Principal::_ACL_CACHE->set( $cache_key => [-1] );
            return (-1);
        }
        elsif ( $type eq 'RT::Model::Queue' ) {
            push @res, $ACE->object_id;
        }
         else {
            Jifty->log->error(
                'ShowTicket right is granted on unsupported object');
        }
    }
    $RT::Principal::_ACL_CACHE->set( $cache_key => \@res );
    return @res;
}

sub current_user_can_see {
    my $self = shift;
    return if $self->{'_sql_current_user_can_see_applied'};

    return $self->{'_sql_current_user_can_see_applied'} = 1
      if $self->current_user->user_object->has_right(
        right  => 'SuperUser',
        object => RT->system
      );

    my $id = $self->current_user->id;

    my @direct_queues = $self->_directly_can_see_in;
    return $self->{'_sql_current_user_can_see_applied'} = 1
      if @direct_queues && $direct_queues[0] == -1;

    my %roles = $self->_roles_can_see;
    {
        my %skip = map { $_ => 1 } @direct_queues;
        foreach my $role ( keys %roles ) {
            next unless ref $roles{$role};

            my @queues = grep !$skip{$_}, @{ $roles{$role} };
            if (@queues) {
                $roles{$role} = \@queues;
            }
            else {
                delete $roles{$role};
            }
        }
    }

    {
        my $join_roles = keys %roles;
        $join_roles = 0 if $join_roles == 1 && $roles{'Owner'};
        my ( $role_group_alias, $cgm_alias );
        if ($join_roles) {
            $role_group_alias = $self->_role_groupsjoin( new => 1 );
            $cgm_alias =
              $self->_group_membersjoin( groups_alias => $role_group_alias );
            $self->SUPER::limit(
                leftjoin => $cgm_alias,
                column    => 'member_id',
                operator => '=',
                value    => $id,
            );
        }
        my $limit_queues = sub {
            my $ea     = shift;
            my @queues = @_;

            return unless @queues;
            if ( @queues == 1 ) {
                $self->_sql_limit(
                    alias           => 'main',
                    column           => 'queue',
                    value           => $_[0],
                    entry_aggregator => $ea,
                );
            }
            else {
                $self->_open_paren;
                foreach my $q (@queues) {
                    $self->_sql_limit(
                        alias           => 'main',
                        column           => 'queue',
                        value           => $q,
                        entry_aggregator => $ea,
                    );
                    $ea = 'OR';
                }
                $self->_close_paren;
            }
            return 1;
        };

        $self->_open_paren;
        my $ea = 'AND';
        $ea = 'OR' if $limit_queues->( $ea, @direct_queues );
        while ( my ( $role, $queues ) = each %roles ) {
            $self->_open_paren;
            if ( $role eq 'Owner' ) {
                $self->_sql_limit(
                    column           => 'Owner',
                    value           => $id,
                    entry_aggregator => $ea,
                );
            }
            else {
                $self->_sql_limit(
                    alias           => $cgm_alias,
                    column           => 'member_id',
                    operator        => 'IS NOT',
                    value           => 'NULL',
                    quote_value      => 0,
                    entry_aggregator => $ea,
                );
                $self->_sql_limit(
                    alias           => $role_group_alias,
                    column           => 'type',
                    value           => $role,
                    entry_aggregator => 'AND',
                );
            }
            $limit_queues->( 'AND', @$queues ) if ref $queues;
            $ea = 'OR' if $ea eq 'AND';
            $self->_close_paren;
        }
        $self->_close_paren;
    }
    return $self->{'_sql_current_user_can_see_applied'} = 1;
}


# Convert a set of oldstyle SB Restrictions to Clauses for RQL

sub _restrictions_to_clauses {
    my $self = shift;

    my $row;
    my %clause;
    foreach $row ( keys %{ $self->{'TicketRestrictions'} } ) {
        my $restriction = $self->{'TicketRestrictions'}{$row};

        # We need to reimplement the subclause aggregation that SearchBuilder does.
        # Default Subclause is alias.column, and default alias is 'main',
        # Then SB AND's the different Subclauses together.

        # So, we want to group things into Subclauses, convert them to
        # SQL, and then join them with the appropriate DefaultEA.
        # Then join each subclause group with AND.

        my $field     = $restriction->{'column'};
        my $realfield = $field;                     # CustomFields fake up a fieldname, so
                                                    # we need to figure that out

        # One special case
        # Rewrite linked_to meta field to the real field
        if ( $field =~ /LinkedTo/ ) {
            $realfield = $field = $restriction->{'type'};
        }

        # Two special case
        # Handle subkey fields with a different real field
        if ( $field =~ /^(\w+)\./ ) {
            $realfield = $1;
        }

        die "I don't know about $field yet"
            unless ( exists $FIELD_METADATA{$realfield}
            or $restriction->{customfield} );

        my $type = $FIELD_METADATA{$realfield}->[0];
        my $op   = $restriction->{'operator'};

        my $value = (
            grep    {defined}
                map { $restriction->{$_} } qw(value TICKET base target)
        )[0];

        # this performs the moral equivalent of defined or/dor/C<//>,
        # without the short circuiting.You need to use a 'defined or'
        # type thing instead of just checking for truth values, because
        # value could be 0.(i.e. "false")

        # You could also use this, but I find it less aesthetic:
        # (although it does short circuit)
        #( defined $restriction->{'value'}? $restriction->{value} :
        # defined $restriction->{'TICKET'} ?
        # $restriction->{TICKET} :
        # defined $restriction->{'base'} ?
        # $restriction->{base} :
        # defined $restriction->{'target'} ?
        # $restriction->{target} )

        my $ea 
            = $restriction->{entry_aggregator}
            || $DefaultEA{$type}
            || "AND";
        if ( ref $ea ) {
            die "Invalid operator $op for $field ($type)"
                unless exists $ea->{$op};
            $ea = $ea->{$op};
        }

        # Each CustomField should be put into a different Clause so they
        # are ANDed together.
        if ( $restriction->{customfield} ) {
            $realfield = $field;
        }

        exists $clause{$realfield} or $clause{$realfield} = [];

        # Escape Quotes
        $field =~ s!(['"])!\\$1!g;
        $value =~ s!(['"])!\\$1!g;
        my $data = [ $ea, $type, $field, $op, $value ];

        # here is where we store extra data, say if it's a keyword or
        # something.  (I.e. "type SPECIFIC STUFF")

        push @{ $clause{$realfield} }, $data;
    }
    return \%clause;
}



=head2 _process_restrictions PARAMHASH

# The new _ProcessRestrictions is somewhat dependent on the SQL stuff,
# but isn't quite generic enough to move into Tickets_Overlay_SQL.

=cut

sub _process_restrictions {
    my $self = shift;

    #Blow away ticket aliases since we'll need to regenerate them for
    #a new search
    delete $self->{'TicketAliases'};
    delete $self->{'items_array'};
    delete $self->{'item_map'};
    delete $self->{'raw_rows'};
    delete $self->{'rows'};
    delete $self->{'count_all'};

    my $sql = $self->query;    # Violating the _SQL namespace
    if ( !$sql || $self->{'RecalcTicketLimits'} ) {

        #  "Restrictions to Clauses Branch\n";
        my $clauseRef = eval { $self->_restrictions_to_clauses; };
        if ($@) {
            Jifty->log->error( "RestrictionsToClauses: " . $@ );
            $self->from_sql("");
        } else {
            $sql = $self->clauses_to_sql($clauseRef);
            $self->from_sql($sql) if $sql;
        }
    }

    $self->{'RecalcTicketLimits'} = 0;

}

=head2 _build_item_map

    # Build up a map of first/last/next/prev items, so that we can display search nav quickly

=cut

sub _build_item_map {
    my $self = shift;

    my $items = $self->items_array_ref;
    my $prev  = 0;

    delete $self->{'item_map'};
    if ( $items->[0] ) {
        $self->{'item_map'}->{'first'} = $items->[0]->effective_id;
        while ( my $item = shift @$items ) {
            my $id = $item->effective_id;
            $self->{'item_map'}->{$id}->{'defined'} = 1;
            $self->{'item_map'}->{$id}->{prev}      = $prev;
            $self->{'item_map'}->{$id}->{next}      = $items->[0]->effective_id
                if ( $items->[0] );
            $prev = $id;
        }
        $self->{'item_map'}->{'last'} = $prev;
    }
}

=head2 item_map

Returns an a map of all items found by this search. The map is of the form

$ItemMap->{'first'} = first ticketid found
$ItemMap->{'last'} = last ticketid found
$ItemMap->{$id}->{prev} = the ticket id found before $id
$ItemMap->{$id}->{next} = the ticket id found after $id

=cut

sub item_map {
    my $self = shift;
    $self->_build_item_map()
        unless ( $self->{'items_array'} and $self->{'item_map'} );
    return ( $self->{'item_map'} );
}

=cut



}





=head2 prep_for_serialization

You don't want to serialize a big tickets object, as the {items} hash will be instantly invalid _and_ eat lots of space

=cut

sub prep_for_serialization {
    my $self = shift;
    delete $self->{'items'};
    $self->redo_search();
}

use RT::SQL;

# Import configuration data from the lexcial scope of __PACKAGE__ (or
# at least where those two Subroutines are defined.)

# Lower Case version of columns, for case insensitivity
my %lcfields = map { ( lc($_) => $_ ) } ( keys %FIELD_METADATA );

sub _init_sql {
    my $self = shift;

    # Private Member Variables (which should get cleaned)
    $self->{'_sql_transalias'}               = undef;
    $self->{'_sql_trattachalias'}            = undef;
    $self->{'_sql_cf_alias'}                 = undef;
    $self->{'_sql_object_cfv_alias'}         = undef;
    $self->{'_sql_watcher_join_users_alias'} = undef;
    $self->{'_sql_query'}                    = '';
    $self->{'_sql_looking_at'}               = {};
}

sub _sql_limit {
    my $self = shift;
    my %args = (@_);
    if ( $args{'column'} eq 'effective_id'
        && ( !$args{'alias'} || $args{'alias'} eq 'main' ) )
    {
        $self->{'looking_at_effective_id'} = 1;
    }

    if ( $args{'column'} eq 'type'
        && ( !$args{'alias'} || $args{'alias'} eq 'main' ) )
    {
        $self->{'looking_at_type'} = 1;
    }

    # All SQL stuff goes into one SB subclause so we can deal with all
    # the aggregation
    $self->SUPER::limit( %args, subclause => 'ticketsql' );
}

sub _sql_join {

    # All SQL stuff goes into one SB subclause so we can deal with all
    # the aggregation
    my $this = shift;

    $this->join( @_, subclause => 'ticketsql' );
}

# Helpers
sub open_paren {
    $_[0]->SUPER::open_paren('ticketsql');
}

sub close_paren {
    $_[0]->SUPER::close_paren('ticketsql');
}

=head1 SQL Functions

=cut

=head2 robert's Simple SQL Parser

Documentation In Progress

The Parser/Tokenizer is a relatively simple state machine that scans through a SQL WHERE clause type string extracting a token at a time (where a token is:

  value -> quoted string or number
  AGGREGator -> AND or OR
  KEYWORD -> quoted string or single word
  OPerator -> =,!=,LIKE,etc..
  PARENthesis -> open or close.

And that stream of tokens is passed through the "machine" in order to build up a structure that looks like:

       KEY OP value
  AND  KEY OP value
  OR   KEY OP value

That also deals with parenthesis for nesting.  (The parentheses are
just handed off the SearchBuilder)

=cut

sub _close_bundle {
    my ( $self, @bundle ) = @_;
    return unless @bundle;

    if ( @bundle == 1 ) {
        $bundle[0]->{'dispatch'}->(
            $self,
            $bundle[0]->{'key'},
            $bundle[0]->{'op'},
            $bundle[0]->{'val'},
            subclause        => '',
            entry_aggregator => $bundle[0]->{ea},
            subkey           => $bundle[0]->{subkey},
        );
    } else {
        my @args;
        foreach my $chunk (@bundle) {
            push @args,
                [
                $chunk->{key},
                $chunk->{op},
                $chunk->{val},
                subclause        => '',
                entry_aggregator => $chunk->{ea},
                subkey           => $chunk->{subkey},
                ];
        }
        $bundle[0]->{dispatch}->( $self, \@args );
    }
}

sub _parser {
    my ( $self, $string ) = @_;
    my @bundle;
    my $ea = '';

    my %callback;
    $callback{'open_paren'} = sub {
        $self->_close_bundle(@bundle);
        @bundle = ();
        $self->open_paren;
    };
    $callback{'close_paren'} = sub {
        $self->_close_bundle(@bundle);
        @bundle = ();
        $self->close_paren;
    };
    $callback{'entry_aggregator'} = sub { $ea = $_[0] || '' };
    $callback{'Condition'} = sub {
        my ( $key, $op, $value ) = @_;

        # key has dot then it's compound variant and we have subkey
        my $subkey = '';
        ( $key, $subkey ) = ( $1, $2 ) if $key =~ /^([^\.]+)\.(.+)$/;

        # normalize key and get class (type)
        my $class;
        if ( exists $lcfields{ lc $key } ) {
            $key   = $lcfields{ lc $key };
            $class = $FIELD_METADATA{$key}->[0];
        }
        die "Unknown field '$key' in '$string'" unless $class;

        # replace __CurrentUser__ with id
        $value = $self->current_user->id if $value eq '__CurrentUser__';

        unless ( $dispatch{$class} ) {
            die "No dispatch method for class '$class'";
        }
        my $sub = $dispatch{$class};

        if ($can_bundle{$class}
            && (!@bundle
                || (   $bundle[-1]->{dispatch} == $sub
                    && $bundle[-1]->{key} eq $key
                    && $bundle[-1]->{subkey} eq $subkey )
            )
            )
        {
            push @bundle,
                {
                dispatch => $sub,
                key      => $key,
                op       => $op,
                val      => $value,
                ea       => $ea,
                subkey   => $subkey,
                };
        } else {
            $self->_close_bundle(@bundle);
            @bundle = ();
            $sub->(
                $self, $key, $op, $value,
                subclause        => '',        # don't need anymore
                entry_aggregator => $ea,
                subkey           => $subkey,
            );
        }
        $self->{_sql_looking_at}{ lc $key } = 1;
        $ea = '';
    };
    RT::SQL::parse( $string, \%callback );
    $self->_close_bundle(@bundle);
    @bundle = ();
}

=head2 clauses_to_sql

=cut

sub clauses_to_sql {
    my $self    = shift;
    my $clauses = shift;
    my @sql;

    for my $f ( keys %{$clauses} ) {
        my $sql;
        my $first = 1;

        # Build SQL from the data hash
        for my $data ( @{ $clauses->{$f} } ) {
            $sql .= $data->[0] unless $first;
            $first = 0;    # entry_aggregator
            $sql .= " '" . $data->[2] . "' ";    # column
            $sql .= $data->[3] . " ";            # operator
            $sql .= "'" . $data->[4] . "' ";     # value
        }

        push @sql, " ( " . $sql . " ) ";
    }

    return join( "AND", @sql );
}

=head2 from_sql

Convert a RT-SQL string into a set of SearchBuilder restrictions.

Returns (1, 'Status message') on success and (0, 'Error Message') on
failure.




=cut

sub from_sql {
    my ( $self, $query ) = @_;

    {

        # preserve first_row and show_rows across the clean_slate
        local ( $self->{'first_row'}, $self->{'show_rows'} );
        $self->clean_slate;
    }
    $self->_init_sql();

    return ( 1, _("No Query") ) unless $query;

    $self->{_sql_query} = $query;
    eval { $self->_parser($query); };
    if ($@) {
        Jifty->log->error($@);
        return ( 0, $@ );
    }

    # We only want to look at effective_id's (mostly) for these searches.
    unless ( exists $self->{_sql_looking_at}{'effectiveid'} ) {

        #TODO, we shouldn't be hard #coding the tablename to main.
        $self->SUPER::limit(
            column           => 'effective_id',
            value            => 'main.id',
            entry_aggregator => 'AND',
            quote_value      => 0,
        );
    }

    # FIXME: Need to bring this logic back in

    #      if ($self->_islimit_ed && (! $self->{'looking_at_effective_id'})) {
    #         $self->SUPER::limit( column => 'effective_id',
    #               operator => '=',
    #               quote_value => 0,
    #               value => 'main.id');   #TODO, we shouldn't be hard coding the tablename to main.
    #       }
    # --- This is hardcoded above.  This comment block can probably go.
    # Or, we need to reimplement the looking_at_effective_id toggle.

    # Unless we've explicitly asked to look at a specific Type, we need
    # to limit to it.
    unless ( $self->{looking_at_type} ) {
        $self->SUPER::limit( column => 'type', value => 'ticket' );
    }

    # We don't want deleted tickets unless 'allow_deleted_search' is set
    unless ( $self->{'allow_deleted_search'} ) {
        $self->SUPER::limit(
            column   => 'status',
            operator => '!=',
            value    => 'deleted',
        );
    }

    # set SB's dirty flag
    $self->{'must_redo_search'}   = 1;
    $self->{'RecalcTicketLimits'} = 0;

    return ( 1, _("Valid Query") );
}

=head2 query

Returns the query that this object was initialized with

=cut

sub query {
    return ( $_[0]->{_sql_query} );
}

1;

=pod

=head2 exceptions

Most of the RT code does not use Exceptions (die/eval) but it is used
in the TicketSQL code for simplicity and historical reasons.  Lest you
be worried that the dies will trigger user visible errors, all are
trapped via evals.

99% of the dies fall in subroutines called via from_sql and then parse.
(This includes all of the _FooLimit routines in TicketCollection_Overlay.pm.)
The other 1% or so are via _ProcessRestrictions.

All dies are trapped by eval {}s, and will be logged at the 'error'
log level.  The general failure mode is to not display any tickets.

=head2 general Flow

Legacy Layer:

   Legacy limit_Foo routines build up a RestrictionsHash

   _ProcessRestrictions converts the Restrictions to Clauses
   ([key,op,val,rest]).

   Clauses are converted to RT-SQL (TicketSQL)

New RT-SQL Layer:

   from_sql calls the parser

   The parser calls the _FooLimit routines to do Jifty::DBI
   limits.

And then the normal SearchBuilder/Ticket routines are used for
display/navigation.

=cut

=head1 FLAGS

RT::Model::TicketCollection supports several flags which alter search behavior:


allow_deleted_search  (Otherwise never show deleted tickets in search results)
looking_at_type (otherwise limit to type=ticket)

These flags are set by calling 

$tickets->{'flagname'} = 1;

BUG: There should be an API for this

=cut

=cut

1;


