package Pi::Media::Controller;
use 5.14.0;
use Mouse;
use AnyEvent::Run;
use Pi::Media::Queue;
use Pi::Media::File;
use Pi::Media::Library;
use File::Slurp 'slurp';

has notify_cb => (
    is      => 'ro',
    default => sub { sub {} },
);

has current_media => (
    is      => 'ro',
    isa     => 'Pi::Media::File',
    writer  => '_set_current_media',
    clearer => '_clear_current_media',
);

has config => (
    is       => 'ro',
    isa      => 'HashRef',
    required => 1,
);

has queue => (
    is       => 'ro',
    isa      => 'Pi::Media::Queue',
    required => 1,
);

has library => (
    is       => 'ro',
    isa      => 'Pi::Media::Library',
    required => 1,
);

has _temporarily_stopped => (
    is      => 'rw',
    isa     => 'Bool',
    default => 0,
);

has _handle => (
    is      => 'rw',
    clearer => '_clear_handle',
);

has _start_time => (
    is      => 'rw',
    isa     => 'Int',
    clearer => '_clear_start_time',
);

has _buffer => (
    is      => 'rw',
    isa     => 'Str',
    default => '',
);

has is_paused => (
    is     => 'ro',
    isa    => 'Bool',
    writer => '_set_is_paused',
);

# video specific

has has_toggled_subtitles => (
    is     => 'ro',
    isa    => 'Bool',
    writer => '_set_has_toggled_subtitles',
);

has audio_track => (
    is      => 'ro',
    isa     => 'Maybe[Int]',
    writer  => '_set_audio_track',
);

has initial_seconds => (
    is      => 'ro',
    isa     => 'Int',
    writer  => '_set_initial_seconds',
    clearer => '_clear_initial_seconds',
);

# game specific

has _game_home_button_pressed => (
    is      => 'rw',
    isa     => 'Bool',
    default => 1,
);

has save_state => (
    is      => 'ro',
    isa     => 'Str',
    writer  => '_set_save_state',
    clearer => '_clear_save_state',
);

sub play_next_in_queue {
    my $self = shift;

    my $media = $self->queue->shift;
    $self->notify({
        type   => 'fastforward',
        status => $media ? 'show' : 'hide',
    });

    if ($media) {
        $self->_play_media($media);
    }
}

sub stop_playing {
    my $self = shift;

    $self->_temporarily_stopped(1);
    $self->stop_current;
}

sub stop_current {
    my $self = shift;

    if (!$self->current_media) {
        return;
    }
    elsif ($self->current_media->isa('Pi::Media::File::Video')) {
        $self->_run_command('q');
    }
    elsif ($self->current_media->isa('Pi::Media::File::Game')) {
        $self->_game_home_button_pressed(0);
        kill 'TERM', $self->_handle->{child_pid};
    }
    else {
        die "Unable to stop_current for " . $self->current_media;
    }
}

sub notify {
    my $self = shift;
    $self->notify_cb->(@_);
}

sub audio_status {
    my $self = shift;
    my $media = $self->current_media;

    if ($media && $media->isa('Pi::Media::File::Video')) {
        my $available = $media->available_audio;
        return {
            type      => 'audio',
            available => $available,
            selected  => $available->[$self->audio_track],
        };
    }
    else {
        return {
            type      => 'audio',
            available => [],
        };
    }
}

sub _notify_audio {
    my $self = shift;
    $self->notify($self->audio_status);
}

sub _run_command {
    my $self = shift;
    my $command = shift;

    return unless $self->_handle;
    $self->_handle->push_write($command);
}

sub _play_media {
    my $self = shift;
    my $media = shift;

    if ($media->type ne 'stream' && !-e $media->path) {
        $self->notify({
            type  => 404,
            error => "Media file " . $media->path . " not found",
            media => $media,
        });
        return;
    }

    warn "Playing $media ...\n";

    $self->_set_is_paused(0);
    $self->_set_audio_track($media->{audio_track} || 0);
    $self->_set_current_media($media);
    $self->_start_time(time);
    $self->_game_home_button_pressed(1);

    if ($media->type eq 'video') {
        $self->_set_initial_seconds($media->{initial_seconds} || 0);
    }
    elsif ($media->type eq 'game') {
        $self->_set_save_state($media->{save_state});
    }

    $self->notify({
        type  => 'started',
        media => $media,
    });

    $self->notify({
        type   => 'playpause',
        status => 'pause',
    });

    $self->notify({
        type   => 'fastforward',
        status => $media ? 'show' : 'hide',
    });

    $self->_notify_audio;

    my $handle = $self->_handle_for_media($media);
    $self->_handle($handle);

    # set things up to just wait until player exits
    $handle->on_read(sub {
        my ($handle) = @_;
        my $buf = $handle->{rbuf};
        $handle->{rbuf} = '';

        $self->_buffer($self->_buffer . $buf);
    });

    $handle->on_eof(undef);
    $handle->on_error(sub {
        undef $handle;
        $self->_finished_media($media);
    });

    warn "Child pid is " . $handle->{child_pid};
}

sub _handle_for_media {
    my $self = shift;
    my $media = shift;

    if ($media->isa('Pi::Media::File::Stream')) {
        open my $handle, '-|', 'youtube-dl', '-g', $media->url;
        my $url = <$handle>;
        close $handle;
        my @args = ('-b', @{ $self->config->{omxplayer_args} || [] });
        return AnyEvent::Run->new(
            cmd => ['omxplayer', @args, $url],
        );
    }
    elsif ($media->isa('Pi::Media::File::Video')) {
        my @args = ('-b');

        if ($self->initial_seconds) {
            my $s = $self->initial_seconds;
            my $m = int($s / 60);
            $s %= 60;
            my $h = int($m / 60);
            $m %= 60;
            my $timestamp = sprintf '%d:%02d:%02d', $h, $m, $s;
            push @args, '--pos', $timestamp;
        }

        if ($self->audio_track) {
            push @args, '--aidx', $self->audio_track + 1;
        }

        push @args, @{ $self->config->{omxplayer_args} || [] };
        return AnyEvent::Run->new(
            cmd => ['omxplayer', @args, $media->path],
        );
    }
    elsif ($media->isa('Pi::Media::File::Game')) {
        my @emulator_cmd = @{ $self->config->{emulator_for}{$media->extension} || [] };
        if (@emulator_cmd == 0) {
            die "No emulator for type " . $media->extension;
        }

        my $base_path = $media->path;
        $base_path =~ s/.\w+$//;

        my $cfg_path = "$base_path.cfg";
        if (-e $cfg_path) {
            push @emulator_cmd, "--appendconfig", $cfg_path;

            my $config = slurp($cfg_path);
            if ($config =~ / ^ \s* \# \s* pmc: \s* save_state \s* = \s* never \b /mx) {
                my $state_path = "$base_path.state.auto";
                unlink $state_path;
            }

            if ($config =~ / ^ \s* libretro_path \s* = /mx) {
                @emulator_cmd = grep { $_ ne '-L' && !/\.so$/ } @emulator_cmd;
            }
        }

        my $state_path = "$base_path.state.auto";
        my $time = time;
        if ($self->save_state eq 'new') {
          system("mv", $state_path => "$base_path.state.$time");
        }
        elsif ($self->save_state) {
          my $state = $self->save_state;
          system("mv", $state_path => "$base_path.state.$time");
          system("mv", "$base_path.state.$state" => $state_path);
        }

        warn join ' ', @emulator_cmd, $media->path;

        return AnyEvent::Run->new(
            cmd => [@emulator_cmd, $media->path],
        );
    }
    else {
        die "Unable to handle media of type " . $media->type . " in _handle_for_media";
    }
}


sub _finished_media {
    my $self = shift;
    my $media = shift;

    my $end_time = time;

    my $end_seconds;
    my $initial_seconds = $self->initial_seconds;
    my $completed = 0;

    if ($media->isa('Pi::Media::File::Video')) {
        if (my ($h, $m, $s) = $self->_buffer =~ /Stopped at: (\d+):(\d\d):(\d\d)/) {
            $end_seconds = $s
                         + 60 * $m
                         + 3600 * $h;

            # close enough
            if ($media->duration_seconds && $end_seconds > $media->duration_seconds * .9) {
                $completed = 1;
            }
        }

    }
    else {
        $end_seconds = $end_time - $self->_start_time;

        if ($self->_game_home_button_pressed) {
            $self->_temporarily_stopped(1);
        }
    }

    $self->library->add_viewing(
        media           => $self->current_media,
        start_time      => $self->_start_time,
        end_time        => $end_time,
        initial_seconds => $initial_seconds,
        audio_track     => $self->audio_track,
        elapsed_seconds => $end_seconds - $initial_seconds,
        completed       => $completed,
        location        => $self->config->{location},
        who             => $self->current_media->{requestor}->name,
    );

    warn "Done playing $media\n";
    $self->_clear_current_media;
    $self->_clear_handle;
    $self->_buffer('');
    $self->_clear_start_time;
    $self->_clear_initial_seconds;
    $self->_clear_save_state;
    $self->_set_has_toggled_subtitles(0);

    $self->notify({
        type  => 'finished',
        media => $media,
    });

    $self->notify({
        type   => 'playpause',
        status => 'play',
    });

    $self->_notify_audio;

    if ($self->_temporarily_stopped) {
        $self->_temporarily_stopped(0);
        $self->notify({
            type   => 'fastforward',
            status => 'hide',
        });
    }
    else {
        $self->play_next_in_queue;
    }
}

sub toggle_pause {
    my $self = shift;

    die if !$self->current_media;

    if ($self->current_media->isa('Pi::Media::File::Video')) {
        $self->_run_command('p');
    }
    elsif ($self->current_media->isa('Pi::Media::File::Game')) {
        if ($self->is_paused) {
            kill 'CONT', $self->_handle->{child_pid};
        }
        else {
            kill 'STOP', $self->_handle->{child_pid};
        }
    }

    $self->_set_is_paused(!$self->is_paused);
    $self->notify({
        type   => 'playpause',
        status => ($self->is_paused ? 'play' : 'pause'),
    });

    return $self->is_paused;
}

sub unpause {
    my $self = shift;
    return 0 unless $self->is_paused;
    $self->toggle_pause;
    return 1;
}

sub pause {
    my $self = shift;
    return 0 if $self->is_paused;
    $self->toggle_pause;
    return 1;
}

# video specific

sub decrease_speed          { shift->_run_command('1') }
sub increase_speed          { shift->_run_command('2') }
sub rewind                  { shift->_run_command('<') }
sub fast_forward            { shift->_run_command('>') }
sub show_info               { shift->_run_command('z') }
sub previous_audio          { shift->_run_command('j'); sleep 1 }
sub next_audio              { shift->_run_command('k'); sleep 1 }
sub previous_chapter        { shift->_run_command('i') }
sub next_chapter            { shift->_run_command('o') }
sub previous_subtitles      { shift->_run_command('n') }
sub next_subtitles          { shift->_run_command('m') }
sub toggle_subtitles        { shift->_run_command('s') }
sub decrease_subtitle_delay { shift->_run_command('d') }
sub increase_subtitle_delay { shift->_run_command('f') }
sub decrease_volume         { shift->_run_command('-') }
sub increase_volume         { shift->_run_command('+') }

sub toggle_or_next_subtitles {
    my $self = shift;
    if ($self->has_toggled_subtitles) {
        return $self->next_subtitles;
    }
    else {
        $self->_set_has_toggled_subtitles(1);
        return $self->toggle_subtitles;
    }
}

sub set_audio_track {
    my $self    = shift;
    my $desired = shift;
    unless ($self->current_media && $self->current_media->isa('Pi::Media::File::Video')) {
        return;
    }

    $desired = 0 if $desired < 0;
    $desired = $#{ $self->current_media->spoken_langs } if $desired > $#{ $self->current_media->spoken_langs };

    my $current = $self->audio_track;

    if ($desired == $current) {
        return;
    }

    while ($desired > $current) {
        $self->next_audio;
        $current++;
    }

    while ($desired < $current) {
        $self->previous_audio;
        $current--;
    }

    $self->_set_audio_track($current);
    $self->_notify_audio;
}

sub got_event {
    my $self  = shift;
    my $event = shift;

    if ($event->{type} eq 'television/input') {
        if (($event->{input}||'') ne 'Pi') {
            $self->pause if $self->current_media && !$self->is_paused;
        }
    }
}

sub playpause_status {
    my $self = shift;

    if ($self->current_media && !$self->is_paused) {
        return {
            type   => 'playpause',
            status => 'pause',
        };
    }
    else {
        return {
            type   => 'playpause',
            status => 'play',
        };
    }
}

sub fastforward_status {
    my $self = shift;

    return {
        type   => 'fastforward',
        status => $self->current_media ? 'show' : 'hide',
    };
}

1;

