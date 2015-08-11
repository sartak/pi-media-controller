package Pi::Media::Queue;
use 5.14.0;
use Mouse;
use Pi::Media::File;
use Pi::Media::Library;

has library => (
    is       => 'ro',
    isa      => 'Pi::Media::Library',
    required => 1,
);

has _media => (
    is      => 'bare',
    isa     => 'ArrayRef[Pi::Media::File]',
    default => sub { [] },
);

sub media {
    my $self = shift;
    return @{ $self->{_media} };
}

my $Serial = 0;

sub push {
    my $self = shift;

    for my $original (@_) {
        my %copy = %$original;

        $copy{queue_id} = $$ . "-" . $Serial++;
        push @{ $self->{_media} }, \%copy;
    }
}

sub remove_media_with_queue_id {
    my ($self, $queue_id) = @_;

    @{ $self->{_media} } = grep { $_->{queue_id} ne $queue_id } @{ $self->{_media} };
}

sub has_media {
    my $self = shift;
    return scalar @{ $self->{_media} };
}

sub clear {
    my $self = shift;
    @{ $self->{_media} } = ();
}

sub shift {
    my $self = shift;
    return shift @{ $self->{_media} };
}

1;

