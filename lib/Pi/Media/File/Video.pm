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
    isa => 'Maybe[Int]',
);

has skip1_end => (
    is => 'ro',
    isa => 'Maybe[Int]',
);

has skip2_start => (
    is => 'ro',
    isa => 'Maybe[Int]',
);

has skip2_end => (
    is => 'ro',
    isa => 'Maybe[Int]',
);

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
        'th'    => 'Thai',
        'zh'    => 'Chinese',

        '?/ces' => 'Czech(?)',
        '?/deu' => 'German(?)',
        '?/fra' => 'French(?)',
        '?/ita' => 'Italian(?)',
        '?/kor' => 'Korean(?)',
        '?/pol' => 'Polish(?)',
        '?/por' => 'Portuguese(?)',
        '?/rus' => 'Russian(?)',
        '?/spa' => 'Spanish(?)',
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
