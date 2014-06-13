package Pi::Media::Video;
use 5.14.0;
use Mouse;

has path => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has name => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

1;
