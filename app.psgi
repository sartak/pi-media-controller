#!/usr/bin/env perl
use 5.14.0;
use warnings;
use Plack::Request;
use AnyEvent::Run;

use Twiggy::Server;
my $server = Twiggy::Server->new(
    host => "10.0.1.13",
    port => "5000",
);

my $Player;
my @Queue;

sub try_play_next {
    return unless @Queue;

    my $file = shift @Queue;
    warn "Playing $file ...\n";

    $Player = AnyEvent::Run->new(
        cmd => ['omxplayer', '-b', $file],
    );
    $Player->on_read(sub {});
    $Player->on_eof(undef);
    $Player->on_error(sub {
        warn "Done playing $file\n";
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

    unless (-e $file && -r _ && !-d _) {
        my $res = $req->new_response(404);
        $res->body("file not found");
        return $res->finalize;
    }

    warn "Queued $file ...\n";
    push @Queue, $file;

    my $res = $req->new_response(200);
    $res->body(join "\n", @Queue);

    if (!$Player) {
        try_play_next();
    }

    return $res->finalize;
});

AE::cv->recv;
