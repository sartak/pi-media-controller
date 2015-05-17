package Pi::Media::Gamepad::Wiimote;
use 5.14.0;
use Mouse;
extends 'Pi::Media::Gamepad';

has manager => (
    is       => 'ro',
    isa      => 'Pi::Media::GamepadManager',
    required => 1,
    weak_ref => 1,
);

has _handle => (
    is      => 'rw',
    clearer => '_clear_handle',
);

has _buffer => (
    is => 'rw',
    isa => 'Str',
    default => '',
);

sub scan {
    my $self = shift;

    my $file = $self->config->{gamepad}{wiimote}{$self->led};

    warn "Attaching wiimote " . $self->led . " (" . $self->id . ")";

    my $handle = AnyEvent::Run->new(
        cmd => ['wminput', '-c', $file, $self->id],
    );
    $self->_handle($handle);

    $handle->on_read(sub {
        my ($handle) = @_;
        my $buf = $handle->{rbuf};
        $handle->{rbuf} = '';

        $self->_buffer($self->_buffer . $buf);
        warn $buf;
    });
    $handle->on_eof(sub {
        warn "eof";
    });

    $handle->on_error(sub {
            warn "on_error";
        undef $handle;
        $self->_handle(undef);

        $self->manager->remove_gamepad($self);
    });
}

1;

