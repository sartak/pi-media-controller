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

sub scan {
    my $self = shift;

    my $file = $self->config->{gamepad}{wiimote}{$self->led};

    warn "Attaching wiimote " . $self->led . " (" . $self->id . ")";

    my $handle = AnyEvent::Run->new(
        cmd => ['wminput', '-c', $file, $self->id],
    );
    $self->_handle($handle);

    $handle->on_read(sub {
    });

    $handle->on_eof(sub {
        undef $handle;
        $self->_handle(undef);

        $self->manager->remove_gamepad($self);
    });

    $handle->on_error(sub {
        undef $handle;
        $self->_handle(undef);

        $self->manager->remove_gamepad($self);
    });
}

sub disconnect {
    my $self = shift;

    kill 'TERM', $self->_handle->{child_pid};
}

1;

