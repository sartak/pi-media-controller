package Pi::Media::Queue::Autofilling;
use 5.14.0;
use Mouse;
extends 'Pi::Media::Queue';

has source => (
    is      => 'rw',
    isa     => 'Pi::Media::Tree',
    clearer => 'clear_autofill_source',
);

sub shift {
    my $self = shift;
    my $media = $self->SUPER::shift;
    return $media if $media;

    return unless $self->source;

    ($media) = $self->library->media(where => $self->source->query, limit => 1);
    return $media;
}

sub has_media {
    my $self = shift;

    if ($self->source) {
        return 1;
    }
    else {
        return $self->SUPER::has_media(@_);
    }
}

1;

