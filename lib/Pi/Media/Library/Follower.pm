package Pi::Media::Library::Follower;
use 5.14.0;
use Mouse;
use DBD::SQLite::Constants qw/:file_open/;

extends 'Pi::Media::Library';

has '+_dbh' => (
    default => sub {
        my $dbh = DBI->connect(
            "dbi:SQLite:dbname=" . shift->file,
            undef,
            undef,
	    {
                RaiseError => 1,
                sqlite_open_flags => SQLITE_OPEN_READONLY,
	    },
        );
        $dbh->{sqlite_unicode} = 1;
        $dbh
    },
);

sub add_viewing {
    my ($self, %args) = @_;

    my %params = (
        mediaId        => $args{media}->id,
        startTime      => $args{start_time},
        endTime        => $args{end_time},
        completed      => $args{completed},
        initialSeconds => $args{initial_seconds},
        endSeconds     => $args{initial_seconds} + $args{elapsed_seconds},
        audioTrack     => $args{audio_track},
        location       => $args{location},
    );

    my $viewing_id = 'XXX';

    return $viewing_id;
}

1;

