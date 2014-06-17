package Pi::Media::Library;
use 5.14.0;
use Mouse;
use Pi::Media::Video;
use DBI;

has _dbh => (
    is      => 'ro',
    lazy    => 1,
    default => sub {
        my $dbh = DBI->connect(
            "dbi:SQLite:dbname=" . shift->file,
            undef,
            undef,
            { RaiseError => 1 },
        );
        $dbh->{sqlite_unicode} = 1;
        $dbh
    },
);

sub file { 'library.sqlite' }

sub _inflate_videos_from_sth {
    my ($self, $sth) = @_;

    my @videos;

    while (my ($id, $path, $identifier, $label_en, $label_ja, $spoken_langs, $subtitle_langs, $immersible, $streamable, $medium, $series, $season) = $sth->fetchrow_array) {
        my %label;
        $label{en} = $label_en if $label_en;
        $label{ja} = $label_ja if $label_ja;

        my $video = Pi::Media::Video->new(
            id             => $id,
            path           => $path,
            identifier     => $identifier,
            label          => \%label,
            spoken_langs   => [split ',', $spoken_langs],
            subtitle_langs => [split ',', $subtitle_langs],
            immersible     => $immersible,
            streamable     => $streamable,
            medium         => $medium,
            series         => $series,
            season         => $season,
        );
        push @videos, $video;
    }

    return @videos;
}

sub _id_for_medium {
    my ($self, $name) = @_;

    my $sth = $self->_dbh->prepare('SELECT id FROM medium WHERE label_en=? OR label_ja=?;');
    $sth->execute($name, $name);
    return ($sth->fetchrow_array)[0];
}

sub _id_for_medium_series {
    my ($self, $medium, $series) = @_;

    if ($series) {
        my $sth = $self->_dbh->prepare('SELECT mediumId, id FROM series WHERE label_en=? OR label_ja=?;');
        $sth->execute($series, $series);
        return $sth->fetchrow_array;
    }
    else {
        my $sth = $self->_dbh->prepare('SELECT id FROM medium WHERE label_en=? OR label_ja=?;');
        $sth->execute($medium, $medium);
        return $sth->fetchrow_array;
    }
}

sub _id_for_series {
    my ($self, $name) = @_;

    return undef if !$name;

    my $sth = $self->_dbh->prepare('SELECT id FROM series WHERE label_en=? OR label_ja=?;');
    $sth->execute($name, $name);
    return ($sth->fetchrow_array)[0];
}

sub _id_for_season {
    my ($self, $seriesId, $name) = @_;

    return undef if !defined($seriesId) || !$name;

    my $sth = $self->_dbh->prepare('SELECT id FROM season WHERE seriesId=? AND (label_en=? OR label_ja=?);');
    $sth->execute($seriesId, $name, $name);
    return ($sth->fetchrow_array)[0];
}

sub insert_video {
    my ($self, %args) = @_;

    my ($mediumId, $seriesId) = $self->_id_for_medium_series($args{medium}, $args{series})
        or die "unknown medium $args{medium} or series $args{series}";

    my $seasonId = $self->_id_for_season($seriesId, $args{season});

    die "no medium?" unless $mediumId;
    die "no series for $args{series}" if $args{series} && !$seriesId;
    die "unknown season $args{season} for series $args{series}" if $args{season} && !$seasonId;

    $self->_dbh->do('
        INSERT INTO video
            (path, identifier, label_en, label_ja, spoken_langs, subtitle_langs, immersible, streamable, mediumId, seriesId, seasonId)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ;', {}, (
        $args{path},
        $args{identifier},
        $args{label_en},
        $args{label_ja},
        (join ',', @{$args{spoken_langs}}),
        (join ',', @{$args{subtitle_langs}}),
        $args{immersible} ? 1 : 0,
        $args{streamable} ? 1 : 0,
        $mediumId,
        $seriesId,
        $seasonId,
    ));

    return $self->_dbh->last_insert_id;
}

sub insert_series {
    my ($self, %args) = @_;

    my $mediumId = $self->_id_for_medium($args{medium})
        or die "unknown medium $args{medium}";

    $self->_dbh->do('
        INSERT INTO series
            (label_en, label_ja, mediumId)
        VALUES (?, ?, ?)
    ;', {}, (
        $args{label_en},
        $args{label_ja},
        $mediumId,
    ));
}

sub insert_season {
    my ($self, %args) = @_;

    my $seriesId = $self->_id_for_series($args{series})
        or die "unknown series $args{series}";

    $self->_dbh->do('
        INSERT INTO season
            (label_en, label_ja, seriesId)
        VALUES (?, ?, ?)
    ;', {}, (
        $args{label_en},
        $args{label_ja},
        $seriesId,
    ));
}

sub videos {
    my ($self) = @_;

    my $sth = $self->_dbh->prepare('
        SELECT
            video.id, video.path, video.identifier, video.label_en, video.label_ja, video.spoken_langs, video.subtitle_langs, video.immersible, video.streamable, medium.id, series.id, season.id
        FROM video
        JOIN      medium ON video.mediumId = medium.id
        LEFT JOIN series ON video.seriesId = series.id
        LEFT JOIN season ON video.seasonId = season.id
        ;
    ');

    $sth->execute;

    return $self->_inflate_videos_from_sth($sth);
}

sub paths {
    my ($self) = @_;

    my $sth = $self->_dbh->prepare('SELECT path FROM video;');
    $sth->execute;

    my @paths;
    while (my ($path) = $sth->fetchrow_array) {
        push @paths, $path;
    }

    return @paths;
}

sub video_with_id {
    my ($self, $id) = @_;

    my $sth = $self->_dbh->prepare('
        SELECT
            video.id, video.path, video.identifier, video.label_en, video.label_ja, video.spoken_langs, video.subtitle_langs, video.immersible, video.streamable, medium.id, series.id, season.id
        FROM video
        JOIN      medium ON video.mediumId = medium.id
        LEFT JOIN series ON video.seriesId = series.id
        LEFT JOIN season ON video.seasonId = season.id
        WHERE video.id = ?
        LIMIT 1
    ;');

    $sth->execute($id);

    my @videos = $self->_inflate_videos_from_sth($sth);
    return $videos[0];
}

sub random_video_for_immersion {
    my ($self) = @_;

    my $sth = $self->_dbh->prepare('
        SELECT
            video.id, video.path, video.identifier, video.label_en, video.label_ja, video.spoken_langs, video.subtitle_langs, video.immersible, video.streamable, medium.id, series.id, season.id
        FROM video
        JOIN      medium ON video.mediumId = medium.id
        LEFT JOIN series ON video.seriesId = series.id
        LEFT JOIN season ON video.seasonId = season.id
        WHERE
            video.immersible = 1
            AND video.streamable = 1
        ORDER BY RANDOM()
        LIMIT 1
    ;');

    $sth->execute;

    my @videos = $self->_inflate_videos_from_sth($sth);
    return $videos[0];
}

sub add_viewing {
    my ($self, %args) = @_;
    $self->_dbh->do('
        INSERT INTO viewing
            (videoId, startTime, endTime, percent)
        VALUES (?, ?, ?, ?)
    ;', {}, (
        $args{video}->id,
        $args{start_time},
        $args{end_time},
        $args{percent},
    ));
}

1;

