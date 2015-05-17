package Pi::Media::Controller;
use 5.14.0;
use Mouse;
use AnyEvent::Run;
use Pi::Media::Queue;
use Pi::Media::File;
use Pi::Media::Library;
use JSON::Types;

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

# video specific

has is_paused => (
    is     => 'ro',
    isa    => 'Bool',
    writer => '_set_is_paused',
);

has has_toggled_subtitles => (
    is     => 'ro',
    isa    => 'Bool',
    writer => '_set_has_toggled_subtitles',
);

# game specific

has _game_home_button_pressed => (
    is      => 'rw',
    isa     => 'Bool',
    default => 1,
);

sub play_next_in_queue {
    my $self = shift;

    my $media = $self->queue->shift
        or return;

    $self->_play_media($media);
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

sub _run_command {
    my $self = shift;
    my $command = shift;

    return unless $self->_handle;
    $self->_handle->push_write($command);
}

sub _play_media {
    my $self = shift;
    my $media = shift;

    if (!-r $media->path) {
        $self->notify({
            type  => 404,
            error => "Media file " . $media->path . " not found",
            media => $media,
        });
        return;
    }

    warn "Playing $media ...\n";

    $self->_set_is_paused(0);
    $self->_set_current_media($media);
    $self->_start_time(time);
    $self->_game_home_button_pressed(1);

    $self->notify({
        type  => 'started',
        media => $media,
    });

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

    if ($media->isa('Pi::Media::File::Video')) {
        my @args = ('-b', @{ $self->config->{omxplayer_args} || [] });
        return AnyEvent::Run->new(
            cmd => ['omxplayer', @args, $media->path],
        );
    }
    elsif ($media->isa('Pi::Media::File::Game')) {
        my @emulator_cmd = @{ $self->config->{emulator_for}{$media->extension} || [] };
        if (@emulator_cmd == 0) {
            die "No emulator for type " . $media->extension;
        }

        my $cfg_path = $media->path;
        $cfg_path =~ s/.\w+$/.cfg/;
        if (-e $cfg_path) {
            push @emulator_cmd, "--appendconfig", $cfg_path;
        }

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

    my $seconds;
    if ($media->isa('Pi::Media::File::Video')) {
        if (my ($h, $m, $s) = $self->_buffer =~ /Stopped at: (\d+):(\d\d):(\d\d)/) {
            $seconds = $s
                        + 60 * $m
                        + 3600 * $h;

            # close enough
            if ($media->duration_seconds && $seconds > $media->duration_seconds * .9) {
                $seconds = undef;
            }
        }

    }
    else {
        $seconds = $end_time - $self->_start_time;

        if ($self->_game_home_button_pressed) {
            $self->_temporarily_stopped(1);
        }
    }

    $self->library->add_viewing(
        media           => $self->current_media,
        start_time      => $self->_start_time,
        end_time        => $end_time,
        elapsed_seconds => $seconds,
        location        => $self->config->{location},
    );

    warn "Done playing $media\n";
    $self->_clear_current_media;
    $self->_clear_handle;
    $self->_buffer('');
    $self->_clear_start_time;
    $self->_set_has_toggled_subtitles(0);

    $self->notify({
        type  => 'finished',
        media => $media,
    });

    if ($self->_temporarily_stopped) {
        $self->_temporarily_stopped(0);
    }
    else {
        $self->play_next_in_queue;
    }
}

# video specific

sub toggle_pause {
    my $self = shift;
    $self->_set_is_paused(!$self->is_paused);
    $self->_run_command('p');
    $self->notify({
        type   => 'paused',
        paused => bool($self->is_paused),
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

sub decrease_speed          { shift->_run_command('1') }
sub increase_speed          { shift->_run_command('2') }
sub rewind                  { shift->_run_command('<') }
sub fast_forward            { shift->_run_command('>') }
sub show_info               { shift->_run_command('z') }
sub previous_audio          { shift->_run_command('j') }
sub next_audio              { shift->_run_command('k') }
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
1;

