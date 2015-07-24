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
use AnyEvent::HTTP;

use Pi::Media::Queue::Autofilling;
use Pi::Media::Controller;
use Pi::Media::Library;
use Pi::Media::GamepadManager;
use Pi::Media::AC;

select((select(STDERR), $|=1)[0]);

my $json = JSON->new->convert_blessed(1);

die "Need config.json" unless -r "config.json";
my $config = $json->decode(scalar slurp "config.json");

$config->{location} = $ENV{PMC_LOCATION} if $ENV{PMC_LOCATION};

if ($config->{by_location}) {
    %$config = (
        %$config,
        %{ $config->{by_location}{$config->{location}} || {} },
    );
}

my $server = Twiggy::Server->new(
    port => ($ENV{PMC_PORT}||5000),
);

my @Watchers;
my @extra_cb;

my $notify_cb = sub {
    my $event = shift;

    # internal watchers
    for my $cb (@extra_cb) {
        $cb->($event);
    }

    # external watchers

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

my $TelevisionClass = $config->{television}{class} || 'Pi::Media::Television::HDMI';
Mouse::load_class($TelevisionClass);
my $Television = $TelevisionClass->new(
    config => $config,
);

my $ac_state = -e "ac.json" ? $json->decode(scalar slurp "ac.json") : {};
my $AC = Pi::Media::AC->new(%$ac_state);

if (!$config->{disable_gamepads}) {
    my $GamepadManager = Pi::Media::GamepadManager->new(
        config => $config,
        controller => $Controller,
    );
    $GamepadManager->scan;
    push @extra_cb, sub { $GamepadManager->got_event(@_) };
}

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
                $Controller->play_next_in_queue;

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
            $Controller->toggle_or_next_subtitles;
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
                $Queue->remove_media_with_queue_id($queue_id);
            }

            my $res = $req->new_response;
            $res->redirect('/queue');
            return $res;
        },
    },
    '/queue/source' => {
        PUT => sub {
            my $req = shift;

            if ($req->param('tree')) {
                my ($tree) = $Library->trees(id => $req->param('tree'));
                if ($tree) {
                    $Queue->source($tree);
                    warn "Set queue source to tree $tree";
                    if (!$Controller->current_media) {
                        $Controller->play_next_in_queue;
                    }
		    $Television->set_active_source;
                }
                else {
                    warn "Unknown queue source tree " . $req->param('tree');
                }
            }
            else {
                warn "Cleared queue source";
                $Queue->clear_autofill_source;
            }

            return $req->new_response(204);
        },
    },

    '/library' => {
        GET => sub {
            my $req = shift;
            my $res = $req->new_response(200);
            $res->content_type("application/json");

            my $treeId = $req->param('tree') || 0;
            my $query  = $req->param('query');
            my $where;
            my @response;

            if ($treeId) {
                my ($tree) = $Library->trees(id => $treeId);
                if ($tree->query) {
                    $where = $tree->query;
                }
            }

            if ($where) {
                push @response, $Library->media(where => $where);
            }
            else {
                my @trees = $Library->trees(parentId => $treeId, query => $query);
                for my $tree (@trees) {
                    $tree->{requestPath} = "/library?tree=" . $tree->{id};
                    push @response, $tree;
                }

                if ($query) {
                    push @response, $Library->media(query => $query);
                }
                else {
                    push @response, $Library->media(treeId => $treeId);
                }
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

    '/ac/power' => {
        GET => sub {
            my $req = shift;

            my $res = $req->new_response(200);
            $res->body($AC->is_on ? "on" : "off");
            return $res;
        },
        PUT => sub {
            my $req = shift;
            my $on  = $req->param('on');

            if (($on && !$AC->is_on) || (!$on && $AC->is_on)) {
                $AC->toggle_power;
            }

            my $res = $req->new_response;
            $res->redirect('/ac/power');
            return $res;
        },
        TOGGLE => sub {
            my $req = shift;

            $AC->toggle_power;

            my $res = $req->new_response;
            $res->redirect('/ac/power');
            return $res;
        },
        ON => sub {
            my $req = shift;

            $AC->power_on;

            my $res = $req->new_response;
            $res->redirect('/ac/power');
            return $res;
        },
        OFF => sub {
            my $req = shift;

            $AC->power_off;

            my $res = $req->new_response;
            $res->redirect('/ac/power');
            return $res;
        },
    },

    '/ac/temperature' => {
        GET => sub {
            my $req = shift;

            my $res = $req->new_response(200);
            $res->body($AC->temperature);
            return $res;
        },
        PUT => sub {
            my $req = shift;

            $AC->set_temperature($req->param('temperature'));

            my $res = $req->new_response;
            $res->redirect('/ac/temperature');
            return $res;
        },
        MINIMUM => sub {
            my $req = shift;

            $AC->set_temperature($AC->minimum_temperature);

            my $res = $req->new_response;
            $res->redirect('/ac/temperature');
            return $res;
        },
        MAXIMUM => sub {
            my $req = shift;

            $AC->set_temperature($AC->maximum_temperature);

            my $res = $req->new_response;
            $res->redirect('/ac/temperature');
            return $res;
        },
        UP => sub {
            my $req = shift;

            $AC->temperature_up;

            my $res = $req->new_response;
            $res->redirect('/ac/temperature');
            return $res;
        },
        DOWN => sub {
            my $req = shift;

            $AC->temperature_down;

            my $res = $req->new_response;
            $res->redirect('/ac/temperature');
            return $res;
        },
    },

    '/ac/mode' => {
        GET => sub {
            my $req = shift;

            my $res = $req->new_response(200);
            $res->body($AC->mode);
            return $res;
        },
        PUT => sub {
            my $req = shift;

            $AC->set_mode($req->param('mode'));

            my $res = $req->new_response;
            $res->redirect('/ac/mode');
            return $res;
        },
        TOGGLE => sub {
            my $req = shift;

            $AC->toggle_mode;

            my $res = $req->new_response;
            $res->redirect('/ac/mode');
            return $res;
        },
    },

    '/ac/fanspeed' => {
        GET => sub {
            my $req = shift;

            my $res = $req->new_response(200);
            $res->body($AC->fanspeed);
            return $res;
        },
        PUT => sub {
            my $req = shift;

            $AC->set_fanspeed($req->param('fanspeed'));

            my $res = $req->new_response;
            $res->redirect('/ac/fanspeed');
            return $res;
        },
        TOGGLE => sub {
            my $req = shift;

            $AC->toggle_fanspeed;

            my $res = $req->new_response;
            $res->redirect('/ac/fanspeed');
            return $res;
        },
    },

    '/hue/scene' => {
        PUT => sub {
            my $req = shift;
            if (my $scene = $req->param('scene')) {
                my $url = "$config->{hue_host}/api/newdeveloper/groups/0/action";
                my $body = encode_utf8($json->encode({ scene => $scene }));

                http_request
                    PUT => $url,
                    body => $body,
                    sub { "ignore" };

                return $req->new_response(204);
            }

            return $req->new_response(400);
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

    warn $req->method . ' ' . $req->path_info;

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
