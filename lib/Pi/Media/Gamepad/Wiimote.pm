package Pi::Media::Gamepad::Wiimote;
use 5.14.0;
use Mouse;
extends 'Pi::Media::Gamepad';

has wii_id => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has _handle => (
    is      => 'rw',
    clearer => '_clear_handle',
);

has _buffer => (
    is      => 'rw',
    isa     => 'Str',
    default => '',
);

sub scan {
    my $self = shift;
    my $cb   = shift;

    my $file = $self->config->{gamepad}{wiimote}{$self->led};
    warn $file;

    my $handle = AnyEvent::Run->new(
        cmd => ['wminput', '-c', $file, $self->wii_id],
    );
    $self->_handle($handle);
}

1;

