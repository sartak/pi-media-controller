package Pi::Media::Queue;
use 5.14.0;
use Mouse;
use Pi::Media::File;
use Pi::Media::Library;
use Pi::Media::User;

has notify_cb => (
    is      => 'ro',
    default => sub { sub {} },
);

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

sub notify {
    my $self = shift;
    $self->notify_cb->(@_);
}

sub media {
    my $self = shift;
    return @{ $self->{_media} };
}

my $Serial = 0;

sub push {
    my $self = shift;

    for my $media (@_) {
        $media->{queue_id} = $$ . "-" . $Serial++;
        $media->{requestor} = $main::CURRENT_USER;
        push @{ $self->{_media} }, $media;
    }

    $self->notify({ type => 'queue', added => [ @_ ] });
}

sub remove_media_with_queue_id {
    my ($self, $queue_id) = @_;

    $self->notify({ type => 'queue', remove_id => $queue_id });
    @{ $self->{_media} } = grep { $_->{queue_id} ne $queue_id } @{ $self->{_media} };
}

sub has_media {
    my $self = shift;
    return scalar @{ $self->{_media} };
}

sub clear {
    my $self = shift;
    $self->notify({ type => 'queue', clear => 1 });
    @{ $self->{_media} } = ();
}

sub shift {
    my $self = shift;
    my $media = shift @{ $self->{_media} };
    $self->notify({ type => 'queue', shift => $media });
    return $media;
}

1;

