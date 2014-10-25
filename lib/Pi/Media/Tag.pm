package Pi::Media::Tag;
use 5.14.0;
use Mouse;

has id => (
    is  => 'ro',
    isa => 'Str',
);

has label => (
    is  => 'ro',
    isa => 'HashRef[Str]',
);

sub TO_JSON {
    my $self = shift;
    my $frozen = { map { $_ => $self->$_ } qw/id label/ };

    $frozen->{requestPath} = $self->{requestPath} if $self->{requestPath};
    $frozen->{type} = 'tag';

    return $frozen;
}

1;
