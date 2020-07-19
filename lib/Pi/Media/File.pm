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

has last_played => (
    is  => 'rw',
    isa => 'Maybe[Int]',
);

has tags => (
    is       => 'ro',
    isa      => 'ArrayRef[Str]',
    required => 1,
);

has checksum => (
    is  => 'ro',
    isa => 'Maybe[Str]',
);

has sort_order => (
    is  => 'ro',
    isa => 'Maybe[Str]',
);

has materialized_path => (
    is  => 'ro',
    isa => 'Maybe[Str]',
);

sub extension {
    my $self = shift;
    my ($extension) = $self->path =~ /^.+\.(\w+)$/;
    return $extension;
}

sub TO_JSON {
    my $self = shift;
    my $frozen = {
        map { $_ => $self->$_ } qw/id type path identifier label streamable treeId completed last_played tags checksum sort_order materialized_path/
    };

    $frozen->{queue_id} = $self->{queue_id} if $self->{queue_id};
    $frozen->{removePath} = $self->{removePath} if $self->{removePath};
    $frozen->{actions} = $self->{actions} if $self->{actions};
    $frozen->{extension} = $self->extension;

    return $frozen;
}

sub has_tag {
    my $self = shift;
    my $tag = shift;

    for my $t (@{ $self->tags }) {
        return 1 if $t eq $tag;
    }

    return;
}

sub description {
  my $self = shift;
  return $self->label->{en} || $self->label->{ja} || $self->path;
}

1;

