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
    isa => 'Maybe[Str]',
);

has color => (
    is  => 'ro',
    isa => 'Maybe[Str]',
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

1;
