#!/usr/bin/env perl
use 5.14.0;
use warnings;
use utf8::all;
use Plack::Request;
use Plack::App::File;
use JSON;
use Twiggy::Server;
use Encode;
use Scalar::Util 'blessed';

use Pi::Media::Queue::Autofilling;
use Pi::Media::Controller;
use Pi::Media::Library;
use Pi::Media::Television;

my $json = JSON->new->convert_blessed(1);

my $server = Twiggy::Server->new(
    host => $ENV{PMC_HOST},
    port => ($ENV{PMC_PORT}||5000),
);

my @Watchers;

my $notify_cb = sub {
    my $event = shift;
    my $json = encode_utf8($json->encode($event));

    for my $writer (@Watchers) {
	eval {
            $writer->write($json);
            $writer->write("\n");
	};
    }
};

my $Library = Pi::Media::Library->new(file => $ENV{PMC_DATABASE});
my $Queue = Pi::Media::Queue::Autofilling->new(library => $Library);
my $Controller = Pi::Media::Controller->new(
    queue     => $Queue,
    library   => $Library,
    notify_cb => $notify_cb,
);
my $Television = Pi::Media::Television->new;
my %endpoints = (
    '/medium' => {
        GET => sub {
            my $req = shift;
            my $res = $req->new_response(200);
            $res->body(encode_utf8($json->encode([$Library->mediums])));
            return $res;
        },
    },

    '/series' => {
        GET => sub {
            my $req = shift;
            my $res = $req->new_response(200);
            my %args;

            if (my $mediumId = $req->param('mediumId')) {
                $args{mediumId} = $mediumId;
            }

            $res->body(encode_utf8($json->encode([$Library->series(%args)])));
            return $res;
        },
    },

    '/current' => {
        GET => sub {
            my $req = shift;
            if (!$Controller->current_video) {
                return $req->new_response(204);
            }

            my $res = $req->new_response(200);
            $res->body(encode_utf8($json->encode($Controller->current_video)));
            return $res;
        },
        DELETE => sub {
            my $req = shift;
            if (!$Controller->current_video) {
                $Television->set_active_source;

                if (!$Controller->current_video) {
                    $Controller->play_next_in_queue;
                }

                return $req->new_response(204);
            }

            $Controller->stop_current;
            return $req->new_response(200);
        },
        PLAYPAUSE => sub {
            my $req = shift;
            if ($Controller->toggle_pause) {
                # unpaused
                $Television->set_active_source;

                if (!$Controller->current_video) {
                    $Controller->play_next_in_queue;
                }
            }

            return $req->new_response(200);
        },
        STOP => sub {
            my $req = shift;
            $Controller->stop_playing;
            $Television->power_off;
            return $req->new_response(200);
        },
        PAUSE => sub {
            my $req = shift;
            if ($Controller->pause) {
                return $req->new_response(200);
            }
            else {
                return $req->new_response(204);
            }
        },
        UNPAUSE => sub {
            my $req = shift;
            $Television->set_active_source;
            if ($Controller->unpause) {
                if (!$Controller->current_video) {
                    $Controller->play_next_in_queue;
                }

                return $req->new_response(200);
            }
            else {
                return $req->new_response(204);
            }
        },
        NEXTAUDIO => sub {
            my $req = shift;
            $Controller->next_audio;
            return $req->new_response(200);
        },
        NEXTSUBS => sub {
            my $req = shift;
            $Controller->next_subtitles;
            return $req->new_response(200);
        },
        # decrease_speed increase_speed rewind fast_forward show_info
        # previous_audio previous_chapter next_chapter
        # previous_subtitles toggle_subtitles
        # decrease_subtitle_delay increase_subtitle_delay decrease_volume
        # increase_volume
    },

    '/queue' => {
        GET => sub {
            my $req = shift;
            if (!$Queue->has_videos) {
                return $req->new_response(204);
            }

            my $res = $req->new_response(200);
            $res->content_type("application/json");

            my @videos;
            for my $original ($Queue->videos) {
                my $copy = \%$original;
                $copy->{removePath} = "/queue?queue_id=" . $original->{queue_id};
                push @videos, $copy;
            }

            $res->body(encode_utf8($json->encode(\@videos)));
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

            $Television->set_active_source;
            $Queue->push($video);

            my $res = $req->new_response;

            if ($Controller->current_video) {
                $res->redirect('/queue');
            }
            else {
                $Controller->play_next_in_queue;
                $res->redirect('/current');
            }

            return $res;
        },
        DELETE => sub {
            my $req = shift;
            $Queue->clear;
            my $res = $req->new_response;
            $res->redirect('/queue');
            return $res;
        },
        REMOVE => sub {
            my $req = shift;
            if (my $queue_id = $req->param('queue_id')) {
                $Queue->remove_video_with_queue_id($queue_id);
            }

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

            my %args;
            my @response;

            sub {
                $args{mediumId} = $req->param('mediumId') or do {
                    @response = $Library->mediums;
                    for my $medium (@response) {
                        $medium->{requestPath} = "/library?mediumId=" . $medium->{id};
                    }
                    return;
                };

                $args{seriesId} = $req->param('seriesId') or do {
                    @response = $Library->series(%args);
                    for my $series (@response) {
                        $series->{requestPath} = "/library?mediumId=" . $args{mediumId} . "&seriesId=" . $series->{id};
                    }

                    push @response, $Library->videos(
                        %args,
                        seriesId => undef,
                    );

                    return;
                };

                $args{seasonId} = $req->param('seasonId') or do {
                    @response = $Library->seasons(%args);
                    for my $season (@response) {
                        $season->{requestPath} = "/library?mediumId=" . $args{mediumId} . "&seriesId=" . $args{seriesId} . "&seasonId=" . $season->{id};
                    }

                    push @response, $Library->videos(
                        %args,
                        seasonId => undef,
                    );

                    return;
                };

                @response = $Library->videos(%args);
            }->();

            $res->body(encode_utf8($json->encode(\@response)));
            return $res;
        },
    },

    '/pi' => {
        SHUTDOWN => sub {
            my $req = shift;
            my $res = $req->new_response(204);

            system("sudo reboot");

            return $res;
        },
    },

    '/stream' => {
        GET => sub {
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

            my $path = $video->path;

            return Plack::App::File->new->serve_path($req->env, $path);
        },
    },
);

$server->register_service(sub {
    my $req = Plack::Request->new(shift);

    if ($req->path_info eq '/status') {
        if ($req->method eq 'GET') {
            return sub {
                my $responder = shift;
                my $writer = $responder->([200, ['Content-Type', 'application/json']]);
                push @Watchers, $writer;
            };
        }
        else {
            my $res = $req->new_response(405);
            $res->body("allowed methods: GET");
            return $res->finalize;
        }
    }

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
    if (blessed($res)) {
        return $res->finalize;
    }
    return $res;
});

warn "Ready!\n";

if ($Queue->has_videos) {
    $Television->set_active_source;
    $Controller->play_next_in_queue;
}

AE::cv->recv;
