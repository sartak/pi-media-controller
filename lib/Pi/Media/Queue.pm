package Pi::Media::Queue;
use 5.14.0;
use Mouse;

has _videos => (
    traits  => 'Array',
    isa     => 'ArrayRef[Str]',
    default => sub { [] },
    handles => {
        push     => 'push',
        shift    => 'shift',
        count    => 'count',
        elements => 'videos',
        clear    => 'clear',
    },
);

1;

