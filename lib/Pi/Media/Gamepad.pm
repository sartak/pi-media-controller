package Pi::Media::Gamepad;
use 5.14.0;
use Mouse;
use Pi::Media::Config;

has config => (
    is       => 'ro',
    isa      => 'Pi::Media::Config',
    required => 1,
);

has led => (
    is  => 'ro',
    isa => 'Int',
);

has id => (
    is  => 'ro',
    isa => 'Str',
);

1;

