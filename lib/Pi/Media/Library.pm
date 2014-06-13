package Pi::Media::Library;
use 5.14.0;
use Mouse;
use Pi::Media::Video;
use DBI;

has dbh => (
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
    handles => {
        _prepare => 'prepare',
    },
);

sub file { 'library.sqlite' }

sub _inflate_videos_from_sth {
    my ($self, $sth) = @_;

    my @videos;

    while (my ($id, $path, $name, $immersible, $streamable, $medium, $series, $season) = $sth->fetchrow_array) {
        my $video = Pi::Media::Video->new(
            id         => $id,
            path       => $path,
            name       => $name,
            immersible => $immersible,
            streamable => $streamable,
            medium     => $medium,
            series     => $series,
            season     => $season,
        );
        push @videos, $video;
    }

    return @videos;
}

sub videos {
    my ($self) = @_;

    my $sth = $self->_prepare('
        SELECT
            video.id, video.path, video.name, video.immersible, video.streamable, medium.name, series.name, season.name
        FROM video
        JOIN      medium ON video.mediumId = medium.id
        LEFT JOIN series ON video.seriesId = series.id
        LEFT JOIN season ON video.seasonId = season.id
        ;
    ');

    $sth->execute($id);
}

sub get_video_by_id {
    my ($self, $id) = @_;

    my $sth = $self->_prepare('
        SELECT
            video.id, video.path, video.name, video.immersible, video.streamable, medium.name, series.name, season.name
        FROM video
        JOIN      medium ON video.mediumId = medium.id
        LEFT JOIN series ON video.seriesId = series.id
        LEFT JOIN season ON video.seasonId = season.id
        WHERE id = ?
        LIMIT 1
    ;');

    $sth->execute($id);

    my @videos = $self->_inflate_videos_from_sth($sth);
    return $videos[0];
}

1;

