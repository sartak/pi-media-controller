package Pi::Media::Television::HDMI;
use 5.14.0;
use Mouse;
extends 'Pi::Media::Television';

has _handle => (
    is      => 'rw',
    clearer => '_clear_handle',
    lazy    => 1,
    builder => sub {
        my $self = shift;

        my $handle = AnyEvent::Run->new(cmd => "cec-client");
        $handle->on_read(sub {});
        $handle->on_eof(undef);
        $handle->on_error(sub {
            $self->_clear_handle;
            undef $handle;
        });

        return $handle;
    },
);

sub power_on {
    my $self = shift;

    print STDERR "Turning on TV... ";
    $self->_handle->push_write("on 0\n");
    print STDERR "ok.\n";
}

sub power_off {
    my $self = shift;

    print STDERR "Turning off TV... ";
    $self->_handle->push_write("standby 0\n");
    print STDERR "ok.\n";
}

sub set_active_source {
    my $self = shift;

    $self->power_on;

    print STDERR "Setting self as active source for TV ... ";
    $self->_handle->push_write("as\n");
    print STDERR "ok.\n";
}

1;

