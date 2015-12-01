package Pi::Media::File::Video;
use 5.14.0;
use Mouse;
extends 'Pi::Media::File';

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

has immersible => (
    is       => 'ro',
    isa      => 'Bool',
    required => 1,
);

has duration_seconds => (
    is  => 'ro',
    isa => 'Maybe[Int]',
);

sub TO_JSON {
    my $self = shift;
    my $frozen = $self->SUPER::TO_JSON(@_);

    for (qw/spoken_langs subtitle_langs immersible duration_seconds/) {
        $frozen->{$_} = $self->$_;
    };

    $frozen->{streamPath} = $self->{streamPath} if $self->{streamPath};

    return $frozen;
}

1;
