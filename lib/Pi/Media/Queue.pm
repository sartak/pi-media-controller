package Pi::Media::Queue;
use 5.14.0;
use Mouse;

has _videos => (
    traits  => ['Array'],
    isa     => 'ArrayRef[Str]',
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

