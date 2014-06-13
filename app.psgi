#!/usr/bin/env perl
use 5.14.0;
use warnings;
use Plack::Request;
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

my %endpoints = (
    '/current' => {
        GET => sub {
            if (!$CurrentFile) {
                return $req->new_response(204);
            }

            my $res = $req->new_response(200);
            $res->body($CurrentFile);
            return $res;
        },
        DELETE => sub {
            run_command('q');
            return $req->new_response(200);
        },
    },

    '/queue' => {
        GET => sub {
            if (!@Queue) {
                return $req->new_response(204);
            }

            my $res = $req->new_response(200);
            $res->body(join "\n", @Queue);
            return $res;
        },
        POST => {
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

            my $res = $req->new_response;
            $res->redirect('/queue');
            return $res;
        },
        DELETE => {
            @Queue = ();
            my $res = $req->new_response;
            $res->redirect('/queue');
            return $res;
        },
    },
);

$server->register_service(sub {
    my $req = Plack::Request->new(shift);

    my $spec = $endpoints{$req->path_info};
    if (!$spec) {
        my $res = $req->new_response(404);
        $res->body("endpoint not found");
        return $res->finalize;
    }

    my $action = $spec->{uc $req->method};
    if (!$action) {
        my $res = $req->new_response(405);
        $res->body("allowed methods: " . (join ', ', sort keys %spec));
        return $res->finalize;
    }

    my $res = $action->($req);
    return $res->finalize;
});

AE::cv->recv;
