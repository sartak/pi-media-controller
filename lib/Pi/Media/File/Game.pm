package Pi::Media::File::Game;
use 5.14.0;
use Mouse;
extends 'Pi::Media::File';

has playtime => (
    is      => 'rw',
    isa     => 'Int',
    default => 0,
);

has spoken_langs => (
    is       => 'ro',
    isa      => 'ArrayRef[Str]',
    required => 1,
);

has subtitle_langs => (
    is       => 'ro',
    isa      => 'ArrayRef[Str]',
    required => 1,
);

sub TO_JSON {
    my $self = shift;
    my $frozen = $self->SUPER::TO_JSON(@_);

    for (qw/playtime/) {
        $frozen->{$_} = $self->$_;
    };

    $frozen->{spoken_langs} = $self->available_audio;
    $frozen->{subtitle_langs} = $self->available_subtitles;

    return $frozen;
}

1;

