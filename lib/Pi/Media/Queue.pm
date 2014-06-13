package Pi::Media::Queue;
use 5.14.0;
use Mouse;
use Pi::Media::Video;

has _videos => (
    traits  => ['Array'],
    isa     => 'ArrayRef[Pi::Media::Video]',
    default => sub { [] },
    handles => {
        videos => 'elements',
        push   => 'push',
        shift  => 'shift',
        count  => 'count',
        clear  => 'clear',
    },
);

1;

