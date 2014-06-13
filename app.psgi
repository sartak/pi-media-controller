#!/usr/bin/env perl
use 5.14.0;
use warnings;
use Plack::Request;
use JSON;
use Twiggy::Server;

use Pi::Media::Queue;
use Pi::Media::Controller;

my $server = Twiggy::Server->new(
    host => "10.0.1.13",
    port => "5000",
);

my $Queue = Pi::Media::Queue->new;
my $Controller = Pi::Media::Controller->new(queue => $Queue);

my %endpoints = (
    '/current' => {
        GET => sub {
            my $req = shift;
            if (!$Controller->current_file) {
                return $req->new_response(204);
            }

            my $res = $req->new_response(200);
            $res->body($Controller->current_file);
            return $res;
        },
        DELETE => sub {
            my $req = shift;
            run_command('q');
            return $req->new_response(200);
        },
    },

    '/queue' => {
        GET => sub {
            my $req = shift;
            if (!$Queue->count) {
                return $req->new_response(204);
            }

            my $res = $req->new_response(200);
            $res->body(join "\n", $Queue->elements);
            return $res;
        },
        POST => sub {
            my $req = shift;
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
            $Queue->push($file);

            if (!$Controller->current_file) {
                $Controller->play_next_in_queue;
            }

            my $res = $req->new_response;
            $res->redirect('/queue');
            return $res;
        },
        DELETE => sub {
            my $req = shift;
            $Queue->clear;
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
        $res->body("allowed methods: " . (join ', ', sort keys %$spec));
        return $res->finalize;
    }

    my $res = $action->($req);
    return $res->finalize;
});

AE::cv->recv;
