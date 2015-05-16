package Pi::Media::Gamepad;
use 5.14.0;
use Mouse;

has config => (
    is       => 'ro',
    isa      => 'HashRef',
    required => 1,
);

has led => (
    is  => 'ro',
    isa => 'Int',
);

1;

