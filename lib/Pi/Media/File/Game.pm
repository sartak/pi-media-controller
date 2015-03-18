package Pi::Media::File::Game;
use 5.14.0;
use Mouse;
extends 'Pi::Media::File';

has playtime => (
    is      => 'rw',
    isa     => 'Int',
    default => 0,
);

sub TO_JSON {
    my $self = shift;
    my $frozen = $self->SUPER::TO_JSON(@_);

    for (qw/playtime/) {
        $frozen->{$_} = $self->$_;
    };

    return $frozen;
}

1;

