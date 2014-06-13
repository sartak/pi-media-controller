#!/usr/bin/env perl
use 5.14.0;
use warnings;
use Plack::Request;
use Plack::Response;
use AnyEvent::Run;
use JSON;

use Twiggy::Server;
my $server = Twiggy::Server->new(
    host => "10.0.1.13",
    port => "5000",
);

my $Player;
my $CurrentFile;
my @Queue;

sub try_play_next {
    return unless @Queue;

    my $file = shift @Queue;
    warn "Playing $file ...\n";

    $CurrentFile = $file;
    $Player = AnyEvent::Run->new(
        cmd => ['omxplayer', '-b', $file],
    );

    # set things up to just wait until omxplayer exits
    $Player->on_read(sub {});
    $Player->on_eof(undef);
    $Player->on_error(sub {
        warn "Done playing $file\n";
        undef $CurrentFile;
        undef $Player;
        try_play_next();
    });
}

sub run_command {
    return unless $Player;
    $Player->push_write(shift);
}

sub current {
    my $req = shift;

    if ($req->method eq 'GET') {
        my $res;

        if ($CurrentFile) {
            $res = $req->new_response(200);
            $res->body($CurrentFile);
        }
        else {
            $res = $req->new_response(204);
        }

        return $res;
    }
    elsif ($req->method eq 'DELETE') {
        run_command('q');
        return $req->new_response(200);
    }
    else {
        my $res = $req->new_response(405);
        $res->body("valid methods: GET, DELETE");
        return $res;
    }
}

sub queue {
    my $req = shift;

    if ($req->method eq 'GET') {
        if (@Queue) {
            my $res = $req->new_response(200);
            $res->body(join "\n", @Queue);
            return $res;
        }
        else {
            return $req->new_response(204);
        }
    }
    elsif ($req->method eq 'POST') {
        my $file = $req->param('file') or do {
            my $res = $req->new_response(400);
            $res->body("file required");
            return $res;
        };

        unless (-e $file && -r _ && !-d _) {
            my $res = $req->new_response(404);
            $res->body("file not found");
            return $res;
        }

        warn "Queued $file ...\n";
        push @Queue, $file;

        if (!$Player) {
            try_play_next();
        }

        return Plack::Response->new->redirect('/queue');
    }
    elsif ($req->method eq 'DELETE') {
        @Queue = ();
        return Plack::Response->new->redirect('/queue');
    }
    else {
        my $res = $req->new_response(405);
        $res->body("valid methods: GET, POST, DELETE");
        return $res;
    }
}

$server->register_service(sub {
    my $req = Plack::Request->new(shift);
    my $res;

    if ($req->path_info eq '/current') {
        $res = current($req);
    }
    elsif ($req->path_info eq '/queue') {
        $res = queue($req);
    }
    else {
        $res = $req->new_response(404);
        $res->body("endpoint not found");
    }

    return $res->finalize;
});

AE::cv->recv;
