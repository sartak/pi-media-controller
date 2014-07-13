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
    isa     => 'ArrayRef[Pi::Media::Video]',
    default => sub { [] },
);

sub videos { return @{ shift->{_videos} } }
sub push { push @{ shift->{_videos} }, @_ }
sub shift { shift @{ shift->{_videos} } }
sub has_videos { scalar @{ shift->{_videos} } } }
sub clear { @{ shift->{_videos} } = () }

1;

