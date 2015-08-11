package Pi::Media::Queue::Autofilling;
use 5.14.0;
use Mouse;
extends 'Pi::Media::Queue';

has source => (
    is      => 'rw',
    isa     => 'Pi::Media::Tree',
    clearer => 'clear_autofill_source',
);

has requestor => (
    is      => 'rw',
    isa     => 'Str',
    clearer => 'clear_requestor',
);

sub shift {
    my $self = CORE::shift(@_);
    my $media = $self->SUPER::shift(@_);
    return $media if $media;

    return unless $self->source;

    ($media) = $self->library->media(where => $self->source->query, limit => 1);
    $media->{requestor} = $self->requestor;
    $self->notify({ type => 'queue', shift => $media, autofill => 1 });
    return $media;
}

sub has_media {
    my $self = CORE::shift(@_);

    if ($self->source) {
        return 1;
    }
    else {
        return $self->SUPER::has_media(@_);
    }
}

1;

