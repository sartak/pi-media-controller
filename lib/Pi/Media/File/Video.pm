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

has duration_seconds => (
    is  => 'ro',
    isa => 'Maybe[Int]',
);

has skip1_start => (
    is => 'ro',
    isa => 'Maybe[Num]',
);

has skip1_end => (
    is => 'ro',
    isa => 'Maybe[Num]',
);

has skip2_start => (
    is => 'ro',
    isa => 'Maybe[Num]',
);

has skip2_end => (
    is => 'ro',
    isa => 'Maybe[Num]',
);

sub skips {
    my $self = shift;
    my @skips;

    for my $id ("skip1", "skip2") {
      my $id_start = "${id}_start";
      my $id_end = "${id}_end";
      my $start = $self->$id_start;
      my $end = $self->$id_end;

      push @skips, [$start, $end] if $start || $end;
    }

    return @skips;
}

sub TO_JSON {
    my $self = shift;
    my $frozen = $self->SUPER::TO_JSON(@_);

    for (qw/duration_seconds/) {
        $frozen->{$_} = $self->$_;
    }

    my @skips = $self->skips;
    $frozen->{skips} = \@skips if @skips;

    $frozen->{spoken_langs} = $self->available_audio;
    $frozen->{subtitle_langs} = $self->available_subtitles;

    $frozen->{resume} = $self->{resume} if $self->{resume};

    return $frozen;
}

1;
