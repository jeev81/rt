#!/usr/bin/perl
use strict;
use warnings;

use RT::Test::GnuPG tests => 13, gnupg_options => { passphrase => 'rt-test' };

RT::Test->import_gnupg_key('rt-recipient@example.com');
RT::Test->import_gnupg_key('rt-test@example.com', 'public');

my ($baseurl, $m) = RT::Test->started_ok;

ok( $m->login, 'we did log in' );

# configure key for General queue
{
    $m->get( $baseurl.'/Admin/Queues/');
    $m->follow_link_ok( {text => 'General'} );
    $m->submit_form(
        form_number => 3,
        fields      => { CorrespondAddress => 'rt-recipient@example.com' },
    );
    $m->content_like(qr/rt-recipient\@example.com.* - never/, 'has key info.');
}

ok(my $user = RT::User->new(RT->SystemUser));
ok($user->Load('root'), "Loaded user 'root'");
$user->SetEmailAddress('recipient@example.com');

{
    my $id = send_via_mailgate('quoted_inline_signature.txt');

    my $tick = RT::Ticket->new( RT->SystemUser );
    $tick->Load( $id );
    ok ($tick->id, "loaded ticket #$id");

    my $txn = $tick->Transactions->First;
    my ($msg, @attachments) = @{$txn->Attachments->ItemsArrayRef};

    is( $msg->GetHeader('X-RT-Privacy'),
        undef,
        "no privacy is set as this ticket is not encrypted"
    );

    my @mail = RT::Test->fetch_caught_mails;
    is(scalar @mail, 1, "autoreply only");
}

sub send_via_mailgate {
    my $fname = shift;
    my $emaildatadir = RT::Test::get_relocatable_dir(File::Spec->updir(),
        qw(data gnupg emails special));
    my $file = File::Spec->catfile( $emaildatadir, $fname );
    my $mail = RT::Test->file_content($file);

    my ($status, $id) = RT::Test->send_via_mailgate($mail);
    is ($status >> 8, 0, "the mail gateway exited normally");
    ok ($id, "got id of a newly created ticket - $id");
    return $id;
}

