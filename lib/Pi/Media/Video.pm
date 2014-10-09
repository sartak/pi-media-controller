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

has treeId => (
    is  => 'ro',
    isa => 'Int',
);

has duration_seconds => (
    is  => 'ro',
    isa => 'Maybe[Int]',
);

has watched => (
    is  => 'rw',
    isa => 'Bool',
);

sub TO_JSON {
    my $self = shift;
    my $frozen = {
        map { $_ => $self->$_ } qw/id path identifier label spoken_langs subtitle_langs immersible streamable treeId duration_seconds watched/
    };

    $frozen->{queue_id} = $self->{queue_id} if $self->{queue_id};
    $frozen->{removePath} = $self->{removePath} if $self->{removePath};

    return $frozen;
}

1;
