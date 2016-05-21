package Pi::Media::User;
use 5.14.0;
use Mouse;

has name => (
    is  => 'ro',
    isa => 'Str',
);

has password => (
    is  => 'ro',
    isa => 'Str',
);

has preferred_lang => (
    is  => 'ro',
    isa => 'Maybe[Str]',
);

sub TO_JSON {
    my $self = shift;
    my $frozen = { map { $_ => $self->$_ } qw/name preferred_lang/ };

    return $frozen;
}

1;

