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

    while (my ($id, $path, $name, $spoken_langs, $subtitle_langs, $immersible, $streamable, $medium, $series, $season) = $sth->fetchrow_array) {
        my $video = Pi::Media::Video->new(
            id             => $id,
            path           => $path,
            name           => $name,
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

    my $sth = $self->_dbh->prepare('SELECT id FROM medium WHERE name=?;');
    $sth->execute($name);
    return ($sth->fetchrow_array)[0];
}

sub _id_for_series {
    my ($self, $name, %args) = @_;

    return undef if !$name;

    my $sth = $self->_dbh->prepare('SELECT id FROM series WHERE name=?;');
    $sth->execute($name);
    my ($id) = $sth->fetchrow_array;
    return $id if defined $id;

    $self->_dbh->do('
        INSERT INTO series
            (name, mediumId)
        VALUES (?, ?)
    ;', {}, (
        $name,
        $args{mediumId},
    ));

    $sth = $self->_dbh->prepare('SELECT id FROM series WHERE name=?;');
    $sth->execute($name);
    return ($sth->fetchrow_array)[0];
}

sub _id_for_season {
    my ($self, $name, %args) = @_;

    return undef if !$name;

    my $sth = $self->_dbh->prepare('SELECT id FROM season WHERE name=?;');
    $sth->execute($name);
    my ($id) = $sth->fetchrow_array;
    return $id if defined $id;

    $self->_dbh->do('
        INSERT INTO season
            (name, seriesId)
        VALUES (?, ?)
    ;', {}, (
        $name,
        $args{seriesId},
    ));

    $sth = $self->_dbh->prepare('SELECT id FROM season WHERE name=?;');
    $sth->execute($name);
    return ($sth->fetchrow_array)[0];
}

sub insert_video {
    my ($self, %args) = @_;

    my $mediumId = $self->_id_for_medium($args{medium})
        or die "unknown medium $args{medium}";

    my $seriesId = $self->_id_for_series(
        $args{series},
        mediumId => $mediumId,
    );

    my $seasonId = $self->_id_for_season($args{season},
        mediumId => $mediumId,
        seriesId => $seriesId,
    );

    $self->_dbh->do('
        INSERT INTO video
            (path, name, spoken_langs, subtitle_langs, immersible, streamable, mediumId, seriesId, seasonId)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ;', {}, (
        $args{path},
        $args{name},
        (join ',', @{$args{spoken_langs}}),
        (join ',', @{$args{subtitle_langs}}),
        $args{immersible} ? 1 : 0,
        $args{streamable} ? 1 : 0,
        $mediumId,
        $seriesId,
        $seasonId,
    ));
}

sub videos {
    my ($self) = @_;

    my $sth = $self->_dbh->prepare('
        SELECT
            video.id, video.path, video.name, video.spoken_langs, video.subtitle_langs, video.immersible, video.streamable, medium.name, series.name, season.name
        FROM video
        JOIN      medium ON video.mediumId = medium.id
        LEFT JOIN series ON video.seriesId = series.id
        LEFT JOIN season ON video.seasonId = season.id
        ;
    ');

    $sth->execute;

    return $self->_inflate_videos_from_sth($sth);
}

sub video_with_id {
    my ($self, $id) = @_;

    my $sth = $self->_dbh->prepare('
        SELECT
            video.id, video.path, video.name, video.spoken_langs, video.subtitle_langs, video.immersible, video.streamable, medium.name, series.name, season.name
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

1;

