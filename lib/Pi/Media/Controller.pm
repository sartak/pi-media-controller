package Pi::Media::Controller;
use 5.14.0;
use Mouse;
use AnyEvent::Run;
use Pi::Media::Queue;

has current_file => (
    is      => 'ro',
    isa     => 'Str',
    writer  => '_set_current_file',
    clearer => '_clear_current_file',
);

has queue => (
    is       => 'ro',
    isa      => 'Pi::Media::Queue',
    required => 1,
);

has _handle => (
    is      => 'rw',
    clearer => '_clear_handle',
);

sub play_next_in_queue {
    my $self = shift;

    my $file = $self->queue->shift;

    $self->_play_file($file);
}

sub run_command {
    my $self = shift;
    my $command = shift;

    return unless $self->_handle;
    $self->_handle->push_write($command);
}

sub _play_file {
    my $self = shift;
    my $file = shift;

    warn "Playing $file ...\n";

    $self->_set_current_file($file);

    my $handle = AnyEvent::Run->new(
        cmd => ['omxplayer', '-b', $file],
    );
    $self->_handle($handle);

    # set things up to just wait until omxplayer exits
    $handle->on_read(sub {});
    $handle->on_eof(undef);
    $handle->on_error(sub {
        warn "Done playing $file\n";
        $self->_clear_current_file;
        $self->_clear_handle;
        undef $handle;

        $self->play_next_in_queue;
    });
}

1;

