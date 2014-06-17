package Pi::Media::Queue::Autofilling;
use 5.14.0;
use Mouse;
extends 'Pi::Media::Queue';

sub shift {
    my $self = shift;
    my $video = $self->SUPER::shift;
    return $video if $video;

    return $self->library->random_video_for_immersion;
}

sub has_videos {
    return 1;
}

1;

