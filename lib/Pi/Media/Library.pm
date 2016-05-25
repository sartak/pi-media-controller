package Pi::Media::Library;
use 5.14.0;
use Mouse;
use Pi::Media::File::Video;
use Pi::Media::File::Game;
use Pi::Media::File::Book;
use Pi::Media::Tree;
use Pi::Media::User;
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

sub begin {
    my ($self) = @_;
    $self->_dbh->begin_work;
}

sub commit {
    my ($self) = @_;
    $self->_dbh->commit;
}

sub rollback {
    my ($self) = @_;
    $self->_dbh->rollback;
}

sub login {
    my ($self, $username, $password) = @_;

    my $query = 'SELECT name, password, preferred_lang FROM user WHERE name=? AND password=?;';

    my $sth = $self->_dbh->prepare($query);
    $sth->execute($username, $password);

    if (my ($name, $password, $preferred_lang) = $sth->fetchrow_array) {
        return Pi::Media::User->new(
            name           => $name,
            password       => $password,
            preferred_lang => $preferred_lang,
        );
    }

    return;
}

sub _inflate_media_from_sth {
    my ($self, $sth, %args) = @_;

    my @media;
    my %videos_by_id;
    my %games_by_id;
    my %books_by_id;

    while (my ($id, $type, $path, $identifier, $label_en, $label_ja, $spoken_langs, $subtitle_langs, $immersible, $streamable, $durationSeconds, $treeId, $tags, $checksum, $sort_order) = $sth->fetchrow_array) {
        my %label;
        $label{en} = $label_en if $label_en;
        $label{ja} = $label_ja if $label_ja;
        $tags = [grep { length } split '`', $tags];

        my $media;
        if ($type eq 'video') {
            $media = Pi::Media::File::Video->new(
                id               => $id,
                type             => $type,
                path             => $self->_absolutify_path($path),
                identifier       => $identifier,
                label            => \%label,
                spoken_langs     => [split ',', $spoken_langs],
                subtitle_langs   => [split ',', $subtitle_langs],
                immersible       => $immersible,
                streamable       => $streamable,
                duration_seconds => $durationSeconds,
                treeId           => $treeId,
                tags             => $tags,
                checksum         => $checksum,
                sort_order       => $sort_order,
            );
            push @{ $videos_by_id{$id} ||= [] }, $media;
        }
        elsif ($type eq 'game') {
            $media = Pi::Media::File::Game->new(
                id               => $id,
                type             => $type,
                path             => $self->_absolutify_path($path),
                identifier       => $identifier,
                label            => \%label,
                streamable       => $streamable,
                treeId           => $treeId,
                tags             => $tags,
                checksum         => $checksum,
                sort_order       => $sort_order,
            );
            push @{ $games_by_id{$id} ||= [] }, $media;
        }
        elsif ($type eq 'book') {
            $media = Pi::Media::File::Book->new(
                id               => $id,
                type             => $type,
                path             => $self->_absolutify_path($path),
                identifier       => $identifier,
                label            => \%label,
                streamable       => $streamable,
                treeId           => $treeId,
                tags             => $tags,
                checksum         => $checksum,
                sort_order       => $sort_order,
            );
            push @{ $books_by_id{$id} ||= [] }, $media;
        }
        else {
            die "Unknown type '$type' for row id $id";
        }

        push @media, $media;
    }

    if (!$args{excludeViewing}) {
        Carp::confess "Need a CURRENT_USER to produce viewing data" if !$main::CURRENT_USER;

        if (keys %videos_by_id) {
            my $query = 'SELECT mediaId, MAX(endTime) FROM viewing WHERE';
            $query .= ' who=? AND (';
            $query .= join ' OR ', map { 'mediaId=?' } keys %videos_by_id;
            $query .= ') AND elapsedSeconds IS NULL GROUP BY mediaId;';

            my $sth = $self->_dbh->prepare($query);
            $sth->execute($main::CURRENT_USER->name, keys %videos_by_id);

            while (my ($id, $date) = $sth->fetchrow_array) {
                for my $video (@{ $videos_by_id{$id} }) {
                    $video->completed(1);
                    $video->last_played($date);
                }
            }
        }

        if (keys %games_by_id) {
            # playtime
            {
                my $query = 'SELECT mediaId, SUM(elapsedSeconds) FROM viewing WHERE who=? AND (';
                $query .= join ' OR ', map { 'mediaId=?' } keys %games_by_id;
                $query .= ') GROUP BY mediaId;';

                my $sth = $self->_dbh->prepare($query);
                $sth->execute($main::CURRENT_USER->name, keys %games_by_id);

                while (my ($id, $playtime) = $sth->fetchrow_array) {
                    for my $game (@{ $games_by_id{$id} }) {
                        $game->playtime($playtime);
                    }
                }
            }

            # completed
            {
                my $query = 'SELECT mediaId FROM viewing WHERE who=? AND (';
                $query .= join ' OR ', map { 'mediaId=?' } keys %games_by_id;
                $query .= ') AND elapsedSeconds IS NULL GROUP BY mediaId;';

                my $sth = $self->_dbh->prepare($query);
                $sth->execute($main::CURRENT_USER->name, keys %games_by_id);

                while (my ($id) = $sth->fetchrow_array) {
                    for my $game (@{ $games_by_id{$id} }) {
                        $game->completed(1);
                    }
                }
            }
        }
    }

    return @media;
}

sub _inflate_trees_from_sth {
    my ($self, $sth, %args) = @_;

    my @trees;

    while (my ($id, $label_en, $label_ja, $parentId, $color, $joins, $where, $order, $limit, $sort_order) = $sth->fetchrow_array) {
        my %label;
        $label{en} = $label_en if $label_en;
        $label{ja} = $label_ja if $label_ja;

        my $tree = Pi::Media::Tree->new(
            id           => $id,
            label        => \%label,
            parentId     => $parentId,
            color        => $color,
            join_clause  => $joins,
            where_clause => $where,
            order_clause => $order,
            limit_clause => $limit,
            sort_order   => $sort_order,
        );

        push @trees, $tree;
    }

    return @trees;
}

sub insert_video {
    my ($self, %args) = @_;

    $self->_dbh->do('
        INSERT INTO media
            (path, type, identifier, label_en, label_ja, spoken_langs, subtitle_langs, immersible, streamable, durationSeconds, treeId, tags)
        VALUES (?, "video", ?, ?, ?, ?, ?, ?, ?, ?, ?, ? )
    ;', {}, (
        $self->_relativify_path($args{path}),
        $args{identifier},
        $args{label_en},
        $args{label_ja},
        (join ',', @{$args{spoken_langs}}),
        (join ',', @{$args{subtitle_langs}}),
        $args{immersible} ? 1 : 0,
        $args{streamable} ? 1 : 0,
        $args{durationSeconds},
        $args{treeId},
        ($args{tags} ? ('`' . (join '`', @{$args{tags}}) . '`') : ''),
    ));

    return $self->_dbh->sqlite_last_insert_rowid;
}

sub insert_game {
    my ($self, %args) = @_;

    $self->_dbh->do('
        INSERT INTO media
            (path, type, identifier, label_en, label_ja, streamable, treeId)
        VALUES (?, "game", ?, ?, ?, ?, ?)
    ;', {}, (
        $self->_relativify_path($args{path}),
        $args{identifier},
        $args{label_en},
        $args{label_ja},
        $args{streamable} ? 1 : 0,
        $args{treeId},
    ));

    return $self->_dbh->sqlite_last_insert_rowid;
}

sub insert_book {
    my ($self, %args) = @_;

    $self->_dbh->do('
        INSERT INTO media
            (path, type, identifier, label_en, label_ja, streamable, treeId)
        VALUES (?, "book", ?, ?, ?, ?, ?)
    ;', {}, (
        $self->_relativify_path($args{path}),
        $args{identifier},
        $args{label_en},
        $args{label_ja},
        0,
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

    if ($args{query}) {
        push @where, '(tree.label_en LIKE ? OR tree.label_ja LIKE ?)';
        push @bind, "%" . $args{query} . "%";
        push @bind, "%" . $args{query} . "%";
    }
    elsif ($args{id}) {
        push @where, 'tree.id = ?';
        push @bind, $args{id};
    }
    elsif (!$args{all}) {
        push @where, 'tree.parentId = ?';
        push @bind, $args{parentId};
    }

    my $query = 'SELECT tree.id, tree.label_en, tree.label_ja, tree.parentId, tree.color, tree.join_clause, tree.where_clause, tree.order_clause, tree.limit_clause, tree.sort_order FROM tree';

    if ($args{media_sort}) {
        $query .= ' LEFT JOIN tree_media_sort ON tree.id = tree_media_sort.treeId';
    }

    $query .= ' WHERE ' . join(' AND ', @where) if @where;

    if ($args{media_sort}) {
        $query .= ' GROUP BY tree_media_sort.treeId HAVING COUNT(tree_media_sort.treeId) > 0';
    }

    $query .= ' ORDER BY tree.sort_order IS NULL, tree.sort_order ASC, tree.id ASC';
    $query .= ';';

    my $sth = $self->_dbh->prepare($query);

    $sth->execute(@bind);
    return $self->_inflate_trees_from_sth($sth, %args);
}

sub media {
    my ($self, %args) = @_;

    my @bind;
    my @where;
    my ($joins, $limit, $order);

    if ($args{query}) {
        push @where, '(label_en LIKE ? OR label_ja LIKE ?)';
        push @bind, "%" . $args{query} . "%";
        push @bind, "%" . $args{query} . "%";
    }
    elsif (!$args{all}) {
        push @where, 'media.treeId = ?';
        push @bind, $args{treeId};
    }

    if ($args{joins}) {
        $joins = $args{joins};
    }

    if ($args{limit}) {
        $limit = $args{limit};
    }

    if ($args{order}) {
        $order = $args{order};
    }

    if ($args{where}) {
        push @where, $args{where};
    }

    if ($args{pathLike}) {
        push @bind, $args{pathLike};
        push @where, 'path LIKE ?';
    }

    if ($args{nullDuration}) {
        push @where, 'durationSeconds IS NULL';
    }

    if ($args{nullChecksum}) {
        push @where, 'checksum IS NULL';
    }

    if ($args{emptyLangs}) {
        push @where, "(spoken_langs='??' OR subtitle_langs='??')";
    }

    for my $column (qw/id type path identifier label_en label_ja spoken_langs subtitle_langs immersible streamable durationSeconds checksum sort_order/) {
        if ($args{$column}) {
            push @bind, $args{$column};
            push @where, "media.$column=?";
        }
    }
    
    my $identifier_column = 'media.identifier';
    my $label_en_column = 'media.label_en';
    my $label_ja_column = 'media.label_ja';
    if ($args{source_tree}) {
        $identifier_column = "COALESCE(tree_media_sort.identifier, $identifier_column)";
        $label_en_column = "COALESCE(tree_media_sort.label_en, $label_en_column)";
        $label_ja_column = "COALESCE(tree_media_sort.label_ja, $label_ja_column)";
    }

    my $query = "
        SELECT
            media.id, media.type, media.path, $identifier_column, $label_en_column, $label_ja_column, media.spoken_langs, media.subtitle_langs, media.immersible, media.streamable, media.durationSeconds, media.treeId, media.tags, media.checksum, media.sort_order
        FROM media
    ";

    if ($joins) {
        $query .= " $joins ";
    }

    if ($args{source_tree}) {
        $query .= 'LEFT JOIN tree_media_sort ON media.id = tree_media_sort.mediaId AND tree_media_sort.treeId = ? ';
        push @bind, $args{source_tree};
    }

    $query .= 'WHERE ' . join(' AND ', @where) if @where;

    $query .= ' ORDER BY ';

    if ($order) {
        $query .= " $order ";
    }
    else {
        if ($args{source_tree}) {
            $query .= 'tree_media_sort.sort_order, ';
        }

        $query .= 'media.sort_order IS NULL, media.sort_order ASC, media.rowid ASC';
    }

    $query .= " LIMIT $limit" if $limit;
    $query .= ';';

    $query =~ s/\$CURRENT_USER/$self->_dbh->quote($main::CURRENT_USER->name)/ge;
    my $sth = eval { $self->_dbh->prepare($query) };
    if ($@) {
        die "$query\n\n$@";
    }

    $sth->execute(@bind);

    return $self->_inflate_media_from_sth($sth, %args);
}

sub paths {
    my ($self) = @_;

    my $sth = $self->_dbh->prepare('SELECT path FROM media;');
    $sth->execute;

    my @paths;
    while (my ($path) = $sth->fetchrow_array) {
        push @paths, $self->_absolutify_path($path);
    }

    return @paths;
}

sub media_with_id {
    my ($self, $id, %args) = @_;

    my $sth = $self->_dbh->prepare('
        SELECT
            id, type, path, identifier, label_en, label_ja, spoken_langs, subtitle_langs, immersible, streamable, durationSeconds, treeId, tags, checksum, sort_order
        FROM media
        WHERE id = ?
        LIMIT 1
    ;');

    $sth->execute($id);

    my @media = $self->_inflate_media_from_sth($sth, %args);
    return $media[0];
}

sub add_viewing {
    my ($self, %args) = @_;
    $self->_dbh->do('
        INSERT INTO viewing
            (mediaId, startTime, endTime, initialSeconds, elapsedSeconds, audioTrack, location, who)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ;', {}, (
        $args{media}->id,
        $args{start_time},
        $args{end_time},
        $args{initial_seconds},
        $args{elapsed_seconds},
        $args{audio_track},
        $args{location},
        $args{who},
    ));
}

sub resume_state_for_video {
    my ($self, $media) = @_;

    my $query = q{select initialSeconds, elapsedSeconds, audioTrack from viewing where mediaId=? and viewing.endTime > strftime('%s', 'now')-30*24*60*60 AND viewing.elapsedSeconds IS NOT NULL and viewing.endTime = (select max(endTime) from viewing as v where v.mediaId = ? and v.who = ?) limit 1;};

    my $sth = $self->_dbh->prepare($query);
    $sth->execute($media->id, $media->id, $main::CURRENT_USER->name);

    my ($initial, $elapsed, $audio_track) = $sth->fetchrow_array;
    $initial += $elapsed || 0;
    return if $initial < $media->duration_seconds * .1;
    return if $initial < 10 * 60;
    return ($initial, $audio_track);
}

sub update_media {
    my ($self, $media, %args) = @_;
    my (@columns, @bind);

    for my $column (keys %args) {
        push @columns, $column;
        push @bind, $args{$column};
    }

    my $query = 'UPDATE media SET ';
    $query .= join ', ', map { "$_=?" } @columns;
    $query .= ' WHERE rowid=?;';
    $self->_dbh->do($query, {}, @bind, $media->id);
}

sub update_tree {
    my ($self, $tree, %args) = @_;
    my (@columns, @bind);

    for my $column (keys %args) {
        push @columns, $column;
        push @bind, $args{$column};
    }

    my $query = 'UPDATE tree SET ';
    $query .= join ', ', map { "$_=?" } @columns;
    $query .= ' WHERE rowid=?;';
    $self->_dbh->do($query, {}, @bind, $tree->id);
}

sub _absolutify_path {
    my ($self, $relative) = @_;

    return $relative if $relative =~ /^real:/;

    return Path::Class::file($self->file)->dir->file($relative)->stringify;
}

sub _relativify_path {
    my ($self, $absolute) = @_;

    return $absolute if $absolute =~ /^real:/;

    return Path::Class::file($absolute)->relative(Path::Class::file($self->file)->dir)->stringify;
}

sub stream_tmp {
    my $self = shift;

    return Path::Class::file($self->file)->dir->subdir('tmp')->stringify . '/';
}

1;

