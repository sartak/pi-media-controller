package Pi::Media::Tree;
use 5.14.0;
use Mouse;

has id => (
    is  => 'ro',
    isa => 'Int',
);

has label => (
    is  => 'ro',
    isa => 'HashRef[Str]',
);

has query => (
    is  => 'ro',
    isa => 'Str',
);

has color => (
    is  => 'ro',
    isa => 'Str',
);

has parentId => (
    is  => 'ro',
    isa => 'Int',
);

sub TO_JSON {
    my $self = shift;
    my $frozen = { map { $_ => $self->$_ } qw/id label color parentId/ };

    $frozen->{requestPath} = $self->{requestPath} if $self->{requestPath};
    $frozen->{type} = 'tree';

    return $frozen;
}

sub where_clause {
    my $self = shift;

    if ($self->query) {
        return 'WHERE ' . $self->query;
    }
    else {
        return ('WHERE treeId=?', $self->id;
    }
}

1;
