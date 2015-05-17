package Pi::Media::GamepadManager;
use 5.14.0;
use Mouse;
use Pi::Media::Gamepad;

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

    my $handle = AnyEvent::Run->new(
        cmd => ['hcitool', 'scan'],
    );

    $self->_wiimote_handle($handle);

    $handle->on_read(sub {
        my ($handle) = @_;
        my $buf = $handle->{rbuf};
        $handle->{rbuf} = '';

        $self->_buffer($self->_buffer . $buf);
    });

    $handle->on_eof(undef);

    $handle->on_error(sub {
        undef $handle;
        $self->_wiimote_handle(undef);

        # scan again?
        warn "on_error: " . $self->_buffer;
    });
}

sub disconnect_all {
    my $self = shift;
    @{ $self->gamepads } = ();
}

1;

