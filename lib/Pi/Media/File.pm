package Pi::Media::File;
use 5.14.0;
use Mouse;

has id => (
    is  => 'ro',
    isa => 'Int',
);

has type => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
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

has streamable => (
    is       => 'ro',
    isa      => 'Bool',
    required => 1,
);

has treeId => (
    is  => 'ro',
    isa => 'Int',
);

has completed => (
    is  => 'rw',
    isa => 'Bool',
);

has tags => (
    is       => 'ro',
    isa      => 'ArrayRef[Str]',
    required => 1,
);

sub extension {
    my $self = shift;
    my ($extension) = $self->path =~ /^.+\.(\w+)$/;
    return $extension;
}

sub TO_JSON {
    my $self = shift;
    my $frozen = {
        map { $_ => $self->$_ } qw/id type path identifier label streamable treeId completed tags/
    };

    $frozen->{queue_id} = $self->{queue_id} if $self->{queue_id};
    $frozen->{removePath} = $self->{removePath} if $self->{removePath};

    return $frozen;
}

1;

