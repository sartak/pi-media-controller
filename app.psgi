#!/usr/bin/env perl
use 5.14.0;
use warnings;
use utf8::all;
use Plack::Request;
use Plack::App::File;
use JSON;
use JSON::Types;
use Twiggy::Server;
use Encode;
use Scalar::Util 'blessed';
use File::Slurp 'slurp';
use URI::Escape;
use AnyEvent::HTTP;
use Time::HiRes 'time';
use AnyEvent::Filesys::Notify;

use Pi::Media::Queue::Autofilling;
use Pi::Media::Controller;
use Pi::Media::Library;
use Pi::Media::GamepadManager;
use Pi::Media::AC;

our $CURRENT_USER;

select((select(STDERR), $|=1)[0]);

my $json = JSON->new->convert_blessed(1);

my $config = Pi::Media::Config->new;

my $server = Twiggy::Server->new(
    port => ($ENV{PMC_PORT}||5000),
);

my @Watchers;
my @extra_cb;

my $notify_cb = sub {
    my $event = shift;
    my $single = shift;

    # internal watchers
    for my $cb (@extra_cb) {
        next if $single && $cb != $single;
        $cb->($event);
    }

    # external watchers

    my $unicode_json = $json->encode($event);
    my $json = encode_utf8($unicode_json) . "\n";
    warn $json;

    my @ok;

    for my $writer (@Watchers) {
        if (!$single || $writer == $single) {
            eval { $writer->write($json) };
            warn $@ if $@;
            push @ok, $writer if !$@;
        }
        else {
            push @ok, $writer;
        }
    }

    @Watchers = @ok;

    if (my $url = $config->value('notify_url')) {
      $url .= "/$event->{type}" if $event->{type};
      http_request(
        POST => $url,
        headers => {
          'User-Agent' => 'pmc.sartak.org',
          'Content-Type' => 'application/json',
          %{ $config->value('notify_headers') || {} },
        },
        body => $json,
        sub { "ignore" },
      );
    }
};

my $Library = Pi::Media::Library->new(
  file   => $ENV{PMC_DATABASE},
  config => $config,
);
my $Queue = Pi::Media::Queue::Autofilling->new(
    library   => $Library,
    notify_cb => $notify_cb,
);
my $Controller = Pi::Media::Controller->new(
    config    => $config,
    queue     => $Queue,
    library   => $Library,
    notify_cb => $notify_cb,
);
push @extra_cb, sub { $Controller->got_event(@_) };

my $TelevisionClass = $config->value('television')->{class} || 'Pi::Media::Television::HDMI';
my $TelevisionStateFile = $config->value('television')->{file} || 'tv.json';
Mouse::load_class($TelevisionClass);
my $tv_state = -e $TelevisionStateFile ? $json->decode(scalar slurp $TelevisionStateFile) : { is_on => 1 };
my $Television = $TelevisionClass->new(
    config    => $config,
    notify_cb => $notify_cb,
    %{ $config->value('television') },
    %$tv_state,
    is_on => ($tv_state->{is_on} ? 1 : 0), # JSON::XS::Boolean fails type
);

my $ac_state = -e "ac.json" ? $json->decode(scalar slurp "ac.json") : {};
my $AC = Pi::Media::AC->new(
    notify_cb => $notify_cb,
    %$ac_state,
    is_on => ($ac_state->{is_on} ? 1 : 0), # JSON::XS::Boolean fails type
);

if (!$config->value('disable_gamepads')) {
    my $GamepadManager = Pi::Media::GamepadManager->new(
        config => $config,
        controller => $Controller,
        library => $Library,
        queue => $Queue,
        television => $Television,
        start_cb => \&restart_provisional_viewing_timer,
    );
    $GamepadManager->scan;
    push @extra_cb, sub { $GamepadManager->got_event(@_) };
}

my %endpoints;
%endpoints = (
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
                $Television->set_active_source
                    if $Television->can('set_active_source');
                $Controller->play_next_in_queue;

                restart_provisional_viewing_timer();

                return $req->new_response(204);
            }

            $Controller->stop_current;
            return $req->new_response(200);
        },
        PLAYPAUSE => sub {
            my $req = shift;

            $Television->set_active_source
                if $Television->can('set_active_source');

            if (!$Controller->current_media) {
                $Controller->play_next_in_queue;
                restart_provisional_viewing_timer();
            }

            if ($Controller->current_media) {
                $Controller->toggle_pause;
            }

            return $req->new_response(200);
        },
        STOP => sub {
            my $req = shift;
            $Controller->stop_playing;
            $Television->power_off if $Television->can('power_off');
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
            $Television->set_active_source
                if $Television->can('set_active_source');
            if ($Controller->unpause) {
                if (!$Controller->current_media) {
                    $Controller->play_next_in_queue;
                    restart_provisional_viewing_timer();
                }

                return $req->new_response(200);
            }
            else {
                return $req->new_response(204);
            }
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
    '/current/paused' => {
        PUT => sub {
            my $req = shift;
            if ($req->param('paused')) {
                if ($Controller->pause) {
                    return $req->new_response(200);
                }
                else {
                    return $req->new_response(204);
                }
            }
            else {
                $Television->set_active_source
                    if $Television->can('set_active_source');
                if ($Controller->unpause) {
                    if (!$Controller->current_media) {
                        $Controller->play_next_in_queue;
                        restart_provisional_viewing_timer();
                    }

                    return $req->new_response(200);
                }
                else {
                    return $req->new_response(204);
                }
            }

            return $req->new_response(200);
        },
        DELETE => sub {
            my $req = shift;
            $Controller->stop_playing;
            $Television->power_off if $Television->can('power_off');
            return $req->new_response(200);
        },
    },
    '/current/audio' => {
        GET => sub {
            my $req = shift;

            my $res = $req->new_response(200);
            my $body = $Controller->audio_track;
            $res->body($body);

            return $res;
        },
        PUT => sub {
            my $req = shift;

            $Controller->set_audio_track($req->param('track'));

            return $endpoints{'/current/audio'}{GET}->($req);
        },
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

            $media->{initial_seconds} = $req->param('initialSeconds') || 0;
            $media->{audio_track} = $req->param('audioTrack') || 0;
            $media->{save_state} = $req->param('saveState') || 0;

            warn "Queued $media ...\n";

            $Television->set_active_source
                if $Television->can('set_active_source');
            $Queue->push($media);

            my $res = $req->new_response;

            if ($Controller->current_media) {
                $res->redirect('/queue');
            }
            else {
                $Controller->play_next_in_queue;
                restart_provisional_viewing_timer();
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

            return $req->new_response(204);
        },
    },
    '/queue/source' => {
        PUT => sub {
            my $req = shift;

            if ($req->param('tree')) {
                my ($tree) = $Library->trees(id => $req->param('tree'));
                if ($tree) {
                    $Queue->source($tree);
                    $Queue->requestor($main::CURRENT_USER);
                    warn "Set queue source to tree $tree";
                    $Television->set_active_source
                        if $Television->can('set_active_source');
                    if (!$Controller->current_media) {
                        $Controller->play_next_in_queue;
                        restart_provisional_viewing_timer();
                    }
                }
                else {
                    warn "Unknown queue source tree " . $req->param('tree');
                }
            }
            else {
                warn "Cleared queue source";
                $Queue->clear_autofill_source;
                $Queue->clear_requestor;
            }

            return $req->new_response(204);
        },
    },

    '/library' => {
        GET => sub {
            my $req = shift;
            my $res = $req->new_response(200);
            $res->content_type("application/json");

            my $treeId  = $req->param('tree') || 0;
            my $query   = $req->param('query');

            my %args;
            my @response;

            warn "Starting library queries at " . (time - $req->{_pmc_begin}) . "s" if $ENV{PMC_PROFILE};

            if ($treeId) {
                my ($tree) = $Library->trees(id => $treeId);
                if ($tree->has_clause) {
                    %args = (
                        all         => 1,
                        joins       => $tree->join_clause,
                        where       => $tree->where_clause,
                        group       => $tree->group_clause,
                        order       => $tree->order_clause,
                        limit       => $tree->limit_clause,
                        source_tree => $tree->id,
                    );
                }
                warn "Found tree at " . (time - $req->{_pmc_begin}) . "s" if $ENV{PMC_PROFILE};
            }

            if (($req->param('id')||'') =~ /,/) {
                $args{id} = [grep { length } split ',', $req->param('id')];
                $args{all} = 1;
            }

            if (%args) {
                push @response, $Library->media(%args);
                warn "Got media (with \%args) at " . (time - $req->{_pmc_begin}) . "s" if $ENV{PMC_PROFILE};
            }
            else {
                push @response, $Library->trees(parentId => $treeId, query => $query);
                warn "Got tree (without \%args) at " . (time - $req->{_pmc_begin}) . "s" if $ENV{PMC_PROFILE};

                if ($query) {
                    push @response, $Library->media(query => $query);
                    warn "Got media (with query) at " . (time - $req->{_pmc_begin}) . "s" if $ENV{PMC_PROFILE};
                }
                else {
                    push @response, $Library->media(treeId => $treeId);
                    warn "Got media (without query) at " . (time - $req->{_pmc_begin}) . "s" if $ENV{PMC_PROFILE};
                }
            }

            my %tags_for_tree;
            for my $thing (@response) {
                my @actions;

                if ($thing->isa('Pi::Media::File::Video')) {
                    my $id = $thing->id;
                    my ($seconds, $audio_track) = $Library->resume_state_for_video($thing);

                    push @actions, {
                        url    => "/queue?media=" . $id,
                        type   => 'enqueue',
                        label  => $seconds ? 'TV Play from Beginning' : 'Play on TV',
                    };

                    if ($seconds) {
                        # context is important!
                        $seconds -= 120;

                        $thing->{resume}{seconds} = $seconds;

                        push @actions, {
                            url            => "/queue?media=" . $id . '&initialSeconds=' . $seconds . '&audioTrack=' . $audio_track,
                            type           => 'enqueue',
                            label          => "Resume Play on TV",
                            initialSeconds => $seconds,
                            audioTrack     => $audio_track,
                        };
                    }

                    unless ($config->value('disable_downloads')) {
                        push @actions, {
                            url    => "/download?media=" . $id,
                            type   => 'download',
                            label  => 'Download',
                        };
                    }

                    my $treeId = $thing->treeId;
                    $tags_for_tree{$treeId} ||= [$Library->media_tags_for_tree($treeId)];
                    my @tags = @{ $thing->tags };
                    for my $tag ('bookmark', @{ $tags_for_tree{$thing->treeId} }) {
                        if (grep { $_ eq $tag } @tags) {
                            push @actions, {
                                url    => "/library/tags?mediaId=" . $id . "&removeTag=" . uri_escape($tag),
                                type   => 'tag',
                                label  => $tag eq 'bookmark' ? "Unbookmark" : "Remove Tag \"$tag\"",
                            };
                        }
                        else {
                            push @actions, {
                                url    => "/library/tags?mediaId=" . $id . "&addTag=" . uri_escape($tag),
                                type   => 'tag',
                                label  => $tag eq 'bookmark' ? 'Bookmark' : "Add Tag \"$tag\"",
                            };
                        }
                    }
                }
                elsif ($thing->isa('Pi::Media::Tree')) {
                    push @actions, {
                        url => "/library?tree=" . $thing->{id},
                        type => 'navigate',
                        label => 'Display', # shouldn't be shown
                    };
                }
                elsif ($thing->isa('Pi::Media::File::Game')) {
                    push @actions, {
                        url    => "/queue?media=" . $thing->{id} . '&saveState=new',
                        type   => 'enqueue',
                        label  => 'New Game',
                    };

                    my $base = $thing->path;
                    $base =~ s/\.\w+$//;
                    my @save_states = sort glob(qq{"$base.state.*"});
                    if (@save_states) {
                        push @actions, {
                            url    => "/queue?media=" . $thing->{id},
                            type   => 'enqueue',
                            label  => 'Resume Latest State',
                        };

                        for my $path (@save_states) {
                          my ($state) = $path =~ /\.(\d+)$/
                              or next;

                          push @actions, {
                              url    => "/queue?media=" . $thing->{id} . "&saveState=$state",
                              type   => 'enqueue',
                              label  => 'Resume ' . scalar(localtime($state)),
                          };
                        }
                    }
                }
                elsif ($thing->isa('Pi::Media::File::Stream')) {
                    my $id = $thing->id;

                    push @actions, {
                        url    => "/queue?media=" . $id,
                        type   => 'enqueue',
                        label  => 'Stream on TV',
                    };

                    my $treeId = $thing->treeId;
                    $tags_for_tree{$treeId} ||= [$Library->media_tags_for_tree($treeId)];
                    my @tags = @{ $thing->tags };
                    for my $tag ('bookmark', @{ $tags_for_tree{$thing->treeId} }) {
                        if (grep { $_ eq $tag } @tags) {
                            push @actions, {
                                url    => "/library/tags?mediaId=" . $id . "&removeTag=" . uri_escape($tag),
                                type   => 'tag',
                                label  => $tag eq 'bookmark' ? "Unbookmark" : "Remove Tag \"$tag\"",
                            };
                        }
                        else {
                            push @actions, {
                                url    => "/library/tags?mediaId=" . $id . "&addTag=" . uri_escape($tag),
                                type   => 'tag',
                                label  => $tag eq 'bookmark' ? 'Bookmark' : "Add Tag \"$tag\"",
                            };
                        }
                    }
                }

                $thing->{actions} = \@actions;
            }

            warn "Finished inflating response at " . (time - $req->{_pmc_begin}) . "s" if $ENV{PMC_PROFILE};
            $res->body(encode_utf8($json->encode(\@response)));
            warn "Finished serializing response at " . (time - $req->{_pmc_begin}) . "s" if $ENV{PMC_PROFILE};
            return $res;
        },
    },
    '/library/viewed' => {
        PUT => sub {
            my $req = shift;
            my $mediaId = $req->param('mediaId');
            my $startTime = $req->param('startTime');
            my $endTime = $req->param('endTime');
            my $completed = $req->param('completed') || 0;
            my $initialSeconds = $req->param('initialSeconds');
            my $endSeconds = $req->param('endSeconds');
            my $audioTrack = $req->param('audioTrack');
            my $location = $req->param('location');
            my $who = $main::CURRENT_USER->name;

            my $media = $Library->media_with_id($mediaId) or do {
                my $res = $req->new_response(404);
                $res->body("media not found");
                return $res;
            };

            # close enough
            if ($media->duration_seconds && $endSeconds > $media->duration_seconds * .9) {
                $completed = 1;
            }

            for my $skip ($media->skips) {
                if (!defined($skip->[1]) && $endSeconds > $skip->[0] - 2) {
                    $completed = 1;
                }
            }

            $Library->add_viewing(
                media           => $media,
                start_time      => int($startTime),
                end_time        => int($endTime),
                initial_seconds => int($initialSeconds),
                elapsed_seconds => int($endSeconds - $initialSeconds),
                completed       => $completed,
                audio_track     => $audioTrack,
                location        => $location,
                who             => $who,
            );

            my $res = $req->new_response(204);
            $res->header('X-PMC-Completed' => $completed);
            return $res;
        },
    },

    '/library/tags' => {
        POST => sub {
            my $req = shift;
            my $mediaId = $req->param('mediaId');
            my $addTag = $req->param('addTag');
            my $removeTag = $req->param('removeTag');

            my $media = $Library->media_with_id($mediaId) or do {
                my $res = $req->new_response(404);
                $res->body("media not found");
                return $res;
            };

            my @oldTags = @{ $media->tags };
            my @newTags = @oldTags;

            if ($addTag) {
                push @newTags, $addTag unless grep { $_ eq $addTag } @newTags;
            }
            if ($removeTag) {
                @newTags = grep { $_ ne $removeTag } @newTags;
            }

            if ("@oldTags" ne "@newTags") {
                my $tags = @newTags ? ('`' . (join '`', @newTags) . '`') : '';
                $Library->update_media($media, tags => $tags);
            }

            my $res = $req->new_response(204);
            return $res;
        },
    },

    '/download' => {
        GET => sub {
            my $req = shift;

            if ($config->value('disable_download')) {
                my $res = $req->new_response(400);
                $res->body("download disabled");
                return $res;
            }

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

            my $user = $main::CURRENT_USER;
            my $username = $user->name;
            my $password = $user->password;
            my $path = uri_escape(encode_utf8($Library->_relativify_path($media->path)));
            my $app = $req->header('X-App-Name');
            $app = $app ? "/$app" : "";

            my $url = "$app/static/download/$path?user=$username&pass=$password&id=" . $media->id;

            my $res = $req->new_response;
            $res->redirect($url);
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

    '/television' => {
        GET => sub {
            my $req = shift;
            my $res = $req->new_response(200);
            $res->content_type("application/json");

            my $state = $Television->state;

            $res->body(encode_utf8($json->encode($state)));

            return $res;
        },
    },

    '/television/volume' => {
        GET => sub {
            my $req = shift;

            my $res = $req->new_response(200);
            my $body = $Television->volume;
            if ($Television->muted) {
                $body .= " [mute]";
            }
            $res->body($body);

            return $res;
        },
        PUT => sub {
            my $req = shift;

            $Television->set_volume($req->param('volume'));

            return $endpoints{'/television/volume'}{GET}->($req);
        },
        MINIMUM => sub {
            my $req = shift;

            $Television->set_volume($Television->minimum_volume);

            return $endpoints{'/television/volume'}{GET}->($req);
        },
        MAXIMUM => sub {
            my $req = shift;

            $Television->set_volume($Television->maximum_volume);

            return $endpoints{'/television/volume'}{GET}->($req);
        },
        UP => sub {
            my $req = shift;

            $Television->volume_up;

            return $endpoints{'/television/volume'}{GET}->($req);
        },
        DOWN => sub {
            my $req = shift;

            $Television->volume_down;

            return $endpoints{'/television/volume'}{GET}->($req);
        },
        MUTE => sub {
            my $req = shift;

            $Television->mute;

            return $endpoints{'/television/volume'}{GET}->($req);
        },
        UNMUTE => sub {
            my $req = shift;

            $Television->unmute;

            return $endpoints{'/television/volume'}{GET}->($req);
        },
    },

    '/television/input' => {
        GET => sub {
            my $req = shift;

            my $res = $req->new_response(200);
            $res->body($Television->input);
            return $res;
        },
        PUT => sub {
            my $req = shift;

            $Television->set_input($req->param('input'));

            return $endpoints{'/television/input'}{GET}->($req);
        },
    },

    '/television/power' => {
        GET => sub {
            my $req = shift;

            my $res = $req->new_response(200);
            $res->body($Television->is_on ? "on" : "off");
            return $res;
        },
        PUT => sub {
            my $req = shift;
            my $on  = $req->param('on');
            my $is_on = $Television->is_on;

            if ($on && !$is_on) {
                $Television->power_on;
            }
            elsif (!$on && $is_on) {
                $Television->power_off;
            }

            return $endpoints{'/television/power'}{GET}->($req);
        },
        ON => sub {
            my $req = shift;

            $Television->power_on;

            return $endpoints{'/television/power'}{GET}->($req);
        },
        OFF => sub {
            my $req = shift;

            $Television->power_off;

            return $endpoints{'/television/power'}{GET}->($req);
        },
    },

    '/ac' => {
        GET => sub {
            my $req = shift;
            my $res = $req->new_response(200);
            $res->content_type("application/json");

            $res->body(encode_utf8($json->encode($AC->state)));

            return $res;
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

            return $endpoints{'/ac/power'}{GET}->($req);
        },
        TOGGLE => sub {
            my $req = shift;

            $AC->toggle_power;

            return $endpoints{'/ac/power'}{GET}->($req);
        },
        ON => sub {
            my $req = shift;

            $AC->power_on;

            return $endpoints{'/ac/power'}{GET}->($req);
        },
        OFF => sub {
            my $req = shift;

            $AC->power_off;

            return $endpoints{'/ac/power'}{GET}->($req);
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

            return $endpoints{'/ac/temperature'}{GET}->($req);
        },
        MINIMUM => sub {
            my $req = shift;

            $AC->set_temperature($AC->minimum_temperature);

            return $endpoints{'/ac/temperature'}{GET}->($req);
        },
        MAXIMUM => sub {
            my $req = shift;

            $AC->set_temperature($AC->maximum_temperature);

            return $endpoints{'/ac/temperature'}{GET}->($req);
        },
        UP => sub {
            my $req = shift;

            $AC->temperature_up;

            return $endpoints{'/ac/temperature'}{GET}->($req);
        },
        DOWN => sub {
            my $req = shift;

            $AC->temperature_down;

            return $endpoints{'/ac/temperature'}{GET}->($req);
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

            return $endpoints{'/ac/mode'}{GET}->($req);
        },
        TOGGLE => sub {
            my $req = shift;

            $AC->toggle_mode;

            return $endpoints{'/ac/mode'}{GET}->($req);
        },
    },

    '/ac/fanspeed' => {
        GET => sub {
            my $req = shift;

            return $endpoints{'/ac/fanspeed'}{GET}->($req);
        },
        PUT => sub {
            my $req = shift;

            $AC->set_fanspeed($req->param('fanspeed'));

            return $endpoints{'/ac/fanspeed'}{GET}->($req);
        },
        TOGGLE => sub {
            my $req = shift;

            $AC->toggle_fanspeed;

            return $endpoints{'/ac/fanspeed'}{GET}->($req);
        },
    },

    '/hue/scene' => {
        PUT => sub {
            my $req = shift;
            if (my $scene = $req->param('scene')) {
                my $url = $config->value('hue_host').'/api/newdeveloper/groups/0/action';
                my $body = encode_utf8($json->encode({ scene => $scene }));

                http_request
                    PUT => $url,
                    body => $body,
                    sub { "ignore" };

                return $req->new_response(204);
            }

            my $res = $req->new_response(400);
            $res->body("scene required");
            return $res;
        },
    },
    '/api/auth' => {
        GET => sub {
            my $req = shift;
            my $res = $req->new_response(200);
            $res->content_type('text/plain');
            $res->body($main::CURRENT_USER->name);
            return $res;
        },
    },
);

my $authenticate = sub {
    my $req = Plack::Request->new(shift);

    my $user;
    my $username;

    if ($username = ($req->header('X-PMC-Username') || $req->header('X-Username') || $req->param('user'))) {
	if ($req->address eq '127.0.0.1') {
          $user = $Library->login_without_password($username);
	} elsif (my $pass = ($req->header('X-PMC-Password') || $req->header('X-Password') || $req->param('pass'))) {
            $user = $Library->login($username, $pass);
        }
    }

    return $user if !wantarray;
    return ($username, $user);
};

my $app = sub {
    my $env = shift;
    my $req = Plack::Request->new($env);
    $req->{_pmc_begin} = time;

    my ($username, $user) = $authenticate->($env);
    if (!$user) {
        warn "Unauthorized request" . ($username ? " by user '$username'" : "") . " from " . $req->address . " for " . $req->method . ' ' . $req->path_info . "\n";
        my $res = $req->new_response(401);
        $res->header('X-PMC-Time' => scalar gmtime);
        $res->header('Cache-control' => 'private, max-age=0, no-store');
        $res->body("unauthorized");
        return $res->finalize;
    }

    local $main::CURRENT_USER = $user;

    warn $req->method . ' ' . $req->request_uri;

    my $spec = $endpoints{$req->path_info};
    if (!$spec) {
        my $res = $req->new_response(404);
        $res->body("endpoint not found");
        $res->header('X-PMC-Time' => scalar gmtime);
        $res->header('Cache-control' => 'private, max-age=0, no-store');
        return $res->finalize;
    }

    my $action = $spec->{uc $req->method};
    if (!$action) {
        my $res = $req->new_response(405);
        $res->body("allowed methods: " . (join ', ', sort keys %$spec));
        $res->header('X-PMC-Time' => scalar gmtime);
        $res->header('Cache-control' => 'private, max-age=0, no-store');
        return $res->finalize;
    }

    my $res = $action->($req);

    warn "Request took " . (time - $req->{_pmc_begin}) . "s" if $ENV{PMC_PROFILE};

    if (blessed($res)) {
        $res->header('X-PMC-Time' => scalar gmtime);
        $res->header('Cache-control' => 'private, max-age=0, no-store');
        return $res->finalize;
    }
    return $res;
};

use Plack::Builder;
$app = builder {
    enable "Plack::Middleware::CrossOrigin",
        origins        => '*',
        methods        => '*',
        headers        => '*',
        expose_headers => '*';

    enable sub {
        my $app = shift;
        sub {
            my $env = shift;
            my $req = Plack::Request->new($env);
            my $res = $app->($env);
            if ($env->{PATH_INFO} =~ m{^/static/download/.*?([^/]+\.(\w+))$}) {
                my ($path, $extension) = ($1, $2);
                my $id = $req->param('id');
                my $file = $id ? "$id.$extension" : $path;
                push @{ $res->[1] }, 'Content-Disposition' => "attachment; filename=$file";
            }
            return $res;
        };
    };

    enable "Plack::Middleware::Static::Range",
        path => sub {
            my ($path, $env) = @_;
            return 0 unless $authenticate->($env);
            s!^/+static/download/!!;
        },
        root => $Library->library_root;

    mount '/status' => sub {
        my $env = shift;
        my $req = Plack::Request->new($env);

        my ($username, $user) = $authenticate->($env);
        if (!$user) {
            warn "Unauthorized request" . ($username ? " by user '$username'" : "") . " from " . $req->address . " for " . $req->method . ' ' . $req->path_info . "\n";
            my $res = $req->new_response(401);
            $res->header('X-PMC-Time' => scalar gmtime);
            $res->header('Cache-control' => 'private, max-age=0, no-store');
            $res->body("unauthorized");
            return $res->finalize;
        }

	my $device = $req->header('X-PMC-Device') || $req->param('device');
        if (!$device) {
            my $res = $req->new_response(400);
            $res->header('X-PMC-Time' => scalar gmtime);
            $res->header('Cache-control' => 'private, max-age=0, no-store');
            $res->body("no device sent");
            warn "no device sent in call to /status from $username\n";
            return $res->finalize;
        }

        if ($req->method eq 'GET') {
            $env->{'plack.skip-deflater'} = 1;

            return sub {
                my $responder = shift;
                my $writer = $responder->([200, ['Content-Type' => 'application/json', 'X-PMC-Time' => scalar(gmtime), 'Cache-control' => 'private, max-age=0, no-store']]);
                push @Watchers, $writer;

                my $current_location = `./get-location.pl $device`;
                chomp $current_location;

                $notify_cb->({ type => 'connected' }, $writer);
                $notify_cb->($Television->power_status, $writer);
                $notify_cb->({ type => 'location/current', location => $current_location }, $writer);

                if ($Television->can('volume_status')) {
                    $notify_cb->($Television->volume_status, $writer);
                }
                else {
                    $notify_cb->({ type => "television/volume", hide => bool(1) }, $writer);
                }

                if ($Television->can('input_status')) {
                    $notify_cb->($Television->input_status, $writer);
                }
                else {
                    $notify_cb->({ type => "television/input", hide => bool(1) }, $writer);
                }

                $notify_cb->($Controller->playpause_status, $writer);
                $notify_cb->($Controller->fastforward_status, $writer);

                $notify_cb->($Controller->audio_status, $writer);

                $notify_cb->({ type => 'subscriber', device => $device, username => $username });
            };
        }
        else {
            my $res = $req->new_response(405);
            $res->body("allowed methods: GET");
            $res->header('X-PMC-Time' => scalar gmtime);
            $res->header('Cache-control' => 'private, max-age=0, no-store');
            return $res->finalize;
        }
    };

    enable "Deflater",
        content_type => ['text/css','text/html','text/javascript','application/javascript','application/json'];

    mount "/" => $app;
};


$server->register_service($app);

my ($dir) = $ENV{PMC_DATABASE} =~ m{^(.*)/[^/]+$}
  or die "Unable to parse $ENV{PMC_DATABASE}";

my $notifier = AnyEvent::Filesys::Notify->new(
  dirs => [$dir],
  filter => sub {
    my $f = shift;
    return $f eq $ENV{PMC_DATABASE};
  },
  cb => sub {
    $notify_cb->({ type => 'database/modified' });
  },
  parse_events => 1,
  skip_subdirs => 1,
);

warn "Ready!\n";
$notify_cb->({ type => 'launched' });

my $provisional_viewing_timer;
sub send_provisional_viewing {
  undef $provisional_viewing_timer;

  my $url = $config->value('provisional_viewing_url') or return;

  my $media = $Controller->current_media;
  return if !$media;

  my $start = $Controller->start_time;
  my $elapsed = time - $start;

  warn "Provisional viewing of " . $media->description . " (${elapsed}s) UPSERT $url…\n";

  my $payload = encode_utf8($json->encode({
      startTime => $start,
      elapsedSeconds => $elapsed,
      payload => $json->encode({
        media => {
          %{ $media->TO_JSON },
          path => $Library->_relativify_path($media->path),
        },
        audio_track => $Controller->audio_track,
        location    => $config->location,
        who         => $media->{requestor}->name,
      }),
  }));

  http_request(
    UPSERT => $url,
    headers => {
      'User-Agent' => 'pmc.sartak.org',
      'Content-Type' => 'application/json',
      %{ $config->value('provisional_viewing_headers') || {} },
    },
    body => $payload,
    sub { "ignore" },
  );

  restart_provisional_viewing_timer(60);
}

sub restart_provisional_viewing_timer {
  my $after = shift;

  if (!$after) {
    return send_provisional_viewing();
  }

  $provisional_viewing_timer = AnyEvent->timer(
    after    => $after,
    cb       => \&send_provisional_viewing,
  );
};

if ($ENV{PMC_AUTOPLAY} && $Queue->has_media) {
    $Television->set_active_source
        if $Television->can('set_active_source');
    $Controller->play_next_in_queue;
    restart_provisional_viewing_timer(1);
}

AE::cv->recv;
