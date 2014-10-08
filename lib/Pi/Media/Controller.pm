package Pi::Media::Controller;
use 5.14.0;
use Mouse;
use AnyEvent::Run;
use Pi::Media::Queue;
use Pi::Media::Video;
use Pi::Media::Library;
use JSON::Types;

has notify_cb => (
    is      => 'ro',
    default => sub { sub {} },
);

has current_video => (
    is      => 'ro',
    isa     => 'Pi::Media::Video',
    writer  => '_set_current_video',
    clearer => '_clear_current_video',
);

has is_paused => (
    is     => 'ro',
    isa    => 'Bool',
    writer => '_set_is_paused',
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

sub play_next_in_queue {
    my $self = shift;

    my $video = $self->queue->shift
        or return;

    $self->_play_video($video);
}

sub stop_playing {
    my $self = shift;

    $self->_temporarily_stopped(1);
    $self->stop_current;
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
sub stop_current            { shift->_run_command('q') }
sub decrease_volume         { shift->_run_command('-') }
sub increase_volume         { shift->_run_command('+') }

sub toggle_pause {
    my $self = shift;
    $self->_set_is_paused(!$self->is_paused);
    $self->_run_command('p');
    $self->notify({
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

sub _play_video {
    my $self = shift;
    my $video = shift;

    if (!-r $video->path) {
        $self->notify({
            error => "Video file " . $video->path . " not found",
            video => $video,
        });
        return;
    }

    warn "Playing $video ...\n";

    $self->_set_is_paused(0);
    $self->_set_current_video($video);
    $self->_start_time(time);

    $self->notify({
        started => $video,
    });

    my $handle = AnyEvent::Run->new(
        cmd => ['omxplayer', '-b', $video->path],
    );
    $self->_handle($handle);

    # set things up to just wait until omxplayer exits
    $handle->on_read(sub {
        my ($handle) = @_;
        my $buf = $handle->{rbuf};
        $handle->{rbuf} = '';

        $self->_buffer($self->_buffer . $buf);
    });

    $handle->on_eof(undef);
    $handle->on_error(sub {
        my $seconds;
        if (my ($h, $m, $s) = $self->_buffer =~ /Stopped at: (\d+):(\d\d):(\d\d)/) {
            $seconds = $s
                     + 60 * $m
                     + 3600 * $h;

            # close enough
            if ($video->durationSeconds && $seconds > $video->durationSeconds * .9) {
                $seconds = undef;
            }
        }


        $self->library->add_viewing(
            video           => $self->current_video,
            start_time      => $self->_start_time,
            end_time        => time,
            elapsed_seconds => $seconds,
        );

        warn "Done playing $video\n";
        $self->_clear_current_video;
        $self->_clear_handle;
        $self->_buffer('');
        $self->_clear_start_time;
        undef $handle;

        if ($self->_temporarily_stopped) {
            $self->_temporarily_stopped(0);
        }
        else {
            $self->play_next_in_queue;
        }
    });
}

1;

