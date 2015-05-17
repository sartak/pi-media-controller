package Pi::Media::GamepadManager;
use 5.14.0;
use Mouse;
use Pi::Media::Gamepad::Wiimote;

has config => (
    is       => 'ro',
    isa      => 'HashRef',
    required => 1,
);

has gamepads => (
    is      => 'ro',
    isa     => 'ArrayRef[Pi::Media::Gamepad]',
    default => sub { [] },
);

has _wiimote_handle => (
    is      => 'rw',
    clearer => '_clear_wiimote_handle',
);

has _wiimote_buffer => (
    is      => 'rw',
    isa     => 'Str',
    default => '',
);

sub scan {
    my $self = shift;
    $self->scan_wiimote;
}

sub scan_wiimote {
    my $self = shift;

    $self->_wiimote_buffer('');

    my $handle = AnyEvent::Run->new(
        cmd => ['hcitool', 'scan'],
    );

    $self->_wiimote_handle($handle);

    $handle->on_read(sub {
        my ($handle) = @_;
        my $buf = $handle->{rbuf};
        $handle->{rbuf} = '';

        $self->_wiimote_buffer($self->_wiimote_buffer . $buf);
    });

    $handle->on_eof(undef);

    $handle->on_error(sub {
        undef $handle;
        $self->_wiimote_handle(undef);

        warn((scalar localtime) . " on_error: " . $self->_wiimote_buffer);

        for my $id ($self->_wiimote_buffer =~ m{(\w\w:\w\w:\w\w:\w\w:\w\w:\w\w)}g) {
            if (!$self->gamepad_with_id($id)) {
                my $gamepad = Pi::Media::Gamepad::Wiimote->new(
                    config  => $self->config,
                    led     => (1 + @{ $self->gamepads }),
                    id      => $id,
                    manager => $self,
                );

                $gamepad->scan;

                push @{ $self->gamepads }, $gamepad;
            }
        }

        # immediately start scanning again
        $self->scan_wiimote;
    });
}

sub gamepad_with_id {
    my $self = shift;
    my $id   = shift;

    for my $gamepad (@{ $self->gamepads }) {
        if ($gamepad->id eq $id) {
            return $gamepad;
        }
    }

    return 0;
}

sub disconnect_all {
    my $self = shift;
    @{ $self->gamepads } = ();
}

sub remove_gamepad {
    my $self = shift;
    my $pad  = shift;

    @{ $self->gamepads } = grep { $_ != $pad } @{ $self->gamepads };
}

1;

