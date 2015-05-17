package Pi::Media::Gamepad::Wiimote;
use 5.14.0;
use Mouse;
extends 'Pi::Media::Gamepad';

has wii_id => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

sub scan {
    my $self = shift;
    my $cb = shift;

    warn "led " . $self->led . " scan for " . $self->wii_id;
}

1;

