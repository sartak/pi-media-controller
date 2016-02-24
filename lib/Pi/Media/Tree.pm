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

has join_clause => (
    is  => 'ro',
    isa => 'Maybe[Str]',
);

has where_clause => (
    is  => 'ro',
    isa => 'Maybe[Str]',
);

has order_clause => (
    is  => 'ro',
    isa => 'Maybe[Str]',
);

has limit_clause => (
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

has sort_order => (
    is  => 'ro',
    isa => 'Maybe[Int]',
);

sub TO_JSON {
    my $self = shift;
    my $frozen = { map { $_ => $self->$_ } qw/id label color parentId sort_order/ };

    $frozen->{requestPath} = $self->{requestPath} if $self->{requestPath};
    $frozen->{type} = 'tree';

    return $frozen;
}

sub has_clause {
    my $self = shift;
    return $self->join_clause
        || $self->where_clause
        || $self->order_clause
        || $self->limit_clause;
}

1;
