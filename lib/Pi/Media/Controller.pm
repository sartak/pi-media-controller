package Pi::Media::Controller;
use 5.14.0;
use Mouse;
use AnyEvent::Run;
use Pi::Media::Queue;
use Pi::Media::Video;
use Pi::Media::Library;

has current_video => (
    is      => 'ro',
    isa     => 'Pi::Media::Video',
    writer  => '_set_current_video',
    clearer => '_clear_current_video',
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

has _handle => (
    is      => 'rw',
    clearer => '_clear_handle',
);

sub play_next_in_queue {
    my $self = shift;

    my $video = $self->queue->shift
        or return;

    $self->_play_video($video);
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
sub toggle_pause            { shift->_run_command('p') }
sub decrease_volume         { shift->_run_command('-') }
sub increase_volume         { shift->_run_command('+') }

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
        die "Video file " . $video->path . " not found";
    }

    warn "Playing $video ...\n";

    $self->_set_current_video($video);

    my $handle = AnyEvent::Run->new(
        cmd => ['omxplayer', '-b', $video->path],
    );
    $self->_handle($handle);

    # set things up to just wait until omxplayer exits
    $handle->on_read(sub {});
    $handle->on_eof(undef);
    $handle->on_error(sub {
        warn "Done playing $video\n";
        $self->_clear_current_video;
        $self->_clear_handle;
        undef $handle;

        $self->play_next_in_queue;
    });
}

1;

