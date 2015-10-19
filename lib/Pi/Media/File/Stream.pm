package Pi::Media::File::Stream;
use 5.14.0;
use Mouse;
extends 'Pi::Media::File';

has url => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

sub TO_JSON {
    my $self = shift;
    my $frozen = $self->SUPER::TO_JSON(@_);

    for (qw/url/) {
        $frozen->{$_} = $self->$_;
    };

    return $frozen;
}

1;

