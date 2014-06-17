package Pi::Media::Queue;
use 5.14.0;
use Mouse;
use Pi::Media::Video;
use Pi::Media::Library;

has library => (
    is       => 'ro',
    isa      => 'Pi::Media::Library',
    required => 1,
);

has _videos => (
    traits  => ['Array'],
    isa     => 'ArrayRef[Pi::Media::Video]',
    default => sub { [] },
    handles => {
        videos     => 'elements',
        push       => 'push',
        shift      => 'shift',
        has_videos => 'count',
        clear      => 'clear',
    },
);

1;

