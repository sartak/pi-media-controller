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
use File::Slurp 'slurp';
use URI::Escape;

use Pi::Media::Queue::Autofilling;
use Pi::Media::Controller;
use Pi::Media::Library;
use Pi::Media::Television;

my $json = JSON->new->convert_blessed(1);

die "Need config.json" unless -r "config.json";
my $config = $json->decode(scalar slurp "config.json");

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
    config    => $config,
    queue     => $Queue,
    library   => $Library,
    notify_cb => $notify_cb,
);
my $Television = Pi::Media::Television->new;

my %endpoints = (
    '/current' => {
        GET => sub {
            my $req = shift;
            if (!$Controller->current_media) {
                return $req->new_response(204);
            }

            my $res = $req->new_response(200);
            $res->body(encode_utf8($json->encode($Controller->current_media)));
            return $res;
        },
        DELETE => sub {
            my $req = shift;
            if (!$Controller->current_media) {
                $Television->set_active_source;

                if (!$Controller->current_media) {
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

                if (!$Controller->current_media) {
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
                if (!$Controller->current_media) {
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
            if (!$Queue->has_media) {
                return $req->new_response(204);
            }

            my $res = $req->new_response(200);
            $res->content_type("application/json");

            my @media;
            for my $original ($Queue->media) {
                my $copy = \%$original;
                $copy->{removePath} = "/queue?queue_id=" . $original->{queue_id};
                push @media, $copy;
            }

            $res->body(encode_utf8($json->encode(\@media)));
            return $res;
        },
        POST => sub {
            my $req = shift;
            my $id = $req->param('media') or do {
                my $res = $req->new_response(400);
                $res->body("media required");
                return $res;
            };

            my $media = $Library->media_with_id($id) or do {
                my $res = $req->new_response(404);
                $res->body("media not found");
                return $res;
            };

            warn "Queued $media ...\n";

            $Television->set_active_source;
            $Queue->push($media);

            my $res = $req->new_response;

            if ($Controller->current_media) {
                warn "have current media: " . $Controller->current_media;
                $res->redirect('/queue');
            }
            else {
                warn "playing next because no current media";
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
                $Queue->remove_media_with_queue_id($queue_id);
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

            my $treeId = $req->param('tree') || 0;
            my $tag    = decode_utf8($req->param('tag'));
            my $query  = $req->param('query');
            my @response;

            if ($treeId || !$tag) {
                my @trees = $Library->trees(parentId => $treeId, query => $query);
                for my $tree (@trees) {
                    $tree->{requestPath} = "/library?tree=" . $tree->{id};
                    push @response, $tree;
                }
            }

            # only at the very top level
            if (!$treeId && !$tag) {
                my @tags = $Library->tags(query => $query);
                for my $tag (@tags) {
                    $tag->{requestPath} = "/library?tag=" . uri_escape_utf8($tag->{id});
                    push @response, $tag;
                }
            }

            if ($tag) {
                push @response, $Library->media(tag => $tag);
            }
            elsif ($query) {
                push @response, $Library->media(query => $query);
            }
            else {
                push @response, $Library->media(treeId => $treeId);
            }

            $res->body(encode_utf8($json->encode(\@response)));
            return $res;
        },
    },

    '/pi' => {
        SHUTDOWN => sub {
            my $req = shift;
            my $res = $req->new_response(204);

            $Library->disconnect;

            system("sudo", "umount", $ENV{PMC_DATABASE});

            system("sudo reboot");

            exit(0);
        },
    },
);

$server->register_service(sub {
    my $req = Plack::Request->new(shift);

    my $auth_ok = 0;
    my $user;
    if ($user = $req->header('X-PMC-Username')) {
        if (my $pass = $req->header('X-PMC-Password')) {
            if ($config->{users}{$user} eq $pass) {
                $auth_ok = 1;
            }
        }
    }

    if (!$auth_ok) {
        warn "Unauthorized request" . ($user ? " from user '$user'" : "") . "\n";
        my $res = $req->new_response(401);
        $res->body("unauthorized");
        return $res->finalize;
    }

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

if ($ENV{PMC_AUTOPLAY} && $Queue->has_media) {
    $Television->set_active_source;
    $Controller->play_next_in_queue;
}

AE::cv->recv;
