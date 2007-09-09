#!/usr/bin/perl -w
# BEGIN BPS TAGGED BLOCK {{{
# 
# COPYRIGHT:
#  
# This software is Copyright (c) 1996-2004 Best Practical Solutions, LLC 
#                                          <jesse.com>
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

=head1 NAME

rt-mailgate - Mail interface to RT3.

=cut

use strict;
use warnings;

use Test::More tests => 153;

use RT::Test config => 'set( $UnsafeEmailCommands, 1);';
my ($baseurl, $m) = RT::Test->started_ok;

use RT::Model::TicketCollection;

use MIME::Entity;
use Digest::MD5 qw(md5_base64);
use LWP::UserAgent;

# TODO: --extension queue

my $url = $m->rt_base_url;

sub latest_ticket {
    my $tickets = RT::Model::TicketCollection->new( $RT::SystemUser );
    $tickets->order_by( { column => 'id', order => 'DESC'} );
    $tickets->limit( column => 'id', operator => '>', value => '0' );
    $tickets->rows_per_page( 1 );
    return $tickets->first;
}

diag "Make sure that when we call the mailgate without URL, it fails" if $ENV{'TEST_VERBOSE'};
{
    my $text = <<EOF;
From: root\@localhost
To: rt\@@{[RT->Config->Get('rtname')]}
Subject: This is a test of new ticket creation

Foob!
EOF
    my ($status, $id) = RT::Test->send_via_mailgate($text, url => undef);
    is ($status >> 8, 1, "The mail gateway exited with a failure");
    ok (!$id, "No ticket id") or diag "by mistake ticket #$id";
}

diag "Make sure that when we call the mailgate with wrong URL, it tempfails" if $ENV{'TEST_VERBOSE'};
{
    my $text = <<EOF;
From: root\@localhost
To: rt\@@{[RT->Config->Get('rtname')]}
Subject: This is a test of new ticket creation

Foob!
EOF
    my ($status, $id) = RT::Test->send_via_mailgate($text, url => 'http://this.test.for.non-connection.is.expected.to.generate.an.error');
    is ($status >> 8, 75, "The mail gateway exited with a failure");
    ok (!$id, "No ticket id");
}

my $everyone_group;
diag "revoke rights tests depend on" if $ENV{'TEST_VERBOSE'};
{
    $everyone_group = RT::Model::Group->new( $RT::SystemUser );
    $everyone_group->load_system_internal_group( 'Everyone' );
    ok ($everyone_group->id, "Found group 'everyone'");

    foreach( qw(CreateTicket ReplyToTicket CommentOnTicket) ) {
        $everyone_group->PrincipalObj->RevokeRight(Right => $_);
    }
}

diag "Test new ticket creation by root who is privileged and superuser" if $ENV{'TEST_VERBOSE'};
{
    my $text = <<EOF;
From: root\@localhost
To: rt\@@{[RT->Config->Get('rtname')]}
Subject: This is a test of new ticket creation

Blah!
Foob!
EOF

    my ($status, $id) = RT::Test->send_via_mailgate($text);
    is ($status >> 8, 0, "The mail gateway exited normally");
    ok ($id, "Created ticket");

    my $tick = latest_ticket();
    isa_ok ($tick, 'RT::Model::Ticket');
    is ($tick->id, $id, "correct ticket id");
    is ($tick->Subject , 'This is a test of new ticket creation', "Created the ticket");
}

diag "Test the 'X-RT-Mail-Extension' field in the header of a ticket" if $ENV{'TEST_VERBOSE'};
{
    my $text = <<EOF;
From: root\@localhost
To: rt\@@{[RT->Config->Get('rtname')]}
Subject: This is a test of the X-RT-Mail-Extension field
Blah!
Foob!
EOF
    local $ENV{'EXTENSION'} = "bad value with\nnewlines\n";
    my ($status, $id) = RT::Test->send_via_mailgate($text);
    is ($status >> 8, 0, "The mail gateway exited normally");
    ok ($id, "Created ticket #$id");

    my $tick = latest_ticket();
    isa_ok ($tick, 'RT::Model::Ticket');
    is ($tick->id, $id, "correct ticket id");
    is ($tick->Subject, 'This is a test of the X-RT-Mail-Extension field', "Created the ticket");

    my $transactions = $tick->Transactions;
    $transactions->order_by({ column => 'id', order => 'DESC' });
    $transactions->limit( column => 'Type', operator => '!=', value => 'EmailRecord');
    my $txn = $transactions->first;
    isa_ok ($txn, 'RT::Model::Transaction');
    is ($txn->Type, 'Create', "correct type");

    my $attachment = $txn->Attachments->first;
    isa_ok ($attachment, 'RT::Model::Attachment');
    # XXX: We eat all newlines in header, that's not what RFC's suggesting
    is (
        $attachment->GetHeader('X-RT-Mail-Extension'),
        "bad value with newlines",
        'header is in place, without trailing newline char'
    );
}

diag "Make sure that not standard --extension is passed" if $ENV{'TEST_VERBOSE'};
{
    my $text = <<EOF;
From: root\@localhost
To: rt\@@{[RT->Config->Get('rtname')]}
Subject: This is a test of new ticket creation

Foob!
EOF
    my ($status, $id) = RT::Test->send_via_mailgate($text, extension => 'some-extension-arg' );
    is ($status >> 8, 0, "The mail gateway exited normally");
    ok ($id, "Created ticket #$id");

    my $tick = latest_ticket();
    isa_ok ($tick, 'RT::Model::Ticket');
    is ($tick->id, $id, "correct ticket id");

    my $transactions = $tick->Transactions;
    $transactions->order_by({ column => 'id', order => 'DESC' });
    $transactions->limit( column => 'Type', operator => '!=', value => 'EmailRecord');
    my $txn = $transactions->first;
    isa_ok ($txn, 'RT::Model::Transaction');
    is ($txn->Type, 'Create', "correct type");

    my $attachment = $txn->Attachments->first;
    isa_ok ($attachment, 'RT::Model::Attachment');
    is (
        $attachment->GetHeader('X-RT-Mail-Extension'),
        'some-extension-arg',
        'header is in place'
    );
}

diag "Test new ticket creation without --action argument" if $ENV{'TEST_VERBOSE'};
{
    my $text = <<EOF;
From: root\@localhost
To: rt\@$RT::rtname
Subject: using mailgate without --action arg

Blah!
Foob!
EOF
    my ($status, $id) = RT::Test->send_via_mailgate($text, extension => 'some-extension-arg' );
    is ($status >> 8, 0, "The mail gateway exited normally");
    ok ($id, "Created ticket #$id");

    my $tick = latest_ticket();
    isa_ok ($tick, 'RT::Model::Ticket');
    is ($tick->id, $id, "correct ticket id");
    is ($tick->Subject, 'using mailgate without --action arg', "using mailgate without --action arg");
}

diag "This is a test of new ticket creation as an unknown user" if $ENV{'TEST_VERBOSE'};
{
    my $text = <<EOF;
From: doesnotexist\@@{[RT->Config->Get('rtname')]}
To: rt\@@{[RT->Config->Get('rtname')]}
Subject: This is a test of new ticket creation as an unknown user

Blah!
Foob!
EOF
    my ($status, $id) = RT::Test->send_via_mailgate($text);
    is ($status >> 8, 0, "The mail gateway exited normally");
    ok (!$id, "no ticket Created");

    my $tick = latest_ticket();
    isa_ok ($tick, 'RT::Model::Ticket');
    ok ($tick->id, "found ticket ".$tick->id);
    isnt ($tick->Subject , 'This is a test of new ticket creation as an unknown user', "failed to create the new ticket from an unprivileged account");

    my $u = RT::Model::User->new($RT::SystemUser);
    $u->load("doesnotexist\@@{[RT->Config->Get('rtname')]}");
    ok( !$u->id, "user does not exist and was not Created by failed ticket submission");
}

diag "grant everybody with CreateTicket right" if $ENV{'TEST_VERBOSE'};
{
    ok( RT::Test->set_rights(
        { Principal => $everyone_group->PrincipalObj,
          Right => [qw(CreateTicket)],
        },
    ), "Granted everybody the right to create tickets");
}

my $ticket_id;
diag "now everybody can create tickets. can a random unkown user create tickets?" if $ENV{'TEST_VERBOSE'};
{
    my $text = <<EOF;
From: doesnotexist\@@{[RT->Config->Get('rtname')]}
To: rt\@@{[RT->Config->Get('rtname')]}
Subject: This is a test of new ticket creation as an unknown user

Blah!
Foob!
EOF
    my ($status, $id) = RT::Test->send_via_mailgate($text);
    is ($status >> 8, 0, "The mail gateway exited normally");
    ok ($id, "ticket Created");

    my $tick = latest_ticket();
    isa_ok ($tick, 'RT::Model::Ticket');
    ok ($tick->id, "found ticket ".$tick->id);
    is ($tick->id, $id, "correct ticket id");
    is ($tick->Subject , 'This is a test of new ticket creation as an unknown user', "failed to create the new ticket from an unprivileged account");

    my $u = RT::Model::User->new( $RT::SystemUser );
    $u->load( "doesnotexist\@@{[RT->Config->Get('rtname')]}" );
    ok ($u->id, "user does not exist and was Created by ticket submission");
    $ticket_id = $id;
}

diag "can another random reply to a ticket without being granted privs? answer should be no." if $ENV{'TEST_VERBOSE'};
{
    my $text = <<EOF;
From: doesnotexist-2\@@{[RT->Config->Get('rtname')]}
To: rt\@@{[RT->Config->Get('rtname')]}
Subject: [@{[RT->Config->Get('rtname')]} #$ticket_id] This is a test of a reply as an unknown user

Blah!  (Should not work.)
Foob!
EOF
    my ($status, $id) = RT::Test->send_via_mailgate($text);
    is ($status >> 8, 0, "The mail gateway exited normally");
    ok (!$id, "no way to reply to the ticket");

    my $u = RT::Model::User->new($RT::SystemUser);
    $u->load('doesnotexist-2@'.RT->Config->Get('rtname'));
    ok( !$u->id, " user does not exist and was not Created by ticket correspondence submission");
}

diag "grant everyone 'ReplyToTicket' right" if $ENV{'TEST_VERBOSE'};
{
    ok( RT::Test->set_rights(
        { Principal => $everyone_group->PrincipalObj,
          Right => [qw(CreateTicket ReplyToTicket)],
        },
    ), "Granted everybody the right to reply to tickets" );
}

diag "can another random reply to a ticket after being granted privs? answer should be yes" if $ENV{'TEST_VERBOSE'};
{
    my $text = <<EOF;
From: doesnotexist-2\@@{[RT->Config->Get('rtname')]}
To: rt\@@{[RT->Config->Get('rtname')]}
Subject: [@{[RT->Config->Get('rtname')]} #$ticket_id] This is a test of a reply as an unknown user

Blah!
Foob!
EOF
    my ($status, $id) = RT::Test->send_via_mailgate($text);
    is ($status >> 8, 0, "The mail gateway exited normally");
    is ($id, $ticket_id, "replied to the ticket");

    my $u = RT::Model::User->new($RT::SystemUser);
    $u->load('doesnotexist-2@'.RT->Config->Get('rtname'));
    ok ($u->id, "user exists and was Created by ticket correspondence submission");
}

diag "add a reply to the ticket using '--extension ticket' feature" if $ENV{'TEST_VERBOSE'};
{
    my $text = <<EOF;
From: doesnotexist-2\@@{[RT->Config->Get('rtname')]}
To: rt\@@{[RT->Config->Get('rtname')]}
Subject: This is a test of a reply as an unknown user

Blah!
Foob!
EOF
    local $ENV{'EXTENSION'} = $ticket_id;
    my ($status, $id) = RT::Test->send_via_mailgate($text, extension => 'ticket');
    is ($status >> 8, 0, "The mail gateway exited normally");
    is ($id, $ticket_id, "replied to the ticket");

    my $tick = latest_ticket();
    isa_ok ($tick, 'RT::Model::Ticket');
    ok ($tick->id, "found ticket ".$tick->id);
    is ($tick->id, $id, "correct ticket id");

    my $transactions = $tick->Transactions;
    $transactions->order_by({ column => 'id', order => 'DESC' });
    $transactions->limit( column => 'Type', operator => '!=', value => 'EmailRecord');
    my $txn = $transactions->first;
    isa_ok ($txn, 'RT::Model::Transaction');
    is ($txn->Type, 'Correspond', "correct type");

    my $attachment = $txn->Attachments->first;
    isa_ok ($attachment, 'RT::Model::Attachment');
    is ($attachment->GetHeader('X-RT-Mail-Extension'), $id, 'header is in place');
}

diag "can another random comment on a ticket without being granted privs? answer should be no" if $ENV{'TEST_VERBOSE'};
{
    my $text = <<EOF;
From: doesnotexist-3\@@{[RT->Config->Get('rtname')]}
To: rt\@@{[RT->Config->Get('rtname')]}
Subject: [@{[RT->Config->Get('rtname')]} #$ticket_id] This is a test of a comment as an unknown user

Blah!  (Should not work.)
Foob!
EOF
    my ($status, $id) = RT::Test->send_via_mailgate($text, action => 'comment');
    is ($status >> 8, 0, "The mail gateway exited normally");
    ok (!$id, "no way to comment on the ticket");

    my $u = RT::Model::User->new($RT::SystemUser);
    $u->load('doesnotexist-3@'.RT->Config->Get('rtname'));
    ok( !$u->id, " user does not exist and was not Created by ticket comment submission");
}


diag "grant everyone 'CommentOnTicket' right" if $ENV{'TEST_VERBOSE'};
{
    ok( RT::Test->set_rights(
        { Principal => $everyone_group->PrincipalObj,
          Right => [qw(CreateTicket ReplyToTicket CommentOnTicket)],
        },
    ), "Granted everybody the right to comment on tickets");
}

diag "can another random reply to a ticket after being granted privs? answer should be yes" if $ENV{'TEST_VERBOSE'};
{
    my $text = <<EOF;
From: doesnotexist-3\@@{[RT->Config->Get('rtname')]}
To: rt\@@{[RT->Config->Get('rtname')]}
Subject: [@{[RT->Config->Get('rtname')]} #$ticket_id] This is a test of a comment as an unknown user

Blah!
Foob!
EOF
    my ($status, $id) = RT::Test->send_via_mailgate($text, action => 'comment');
    is ($status >> 8, 0, "The mail gateway exited normally");
    is ($id, $ticket_id, "replied to the ticket");

    my $u = RT::Model::User->new($RT::SystemUser);
    $u->load('doesnotexist-3@'.RT->Config->Get('rtname'));
    ok ($u->id, " user exists and was Created by ticket comment submission");
}

diag "add comment to the ticket using '--extension action' feature" if $ENV{'TEST_VERBOSE'};
{
    my $text = <<EOF;
From: doesnotexist-3\@@{[RT->Config->Get('rtname')]}
To: rt\@@{[RT->Config->Get('rtname')]}
Subject: [@{[RT->Config->Get('rtname')]} #$ticket_id] This is a test of a comment via '--extension action'

Blah!
Foob!
EOF
    local $ENV{'EXTENSION'} = 'comment';
    my ($status, $id) = RT::Test->send_via_mailgate($text, extension => 'action');
    is ($status >> 8, 0, "The mail gateway exited normally");
    is ($id, $ticket_id, "added comment to the ticket");

    my $tick = latest_ticket();
    isa_ok ($tick, 'RT::Model::Ticket');
    ok ($tick->id, "found ticket ".$tick->id);
    is ($tick->id, $id, "correct ticket id");

    my $transactions = $tick->Transactions;
    $transactions->order_by({ column => 'id', order => 'DESC' });
    $transactions->limit(
        column => 'Type',
        operator => 'NOT ENDSWITH',
        value => 'EmailRecord',
        entry_aggregator => 'AND',
    );
    my $txn = $transactions->first;
    isa_ok ($txn, 'RT::Model::Transaction');
    is ($txn->Type, 'Comment', "correct type");

    my $attachment = $txn->Attachments->first;
    isa_ok ($attachment, 'RT::Model::Attachment');
    is ($attachment->GetHeader('X-RT-Mail-Extension'), 'comment', 'header is in place');
}

diag "Testing preservation of binary attachments" if $ENV{'TEST_VERBOSE'};
{
    # Get a binary blob (Best Practical logo) 
    my $LOGO_FILE = $RT::MasonComponentRoot .'/NoAuth/images/bplogo.gif';

    # Create a mime entity with an attachment
    my $entity = MIME::Entity->build(
        From    => 'root@localhost',
        To      => 'rt@localhost',
        Subject => 'binary attachment test',
        Data    => ['This is a test of a binary attachment'],
    );

    $entity->attach(
        Path     => $LOGO_FILE,
        Type     => 'image/gif',
        Encoding => 'base64',
    );
    # Create a ticket with a binary attachment
    my ($status, $id) = RT::Test->send_via_mailgate($entity);
    is ($status >> 8, 0, "The mail gateway exited normally");
    ok ($id, "Created ticket");

    my $tick = latest_ticket();
    isa_ok ($tick, 'RT::Model::Ticket');
    ok ($tick->id, "found ticket ".$tick->id);
    is ($tick->id, $id, "correct ticket id");
    is ($tick->Subject , 'binary attachment test', "Created the ticket - ".$tick->id);

    my $file = `cat $LOGO_FILE`;
    ok ($file, "Read in the logo image");
    diag "for the raw file the md5 hex is ". Digest::MD5::md5_hex($file) if $ENV{'TEST_VERBOSE'};

    # Verify that the binary attachment is valid in the database
    my $attachments = RT::Model::AttachmentCollection->new($RT::SystemUser);
    $attachments->limit(column => 'ContentType', value => 'image/gif');
    my $txn_alias = $attachments->join(
        alias1 => 'main',
        column1 => 'TransactionId',
        table2 => 'Transactions',
        column2 => 'id',
    );
    $attachments->limit( alias => $txn_alias, column => 'ObjectType', value => 'RT::Model::Ticket' );
    $attachments->limit( alias => $txn_alias, column => 'ObjectId', value => $id );
    is ($attachments->count, 1, 'Found only one gif attached to the ticket');
    my $attachment = $attachments->first;
    ok ($attachment->id, 'loaded attachment object');
    my $acontent = $attachment->Content;

    diag "coming from the database, md5 hex is ".Digest::MD5::md5_hex($acontent) if $ENV{'TEST_VERBOSE'};
    is ($acontent, $file, 'The attachment isn\'t screwed up in the database.');

    # Grab the binary attachment via the web ui
    my $ua = new LWP::UserAgent;
    my $full_url = "$url/Ticket/Attachment/". $attachment->TransactionId
        ."/". $attachment->id. "/bplogo.gif?&user=root&pass=password";
    my $r = $ua->get( $full_url );

    # Verify that the downloaded attachment is the same as what we uploaded.
    is ($file, $r->content, 'The attachment isn\'t screwed up in download');
}

diag "Simple I18N testing" if $ENV{'TEST_VERBOSE'};
{
    my $text = <<EOF;
From: root\@localhost
To: rtemail\@@{[RT->Config->Get('rtname')]}
Subject: This is a test of I18N ticket creation
Content-Type: text/plain; charset="utf-8"

2 accented lines
\303\242\303\252\303\256\303\264\303\273
\303\241\303\251\303\255\303\263\303\272
bye
EOF
    my ($status, $id) = RT::Test->send_via_mailgate($text);
    is ($status >> 8, 0, "The mail gateway exited normally");
    ok ($id, "Created ticket");

    my $tick = latest_ticket();
    isa_ok ($tick, 'RT::Model::Ticket');
    ok ($tick->id, "found ticket ". $tick->id);
    is ($tick->id, $id, "correct ticket");
    is ($tick->Subject , 'This is a test of I18N ticket creation', "Created the ticket - ". $tick->Subject);

    my $unistring = "\303\241\303\251\303\255\303\263\303\272";
    Encode::_utf8_on($unistring);
    is (
        $tick->Transactions->first->Content,
        $tick->Transactions->first->Attachments->first->Content,
        "Content is ". $tick->Transactions->first->Attachments->first->Content
    );
    ok (
        $tick->Transactions->first->Content =~ /$unistring/i,
        $tick->id." appears to be unicode ". $tick->Transactions->first->Attachments->first->id
    );
}

diag "supposedly I18N fails on the second message sent in." if $ENV{'TEST_VERBOSE'};
{
    my $text = <<EOF;
From: root\@localhost
To: rtemail\@@{[RT->Config->Get('rtname')]}
Subject: This is a test of I18N ticket creation
Content-Type: text/plain; charset="utf-8"

2 accented lines
\303\242\303\252\303\256\303\264\303\273
\303\241\303\251\303\255\303\263\303\272
bye
EOF
    my ($status, $id) = RT::Test->send_via_mailgate($text);
    is ($status >> 8, 0, "The mail gateway exited normally");
    ok ($id, "Created ticket");

    my $tick = latest_ticket();
    isa_ok ($tick, 'RT::Model::Ticket');
    ok ($tick->id, "found ticket ". $tick->id);
    is ($tick->id, $id, "correct ticket");
    is ($tick->Subject , 'This is a test of I18N ticket creation', "Created the ticket");

    my $unistring = "\303\241\303\251\303\255\303\263\303\272";
    Encode::_utf8_on($unistring);

    ok (
        $tick->Transactions->first->Content =~ $unistring,
        "It appears to be unicode - ". $tick->Transactions->first->Content
    );
}


my ($val,$msg) = $everyone_group->PrincipalObj->RevokeRight(Right => 'CreateTicket');
ok ($val, $msg);

SKIP: {
skip "Advanced mailgate actions require an unsafe configuration", 47
    unless RT->Config->Get('UnsafeEmailCommands');

# create new queue to be shure we don't mess with rights
use RT::Model::Queue;
my $queue = RT::Model::Queue->new($RT::SystemUser);
my ($qid) = $queue->create( Name => 'ext-mailgate');
ok( $qid, 'queue Created for ext-mailgate tests' );

# {{{ Check take and resolve actions

# create ticket that is owned by nobody
use RT::Model::Ticket;
my $tick = RT::Model::Ticket->new($RT::SystemUser);
my ($id) = $tick->create( Queue => 'ext-mailgate', Subject => 'test');
ok( $id, 'new ticket Created' );
is( $tick->Owner, $RT::Nobody->id, 'owner of the new ticket is nobody' );

$! = 0;
ok(open(MAIL, "|$RT::BinPath/rt-mailgate --url $url --queue ext-mailgate --action take"), "Opened the mailgate - $!");
print MAIL <<EOF;
From: root\@localhost
Subject: [@{[RT->Config->Get('rtname')]} \#$id] test

EOF
close (MAIL);
is ($? >> 8, 0, "The mail gateway exited normally");

$tick = RT::Model::Ticket->new($RT::SystemUser);
$tick->load( $id );
is( $tick->id, $id, 'load correct ticket');
is( $tick->OwnerObj->EmailAddress, 'root@localhost', 'successfuly take ticket via email');

# check that there is no text transactions writen
is( $tick->Transactions->count, 2, 'no superfluous transactions');

my $status;
($status, $msg) = $tick->set_Owner( $RT::Nobody->id, 'Force' );
ok( $status, 'successfuly changed owner: '. ($msg||'') );
is( $tick->Owner, $RT::Nobody->id, 'set owner back to nobody');


$! = 0;
ok(open(MAIL, "|$RT::BinPath/rt-mailgate --url $url --queue ext-mailgate --action take-correspond"), "Opened the mailgate - $@");
print MAIL <<EOF;
From: root\@localhost
Subject: [@{[RT->Config->Get('rtname')]} \#$id] correspondence

test
EOF
close (MAIL);
is ($? >> 8, 0, "The mail gateway exited normally");

Jifty::DBI::Record::Cachable->flush_cache;

$tick = RT::Model::Ticket->new($RT::SystemUser);
$tick->load( $id );
is( $tick->id, $id, "load correct ticket #$id");
is( $tick->OwnerObj->EmailAddress, 'root@localhost', 'successfuly take ticket via email');
my $txns = $tick->Transactions;
$txns->limit( column => 'Type', value => 'Correspond');
$txns->order_by( column => 'id', order => 'DESC' );
# +1 because of auto open
is( $tick->Transactions->count, 6, 'no superfluous transactions');
is( $txns->first->Subject, "[$RT::rtname \#$id] correspondence", 'successfuly add correspond within take via email' );

$! = 0;
ok(open(MAIL, "|$RT::BinPath/rt-mailgate --url $url --queue ext-mailgate --action resolve --debug"), "Opened the mailgate - $!");
print MAIL <<EOF;
From: root\@localhost
Subject: [@{[RT->Config->Get('rtname')]} \#$id] test

EOF
close (MAIL);
is ($? >> 8, 0, "The mail gateway exited normally");

Jifty::DBI::Record::Cachable->flush_cache;

$tick = RT::Model::Ticket->new($RT::SystemUser);
$tick->load( $id );
is( $tick->id, $id, 'load correct ticket');
is( $tick->Status, 'resolved', 'successfuly resolved ticket via email');
is( $tick->Transactions->count, 7, 'no superfluous transactions');

use RT::Model::User;
my $user = RT::Model::User->new( $RT::SystemUser );
my ($uid) = $user->create( Name => 'ext-mailgate',
			   EmailAddress => 'ext-mailgate@localhost',
			   Privileged => 1,
			   Password => 'qwe123',
			 );
ok( $uid, 'user Created for ext-mailgate tests' );
ok( !$user->has_right( Right => 'OwnTicket', Object => $queue ), "User can't own ticket" );

$tick = RT::Model::Ticket->new($RT::SystemUser);
($id) = $tick->create( Queue => $qid, Subject => 'test' );
ok( $id, 'create new ticket' );

my $rtname = RT->Config->Get('rtname');

$! = 0;
ok(open(MAIL, "|$RT::BinPath/rt-mailgate --url $url --queue ext-mailgate --action take"), "Opened the mailgate - $!");
print MAIL <<EOF;
From: ext-mailgate\@localhost
Subject: [$rtname \#$id] test

EOF
close (MAIL);
is ( $? >> 8, 0, "mailgate exited normally" );
Jifty::DBI::Record::Cachable->flush_cache;

cmp_ok( $tick->Owner, '!=', $user->id, "we didn't change owner" );

($status, $msg) = $user->PrincipalObj->GrantRight( Object => $queue, Right => 'ReplyToTicket' );
ok( $status, "successfuly granted right: $msg" );
my $ace_id = $status;
ok( $user->has_right( Right => 'ReplyToTicket', Object => $tick ), "User can reply to ticket" );

$! = 0;
ok(open(MAIL, "|$RT::BinPath/rt-mailgate --url $url --queue ext-mailgate --action correspond-take"), "Opened the mailgate - $!");
print MAIL <<EOF;
From: ext-mailgate\@localhost
Subject: [$rtname \#$id] test

correspond-take
EOF
close (MAIL);
is ( $? >> 8, 0, "mailgate exited normally" );
Jifty::DBI::Record::Cachable->flush_cache;

cmp_ok( $tick->Owner, '!=', $user->id, "we didn't change owner" );
is( $tick->Transactions->count, 3, "one transactions added" );

$! = 0;
ok(open(MAIL, "|$RT::BinPath/rt-mailgate --url $url --queue ext-mailgate --action take-correspond"), "Opened the mailgate - $!");
print MAIL <<EOF;
From: ext-mailgate\@localhost
Subject: [$rtname \#$id] test

correspond-take
EOF
close (MAIL);
is ( $? >> 8, 0, "mailgate exited normally" );
Jifty::DBI::Record::Cachable->flush_cache;

cmp_ok( $tick->Owner, '!=', $user->id, "we didn't change owner" );
is( $tick->Transactions->count, 3, "no transactions added, user can't take ticket first" );

# revoke ReplyToTicket right
use RT::Model::ACE;
my $ace = RT::Model::ACE->new($RT::SystemUser);
$ace->load( $ace_id );
$ace->delete;
my $acl = RT::Model::ACECollection->new($RT::SystemUser);
$acl->limit( column => 'RightName', value => 'ReplyToTicket' );
$acl->LimitToObject( $RT::System );
while( my $ace = $acl->next ) {
	$ace->delete;
}

ok( !$user->has_right( Right => 'ReplyToTicket', Object => $tick ), "User can't reply to ticket any more" );


my $group = RT::Model::Group->new( $RT::SystemUser );
ok( $group->loadQueueRoleGroup( Queue => $qid, Type=> 'Owner' ), "load queue owners role group" );
$ace = RT::Model::ACE->new( $RT::SystemUser );
($ace_id, $msg) = $group->PrincipalObj->GrantRight( Right => 'ReplyToTicket', Object => $queue );
ok( $ace_id, "Granted queue owners role group with ReplyToTicket right" );

($status, $msg) = $user->PrincipalObj->GrantRight( Object => $queue, Right => 'OwnTicket' );
ok( $status, "successfuly granted right: $msg" );
($status, $msg) = $user->PrincipalObj->GrantRight( Object => $queue, Right => 'TakeTicket' );
ok( $status, "successfuly granted right: $msg" );

$! = 0;
ok(open(MAIL, "|$RT::BinPath/rt-mailgate --url $url --queue ext-mailgate --action take-correspond"), "Opened the mailgate - $!");
print MAIL <<EOF;
From: ext-mailgate\@localhost
Subject: [$rtname \#$id] test

take-correspond with reply right granted to owner role
EOF
close (MAIL);
is ( $? >> 8, 0, "mailgate exited normally" );
Jifty::DBI::Record::Cachable->flush_cache;

$tick->load( $id );
is( $tick->Owner, $user->id, "we changed owner" );
ok( $user->has_right( Right => 'ReplyToTicket', Object => $tick ), "owner can reply to ticket" );
is( $tick->Transactions->count, 5, "transactions added" );
my $txns = $tick->Transactions;
while (my $t = $txns->next) {
    diag( $t->id, $t->Description."\n");
}

# }}}
};


1;

