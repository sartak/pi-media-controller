package Pi::Media::Library;
use 5.14.0;
use Mouse;
use Pi::Media::File::Video;
use Pi::Media::File::Game;
use Pi::Media::File::Book;
use Pi::Media::File::Stream;
use Pi::Media::Tree;
use Pi::Media::User;
use Pi::Media::Config;
use DBI;
use Path::Class;
use Time::HiRes 'time';
use Unicode::Normalize 'NFC';

has _dbh => (
    is      => 'ro',
    lazy    => 1,
    clearer => '_clear_dbh',
    default => sub {
        my $dbh = DBI->connect(
            "dbi:SQLite:dbname=" . shift->database,
            undef,
            undef,
	    { RaiseError => 1 },
        );
        $dbh->{sqlite_unicode} = 1;
        $dbh
    },
);

has database => (
    is      => 'ro',
    isa     => 'Str',
    default => $ENV{PMC_DATABASE},
);

has root => (
    is      => 'ro',
    isa     => 'Str',
    default => $ENV{PMC_MEDIA} . '/',
);

has config => (
    is       => 'ro',
    isa      => 'Pi::Media::Config',
    default  => sub { Pi::Media::Config->new },
);

has _resume_state_cache => (
    is      => 'ro',
    isa     => 'HashRef',
    default => sub { {} },
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

sub login_without_password {
    my ($self, $username) = @_;

    my $query = 'SELECT name, password, preferred_lang FROM user WHERE name=?;';

    my $sth = $self->_dbh->prepare($query);
    $sth->execute($username);

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
    my %streams_by_id;

    my $begin = time;

    while (my ($id, $type, $path, $identifier, $label_en, $label_ja, $spoken_langs, $subtitle_langs, $streamable, $durationSeconds, $treeId, $tags, $checksum, $sort_order, $materialized_path, $skip1_start, $skip1_end, $skip2_start, $skip2_end) = $sth->fetchrow_array) {
        my %label;
        $label{en} = $label_en if $label_en;
        $label{ja} = $label_ja if $label_ja;
        $tags = [grep { length } split '`', $tags];
        $spoken_langs ||= '';
        $subtitle_langs ||= '';

        my $media;
        if ($type eq 'video') {
            $media = Pi::Media::File::Video->new(
                id                => $id,
                type              => $type,
                path              => $self->_absolutify_path($path),
                identifier        => $identifier,
                label             => \%label,
                spoken_langs      => [split ',', $spoken_langs],
                subtitle_langs    => [split ',', $subtitle_langs],
                streamable        => $streamable,
                duration_seconds  => $durationSeconds,
                treeId            => $treeId,
                tags              => $tags,
                checksum          => $checksum,
                sort_order        => $sort_order,
                materialized_path => $materialized_path,
                skip1_start       => $skip1_start,
                skip1_end         => $skip1_end,
                skip2_start       => $skip2_start,
                skip2_end         => $skip2_end,
            );
            push @{ $videos_by_id{$id} ||= [] }, $media;
        }
        elsif ($type eq 'game') {
            $media = Pi::Media::File::Game->new(
                id                => $id,
                type              => $type,
                path              => $self->_absolutify_path($path),
                identifier        => $identifier,
                label             => \%label,
                spoken_langs      => [split ',', $spoken_langs],
                subtitle_langs    => [split ',', $subtitle_langs],
                streamable        => $streamable,
                treeId            => $treeId,
                tags              => $tags,
                checksum          => $checksum,
                sort_order        => $sort_order,
                materialized_path => $materialized_path,
            );
            push @{ $games_by_id{$id} ||= [] }, $media;
        }
        elsif ($type eq 'book') {
            $media = Pi::Media::File::Book->new(
                id                => $id,
                type              => $type,
                path              => $self->_absolutify_path($path),
                identifier        => $identifier,
                label             => \%label,
                spoken_langs      => [split ',', $spoken_langs],
                subtitle_langs    => [split ',', $subtitle_langs],
                streamable        => $streamable,
                treeId            => $treeId,
                tags              => $tags,
                checksum          => $checksum,
                sort_order        => $sort_order,
                materialized_path => $materialized_path,
            );
            push @{ $books_by_id{$id} ||= [] }, $media;
        }
        elsif ($type eq 'stream') {
            $media = Pi::Media::File::Stream->new(
                id                => $id,
                type              => $type,
                path              => $path,
                identifier        => $identifier,
                label             => \%label,
                spoken_langs      => [split ',', $spoken_langs],
                subtitle_langs    => [split ',', $subtitle_langs],
                streamable        => $streamable,
                treeId            => $treeId,
                tags              => $tags,
                checksum          => $checksum,
                sort_order        => $sort_order,
                materialized_path => $materialized_path,
            );
            push @{ $streams_by_id{$id} ||= [] }, $media;
        }
        else {
            die "Unknown type '$type' for row id $id";
        }

        push @media, $media;
    }

    warn "fetching all rows took " . (time - $begin) . "s" if $ENV{PMC_PROFILE};

    if (!$args{excludeViewing}) {
        Carp::confess "Need a CURRENT_USER to produce viewing data" if !$main::CURRENT_USER;

        if (keys %videos_by_id) {
            my $query = 'SELECT mediaId, MAX(endTime) FROM viewing WHERE';
            $query .= ' who=? AND mediaId IN (';
            $query .= join ', ', map { '?' } keys %videos_by_id;
            $query .= ') AND completed GROUP BY mediaId;';

            my $sth = $self->_dbh->prepare($query);
            warn "prepare viewing query at " . (time - $begin) . "s" if $ENV{PMC_PROFILE};

            $sth->execute($main::CURRENT_USER->name, keys %videos_by_id);
            warn "execute viewing query $query at " . (time - $begin) . "s" if $ENV{PMC_PROFILE};

            while (my ($id, $date) = $sth->fetchrow_array) {
                for my $video (@{ $videos_by_id{$id} }) {
                    $video->completed(1);
                    $video->last_played($date);
                }
            }
            warn "applying viewing query at " . (time - $begin) . "s" if $ENV{PMC_PROFILE};
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
                $query .= ') AND completed GROUP BY mediaId;';

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

    warn "viewing rows took " . (time - $begin) . "s" if $ENV{PMC_PROFILE};

    return @media;
}

sub _inflate_trees_from_sth {
    my ($self, $sth, %args) = @_;

    my @trees;

    while (my ($id, $label_en, $label_ja, $parentId, $color, $joins, $where, $group, $order, $limit, $sort_order, $media_tags, $materialized_path, $default_language) = $sth->fetchrow_array) {
        my %label;
        $label{en} = $label_en if $label_en;
        $label{ja} = $label_ja if $label_ja;
        $media_tags = [grep { length } split '`', $media_tags];

        my $tree = Pi::Media::Tree->new(
            id                => $id,
            label             => \%label,
            parentId          => $parentId,
            color             => $color,
            join_clause       => $joins,
            where_clause      => $where,
            group_clause      => $group,
            order_clause      => $order,
            limit_clause      => $limit,
            sort_order        => $sort_order,
            media_tags        => $media_tags,
            materialized_path => $materialized_path,
            default_language  => $default_language,
        );

        push @trees, $tree;
    }

    return @trees;
}

sub insert_video {
    my ($self, %args) = @_;

    $self->_dbh->do('
        INSERT INTO media
            (path, type, identifier, label_en, label_ja, spoken_langs, subtitle_langs, streamable, durationSeconds, treeId, tags, sort_order)
        VALUES (?, "video", ?, ?, ?, ?, ?, ?, ?, ?, ?, ? )
    ;', {}, (
        $self->_relativify_path($args{path}),
        $args{identifier},
        $args{label_en},
        $args{label_ja},
        (join ',', @{$args{spoken_langs}}),
        (join ',', @{$args{subtitle_langs}}),
        $args{streamable} ? 1 : 0,
        $args{durationSeconds},
        $args{treeId},
        ($args{tags} ? ('`' . (join '`', @{$args{tags}}) . '`') : ''),
        $args{sort_order},
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

sub insert_stream {
    my ($self, %args) = @_;

    $self->_dbh->do('
        INSERT INTO media
            (path, type, identifier, label_en, label_ja, spoken_langs, streamable, treeId)
        VALUES (?, "stream", ?, ?, ?, ?, ?, ?)
    ;', {}, (
        $args{path},
        $args{identifier},
        $args{label_en},
        $args{label_ja},
        (join ',', @{$args{spoken_langs}}),
        1,
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

    my $query = 'SELECT tree.id, tree.label_en, tree.label_ja, tree.parentId, tree.color, tree.join_clause, tree.where_clause, tree.group_clause, tree.order_clause, tree.limit_clause, tree.sort_order, tree.media_tags, tree.materialized_path, tree.default_language FROM tree';

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
    my ($joins, $limit, $order, $group);

    if ($args{query}) {
        push @where, '(label_en LIKE ? OR label_ja LIKE ?)';
        push @bind, "%" . $args{query} . "%";
        push @bind, "%" . $args{query} . "%";
    }
    elsif (!$args{all}) {
        push @where, 'media.treeId = ?';
        push @bind, $args{treeId};
    }

    if (ref($args{id})) {
        push @where, 'media.id IN (' . (join ',', map { '?' } @{ $args{id} }) . ')';
        push @bind, @{ $args{id} };
        delete $args{id};
    }

    if ($args{joins}) {
        $joins = $args{joins};
    }

    if ($args{limit}) {
        $limit = $args{limit};
    }

    my $distinct = $args{distinct};
    if ($args{group}) {
        $group = $args{group};
        $distinct = 1 if $group =~ s/^\*//;
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

    for my $column (qw/id type path identifier label_en label_ja spoken_langs subtitle_langs streamable durationSeconds checksum sort_order/) {
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
            " . ($distinct ? "DISTINCT(media.id)" : "media.id") . ",
            media.type, media.path, $identifier_column, $label_en_column, $label_ja_column, media.spoken_langs, media.subtitle_langs, media.streamable, media.durationSeconds, media.treeId, media.tags, media.checksum, media.sort_order, media.materialized_path, media.skip1Start, media.skip1End, media.skip2Start, media.skip2End
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

    $query .= " GROUP BY $group" if $group;

    $query .= ' ORDER BY ';

    if ($order) {
        $query .= " $order ";
    }
    else {
        if ($args{source_tree}) {
            $query .= 'tree_media_sort.sort_order, ';
        }

        unless ($args{no_materialized_path_sort}) {
            $query .= 'media.materialized_path ASC, ';
        }

        $query .= 'media.sort_order IS NULL, media.sort_order ASC, media.rowid ASC';
    }

    $query .= " LIMIT $limit" if $limit;
    $query .= ';';

    $query =~ s/\$CURRENT_USER/$self->_dbh->quote($main::CURRENT_USER->name)/ge;

    my $begin = time;

    my $sth = eval { $self->_dbh->prepare($query) };
    if ($@) {
        die "$query\n\n$@";
    }
    warn "prepare took " . (time - $begin) . "s" if $ENV{PMC_PROFILE};

    $sth->execute(@bind);
    warn "execute took " . (time - $begin) . "s" if $ENV{PMC_PROFILE};

    my @media = $self->_inflate_media_from_sth($sth, %args);
    warn "inflate took " . (time - $begin) . "s" if $ENV{PMC_PROFILE};

    return @media;
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
            id, type, path, identifier, label_en, label_ja, spoken_langs, subtitle_langs, streamable, durationSeconds, treeId, tags, checksum, sort_order, materialized_path, media.skip1start, media.skip1end, media.skip2start, media.skip2end
        FROM media
        WHERE id = ?
        LIMIT 1
    ;');

    $sth->execute($id);

    my @media = $self->_inflate_media_from_sth($sth, %args);
    return $media[0];
}

sub media_tags_for_tree {
    my ($self, $id) = @_;

    my $sth = $self->_dbh->prepare('
        SELECT media_tags
        FROM tree
        WHERE id = ?
        LIMIT 1
    ;');
    $sth->execute($id);

    if (my ($tags) = $sth->fetchrow_array) {
        return grep { length } split '`', $tags;
    }

    return;
}

sub add_viewing {
    my ($self, %args) = @_;

    my $id = $args{media_id} || $args{media}->id;

    delete $self->_resume_state_cache->{$id};

    $self->_dbh->do('
        INSERT INTO viewing
            (mediaId, startTime, endTime, initialSeconds, elapsedSeconds, completed, audioTrack, location, who)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ;', {}, (
        $id,
        $args{start_time},
        $args{end_time},
        $args{initial_seconds},
        $args{elapsed_seconds},
        $args{completed},
        $args{audio_track},
        $args{location},
        $args{who},
    ));
    my $rowid = $self->_dbh->sqlite_last_insert_rowid;

    if (my $target = $self->config->value('rsync_to_on_viewing')) {
      $self->_dbh->disconnect();
      $self->_clear_dbh();

      system("rsync", "-az", $self->database, $target);
    }

    return $rowid;
}

sub _resume_state_for_video {
    my ($self, $media) = @_;

    my $query = q{select initialSeconds, elapsedSeconds, audioTrack from viewing where mediaId=? and viewing.endTime > strftime('%s', 'now')-30*24*60*60 AND NOT viewing.completed and viewing.endTime = (select max(endTime) from viewing as v where v.mediaId = ? and v.who = ?) limit 1;};

    my $sth = $self->_dbh->prepare($query);
    $sth->execute($media->id, $media->id, $main::CURRENT_USER->name);

    my ($initial, $elapsed, $audio_track) = $sth->fetchrow_array
        or return;

    $initial += $elapsed || 0;
    return if $initial < 10 * 60;
    return ($initial, $audio_track);
}

sub resume_state_for_video {
    my ($self, $media) = @_;

    my $key = $media->id;
    if (!$self->_resume_state_cache->{$key}) {
        $self->_resume_state_cache->{$key} =
            [ $self->_resume_state_for_video($media) ];
    }
    return @{ $self->_resume_state_cache->{$key} };
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

    return Path::Class::dir($self->root)->file($relative)->stringify;
}

sub _relativify_path {
    my ($self, $absolute) = @_;

    return $absolute if $absolute =~ /^real:/;

    return Path::Class::file($absolute)->relative($self->root)->stringify;
}

sub database_directory {
  my $self = shift;
  return Path::Class::file($self->database)->dir->stringify;
}

sub last_game_played {
  my $self = shift;
  my @media = $self->media(
    all            => 1,
    joins          => 'JOIN viewing ON viewing.mediaId = media.id',
    where          => 'media.type = "game" AND viewing.startTime IS NOT NULL',
    order          => 'viewing.rowid DESC',
    limit          => '1',
    excludeViewing => 1,
  );
  return $media[0];
}

1;

