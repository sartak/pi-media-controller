#!/usr/bin/env perl
use 5.14.0;
use warnings;
use Plack::Request;
use JSON;
use Twiggy::Server;

use Pi::Media::Queue;
use Pi::Media::Controller;
use Pi::Media::Library;

my $json = JSON->new->convert_blessed(1);

my $server = Twiggy::Server->new(
    host => "10.0.1.13",
    port => "5000",
);

my $Queue = Pi::Media::Queue->new;
my $Controller = Pi::Media::Controller->new(queue => $Queue);
my $Library = Pi::Media::Library->new;

my %endpoints = (
    '/current' => {
        GET => sub {
            my $req = shift;
            if (!$Controller->current_video) {
                return $req->new_response(204);
            }

            my $res = $req->new_response(200);
            $res->body($json->encode($Controller->current_video));
            return $res;
        },
        DELETE => sub {
            my $req = shift;
            $Controller->stop_current;
            return $req->new_response(200);
        },
        PLAYPAUSE => sub {
            my $req = shift;
            $Controller->toggle_pause;
            return $req->new_response(200);
        },
        # decrease_speed increase_speed rewind fast_forward show_info
        # previous_audio next_audio previous_chapter next_chapter
        # previous_subtitles next_subtitles toggle_subtitles
        # decrease_subtitle_delay increase_subtitle_delay decrease_volume
        # increase_volume
    },

    '/queue' => {
        GET => sub {
            my $req = shift;
            if (!$Queue->count) {
                return $req->new_response(204);
            }

            my $res = $req->new_response(200);
            $res->content_type("application/json");
            $res->body($json->encode([$Queue->videos]));
            return $res;
        },
        POST => sub {
            my $req = shift;
            my $id = $req->param('video') or do {
                my $res = $req->new_response(400);
                $res->body("video required");
                return $res;
            };

            my $video = $Library->video_with_id($id) or do {
                my $res = $req->new_response(404);
                $res->body("video not found");
                return $res;
            };

            warn "Queued $video ...\n";

            $Queue->push($video);

            if (!$Controller->current_video) {
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

    '/library' => {
        GET => sub {
            my $req = shift;
            my $res = $req->new_response(200);
            $res->content_type("application/json");
            $res->body($json->encode([$Library->videos]));
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
