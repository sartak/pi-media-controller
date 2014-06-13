package Pi::Media::Television;
use 5.14.0;
use Mouse;
use AnyEvent::Run;

has _handle => (
    is      => 'rw',
    clearer => '_clear_handle',
);

sub set_active_source {
    my $self = shift;

    warn "Setting self as active source for TV ... \n";

    my $handle = AnyEvent::Run->new(
        cmd => [ 'echo "on" | cec-client -s; echo "as" | cec-client -s' ],
    );
    $self->_handle($handle);

    # set things up to just wait until omxplayer exits
    $handle->on_read(sub {});
    $handle->on_eof(undef);
    $handle->on_error(sub {
        warn "Done setting active source\n";
        $self->_clear_handle;
        undef $handle;
    });
}

1;

