#!/usr/bin/env perl
use 5.14.0;
use warnings;
use Plack::Request;
use AnyEvent::Run;

use Twiggy::Server;
my $server = Twiggy::Server->new(
    host => "127.0.0.1",
    port => "5000",
);

my $Player;
my @Queue;

sub try_play_next {
    return unless @Queue;

    my $file = shift @Queue;

    $Player = AnyEvent::Run->new(
        cmd => ['omxplayer', '-b', $file],
    );
    $Player->on_read(sub {});
    $Player->on_eof(undef);
    $Player->on_error(sub {
        try_play_next();
    });
}

$server->register_service(sub {
    my $req = Plack::Request->new(shift);
    my $file = $req->param('file') or do {
        my $res = $req->new_response(400);
        $res->body("file required");
        return $res->finalize;
    };

    unless (-e $file) {
        my $res = $req->new_response(404);
        $res->body("file not found");
        return $res->finalize;
    }

    push @Queue, $file;

    if (!$Player) {
        try_play_next();
    }

    my $res = $req->new_response(200);
    return $res->finalize;
});

AE::cv->recv;
