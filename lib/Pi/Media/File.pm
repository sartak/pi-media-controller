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


{
    my %language_map = (
        '?'   => 'Unknown',
        '??'  => 'Unknown',
        'ost' => 'Soundtrack',

        '/c'    => '(Commentary)',
        '/vi'   => '(Visually Impaired)',

        'en'    => 'English',
        '?/eng' => 'English(?)',

        'ja'    => 'Japanese',
        '?/jpn' => 'Japanese(?)',

        'can'   => 'Cantonese',
        'man'   => 'Mandarin',

        'es'    => 'Spanish',
        'fr'    => 'French',
        'de'    => 'German',
        'cs'    => 'Czech',
        'it'    => 'Italian',
        'ko'    => 'Korean',
        'pl'    => 'Polish',
        'pt'    => 'Portuguese',
        'ru'    => 'Russian',
        'sv'    => 'Swedish',
        'th'    => 'Thai',
        'zh'    => 'Chinese',
        'yua'   => 'Mayan',

        '?/ces' => 'Czech(?)',
        '?/deu' => 'German(?)',
        '?/fra' => 'French(?)',
        '?/ita' => 'Italian(?)',
        '?/kor' => 'Korean(?)',
        '?/pol' => 'Polish(?)',
        '?/por' => 'Portuguese(?)',
        '?/rus' => 'Russian(?)',
        '?/spa' => 'Spanish(?)',
        '?/swe' => 'Swedish(?)',
        '?/tha' => 'Thai(?)',
        '?/zho' => 'Chinese(?)',
        '?/hun' => 'Hungarian(?)',
        '?/ukr' => 'Ukranian(?)',
        '?/ind' => 'Indonesian(?)',
        '?/msa' => 'Malay(?)',
        '?/vie' => 'Vietnamese(?)',
    );

    sub label_for_language {
        my $class = shift;
        my $lang = shift;

        return $language_map{$lang} if $language_map{$lang};

        if ($lang =~ /&/) {
            return join ' & ',
                   map { $class->label_for_language($_) }
                   split /&/, $lang;
        }

        if (my ($l, $n) = $lang =~ m{^(.+)(/.+)$}) {
            $l = $language_map{$l};
            $n = $language_map{$n};
            return join ' ', $l, $n
                if $l && $n;
        }

        return;
    }
}

sub _fixup_langs {
    my $self = shift;
    my @langs = @_;

    my @out;
    for my $i (0..$#langs) {
        next if $langs[$i] eq '_';
        push @out, {
            id    => $i,
            type  => $langs[$i],
            label => $self->label_for_language($langs[$i]) || $langs[$i],
        };
    }
    return \@out;
}

sub available_audio {
    my $self = shift;
    return $self->_fixup_langs(@{ $self->spoken_langs });
}

sub available_subtitles {
    my $self = shift;
    return $self->_fixup_langs(@{ $self->subtitle_langs });
}

1;

