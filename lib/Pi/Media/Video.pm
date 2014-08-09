package Pi::Media::Video;
use 5.14.0;
use Mouse;

has id => (
    is  => 'ro',
    isa => 'Int',
);

has path => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has identifier => (
    is  => 'ro',
    isa => 'Maybe[Str]',
);

has label => (
    is  => 'ro',
    isa => 'HashRef[Str]',
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

has immersible => (
    is       => 'ro',
    isa      => 'Bool',
    required => 1,
);

has streamable => (
    is       => 'ro',
    isa      => 'Bool',
    required => 1,
);

has medium => (
    is  => 'ro',
    isa => 'Str',
);

has series => (
    is  => 'ro',
    isa => 'Maybe[Str]',
);

has season => (
    is  => 'ro',
    isa => 'Maybe[Str]',
);

sub TO_JSON {
    my $self = shift;
    my $frozen = {
        map { $_ => $self->$_ } qw/id path identifier label spoken_langs subtitle_langs immersible streamable medium series season/
    };

    $frozen->{queue_id} = $self->{queue_id} if $self->{queue_id};
    $frozen->{removePath} = $self->{removePath} if $self->{removePath};

    return $frozen;
}

1;
