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
    is      => 'bare',
    isa     => 'ArrayRef[Pi::Media::Video]',
    default => sub { [] },
);

sub videos {
    my $self = shift;
    return @{ $self->{_videos} };
}

my $Serial = 0;

sub push {
    my $self = shift;

    for my $original (@_) {
        my $copy = \%$original;

        $copy->{queue_id} = $Serial++;
        push @{ $self->{_videos} }, $copy;
    }
}

sub remove_video_with_queue_id {
    my ($self, $queue_id) = @_;

    @{ $self->{_videos} } = grep { $_->{queue_id} ne $queue_id } @{ $self->{_videos} };
}

sub has_videos {
    my $self = shift;
    return scalar @{ $self->{_videos} };
}

sub clear {
    my $self = shift;
    @{ $self->{_videos} } = ();
}

sub shift {
    my $self = shift;
    return shift @{ $self->{_videos} };
}

1;

