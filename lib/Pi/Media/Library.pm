package Pi::Media::Library;
use 5.14.0;
use Mouse;
use Pi::Media::Video;
use Pi::Media::Tree;
use DBI;
use Path::Class;
use Unicode::Normalize 'NFC';

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

has file => (
    is      => 'ro',
    isa     => 'Str',
    default => 'library.sqlite',
);

sub disconnect {
    my ($self) = @_;
    $self->_dbh->disconnect;
}

sub _inflate_videos_from_sth {
    my ($self, $sth, %args) = @_;

    my @videos;
    my %video_by_id;

    while (my ($id, $path, $identifier, $label_en, $label_ja, $spoken_langs, $subtitle_langs, $immersible, $streamable, $durationSeconds, $treeId) = $sth->fetchrow_array) {
        my %label;
        $label{en} = $label_en if $label_en;
        $label{ja} = $label_ja if $label_ja;

        my $video = Pi::Media::Video->new(
            id               => $id,
            path             => $self->_absolutify_path($path),
            identifier       => $identifier,
            label            => \%label,
            spoken_langs     => [split ',', $spoken_langs],
            subtitle_langs   => [split ',', $subtitle_langs],
            immersible       => $immersible,
            streamable       => $streamable,
            duration_seconds => $durationSeconds,
            treeId           => $treeId,
        );

        $video_by_id{$id} = $video;

        push @videos, $video;
    }

    if (!$args{excludeViewing} && keys %video_by_id) {
        my $query = 'SELECT videoId FROM viewing WHERE (';
        $query .= join ' OR ', map { 'videoId=?' } keys %video_by_id;
        $query .= ') AND elapsedSeconds IS NULL GROUP BY videoId;';

        my $sth = $self->_dbh->prepare($query);
        $sth->execute(keys %video_by_id);

        while (my ($id) = $sth->fetchrow_array) {
            $video_by_id{$id}->watched(1);
        }
    }

    return @videos;
}

sub _inflate_trees_from_sth {
    my ($self, $sth, %args) = @_;

    my @trees;

    while (my ($id, $label_en, $label_ja, $parentId) = $sth->fetchrow_array) {
        my %label;
        $label{en} = $label_en if $label_en;
        $label{ja} = $label_ja if $label_ja;

        my $tree = Pi::Media::Tree->new(
            id       => $id,
            label    => \%label,
            parentId => $parentId,
        );

        push @trees, $tree;
    }

    return @trees;
}

sub insert_video {
    my ($self, %args) = @_;

    $self->_dbh->do('
        INSERT INTO video
            (path, identifier, label_en, label_ja, spoken_langs, subtitle_langs, immersible, streamable, treeId)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ? )
    ;', {}, (
        $self->_relativify_path($args{path}),
        $args{identifier},
        $args{label_en},
        $args{label_ja},
        (join ',', @{$args{spoken_langs}}),
        (join ',', @{$args{subtitle_langs}}),
        $args{immersible} ? 1 : 0,
        $args{streamable} ? 1 : 0,
        $args{treeId},
    ));

    return $self->_dbh->sqlite_last_insert_rowid;
}

sub insert_tree {
    my ($self, %args) = @_;

    $self->_dbh->do('
        INSERT INTO tree
            (label_en, label_ja, parentId)
        VALUES (?, ?, ?)
    ;', {}, (
        $args{label_en},
        $args{label_ja},
        $args{parentId},
    ));

    return $self->_dbh->sqlite_last_insert_rowid;
}

sub tree_from_segments {
    my ($self, @segments) = @_;

    # when @segments = ('A')
    #   SELECT tree0.id
    #   FROM tree AS tree0
    #   WHERE
    #     (tree0.label_en = A OR tree0.label_ja = A)
    #   LIMIT 1

    # when @segments = ('A', 'B')
    #   SELECT tree0.id
    #   FROM tree AS tree0
    #   JOIN tree AS tree1 ON tree0.parentId = tree1.id
    #   WHERE
    #         (tree0.label_en = B OR tree0.label_ja = B)
    #     AND (tree1.label_en = A OR tree1.label_ja = A)
    #   LIMIT 1;

    # when @segments = ('A', 'B', 'C')
    #   SELECT tree0.id
    #   FROM tree AS tree0
    #   JOIN tree AS tree1 ON tree0.parentId = tree1.id
    #   JOIN tree AS tree2 ON tree1.parentId = tree2.id
    #   WHERE
    #         (tree0.label_en = C OR tree0.label_ja = C)
    #     AND (tree1.label_en = B OR tree1.label_ja = B)
    #     AND (tree2.label_en = A OR tree2.label_ja = A)
    #   LIMIT 1;

    my (@join, @where, @bind);

    my $i = 0;
    for my $segment (reverse @segments) {
        push @where, "(tree$i.label_en = ? OR tree$i.label_ja = ?)";
        push @bind, $segment, $segment;

        ++$i;
        push @join, "JOIN tree AS tree$i ON tree" . ($i-1) . ".parentId = tree$i.id";
    }

    pop @join;

    my $query = 'SELECT tree0.id FROM tree AS tree0 ';
    $query .= join " ", @join;
    $query .= ' WHERE ';
    $query .= join " AND ", @where;

    $query .= ' LIMIT 1;';

    my $sth = $self->_dbh->prepare($query);
    $sth->execute(@bind);
    my $id = ($sth->fetchrow_array)[0];
    if (!$id) {
        die "No path for segments: " . join(', ', map { qq{"$_"} } @segments);
    }
    return $id;
}

sub trees {
    my ($self, %args) = @_;

    my @bind;
    my @where;

    if (!$args{all}) {
        push @where, 'parentId = ?';
        push @bind, $args{parentId};
    }

    my $query = 'SELECT id, label_en, label_ja, parentId FROM tree';

    $query .= ' WHERE ' . join(' AND ', @where) if @where;
    $query .= ' ORDER BY sort_order IS NULL, sort_order ASC, id ASC';
    $query .= ';';

    my $sth = $self->_dbh->prepare($query);

    $sth->execute(@bind);
    return $self->_inflate_trees_from_sth($sth, %args);
}

sub videos {
    my ($self, %args) = @_;

    my @bind;
    my @where;

    if (!$args{all}) {
        push @where, 'video.treeId = ?';
        push @bind, $args{treeId};
    }

    if ($args{pathLike}) {
        push @bind, $args{pathLike};
        push @where, 'video.path LIKE ?';
    }

    if ($args{nullDuration}) {
        push @where, 'video.durationSeconds IS NULL';
    }

    my $query = '
        SELECT
            id, path, identifier, label_en, label_ja, spoken_langs, subtitle_langs, immersible, streamable, durationSeconds, treeId
        FROM video
    ';

    $query .= 'WHERE ' . join(' AND ', @where) if @where;
    $query .= ' ORDER BY sort_order IS NULL, sort_order ASC, rowid ASC';
    $query .= ';';

    my $sth = $self->_dbh->prepare($query);

    $sth->execute(@bind);

    return $self->_inflate_videos_from_sth($sth, %args);
}

sub paths {
    my ($self) = @_;

    my $sth = $self->_dbh->prepare('SELECT path FROM video;');
    $sth->execute;

    my @paths;
    while (my ($path) = $sth->fetchrow_array) {
        push @paths, $self->_absolutify_path($path);
    }

    return @paths;
}

sub video_with_id {
    my ($self, $id, %args) = @_;

    my $sth = $self->_dbh->prepare('
        SELECT
            id, path, identifier, label_en, label_ja, spoken_langs, subtitle_langs, immersible, streamable, durationSeconds, treeId
        FROM video
        WHERE id = ?
        LIMIT 1
    ;');

    $sth->execute($id);

    my @videos = $self->_inflate_videos_from_sth($sth, %args);
    return $videos[0];
}

sub random_video_for_immersion {
    my ($self) = @_;

    my $sth = $self->_dbh->prepare('
        SELECT
            id, path, identifier, label_en, label_ja, spoken_langs, subtitle_langs, immersible, streamable, durationSeconds, treeId
        FROM video
        WHERE immersible = 1 AND streamable = 1
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
            (videoId, startTime, endTime, elapsedSeconds)
        VALUES (?, ?, ?, ?)
    ;', {}, (
        $args{video}->id,
        $args{start_time},
        $args{end_time},
        $args{elapsed_seconds},
    ));
}

sub update_video {
    my ($self, $video, %args) = @_;
    my (@columns, @bind);

    for my $column (keys %args) {
        push @columns, $column;
        push @bind, $args{$column};
    }

    my $query = 'UPDATE video SET ';
    $query .= join ', ', map { "$_=?" } @columns;
    $query .= ' WHERE rowid=?;';
    $self->_dbh->do($query, {}, @bind, $video->id);
}

sub _absolutify_path {
    my ($self, $relative) = @_;

    my $path = Path::Class::file($self->file)->dir->file($relative)->stringify;
    return NFC($path);
}

sub _relativify_path {
    my ($self, $absolute) = @_;

    my $path = Path::Class::file($absolute)->relative(Path::Class::file($self->file)->dir)->stringify;
    return NFC($path);
}

1;

