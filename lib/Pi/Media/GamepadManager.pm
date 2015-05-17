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

sub scan {
    my $self = shift;
    $self->scan_wiimote;
}

sub scan_wiimote {
    my $self = shift;

    warn "launching";

    my $handle = AnyEvent::Run->new(
        cmd => ['hcitool', 'scan'],
    );

    $self->_wiimote_handle($handle);

    $handle->on_read(sub {
        my ($handle) = @_;
        my $buf = $handle->{rbuf};
        $handle->{rbuf} = '';
        warn "on_read: $buf";
    });

    $handle->on_eof(undef);

    $handle->on_error(sub {
        undef $handle;
        $self->_wiimote_handle(undef);

        # scan again?
        warn "on_error";
    });
}

sub disconnect_all {
    my $self = shift;
    @{ $self->gamepads } = ();
}

1;

