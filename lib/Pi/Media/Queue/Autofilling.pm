package Pi::Media::Queue::Autofilling;
use 5.14.0;
use Mouse;
extends 'Pi::Media::Queue';

sub shift {
    my $self = shift;
    my $media = $self->SUPER::shift;
    return $media if $media;

    return $self->library->random_video_for_immersion;
}

sub has_media {
    return 1;
}

1;

