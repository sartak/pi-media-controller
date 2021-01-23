package Pi::Media::File::Stream;
use 5.14.0;
use Mouse;
extends 'Pi::Media::File';

sub TO_JSON {
    my $self = shift;
    my $frozen = $self->SUPER::TO_JSON(@_);

    return $frozen;
}

1;
