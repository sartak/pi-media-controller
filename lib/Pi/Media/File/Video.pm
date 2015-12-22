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

has immersible => (
    is       => 'ro',
    isa      => 'Bool',
    required => 1,
);

has duration_seconds => (
    is  => 'ro',
    isa => 'Maybe[Int]',
);

my %language_map = (
    '?'   => 'Unknown',
    '??'  => 'Unknown',
    'ost' => 'Soundtrack',

    'en'    => 'English',
    'en/c'  => 'English (Commentary)',
    '?/eng' => 'English(?)',

    'ja'    => 'Japanese',
    'jp/c'  => 'Japanese (Commentary)',
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
);

sub label_for_language {
    my $class = shift;
    my $lang = shift;

    return $language_map{$lang};
}

sub TO_JSON {
    my $self = shift;
    my $frozen = $self->SUPER::TO_JSON(@_);

    for (qw/immersible duration_seconds/) {
        $frozen->{$_} = $self->$_;
    }

    for my $type (qw/spoken_langs subtitle_langs/) {
        my @langs = @{ $self->$type };
        my @out;
        for my $i (0..$#langs) {
            next if $langs[$i] eq '_';
            push @out, {
                id    => $i,
                type  => $langs[$i],
                label => $language_map{$langs[$i]} || $langs[$i],
            };
        }
        $frozen->{$type} = \@out;
    }

    $frozen->{streamPath} = $self->{streamPath} if $self->{streamPath};

    return $frozen;
}

1;
