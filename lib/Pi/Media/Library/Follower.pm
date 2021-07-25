package Pi::Media::Library::Follower;
use 5.14.0;
use Mouse;
use DBD::SQLite::Constants qw/:file_open/;
use URI;
use LWP::UserAgent;

extends 'Pi::Media::Library';

has '+_dbh' => (
    default => sub {
        my $dbh = DBI->connect(
            "dbi:SQLite:dbname=" . shift->database,
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

    my $media = $args{media};
    my $leader = $self->config->value('leader');

    my %params = (
        mediaId        => $media->id,
        startTime      => $args{start_time},
        endTime        => $args{end_time},
        completed      => $args{completed},
        initialSeconds => $args{initial_seconds},
        endSeconds     => $args{initial_seconds} + $args{elapsed_seconds},
        audioTrack     => $args{audio_track},
        location       => $args{location},
        metadata       => $args{metadata},
    );

    my $uri = URI->new("$leader/library/viewed");
    $uri->query_form(\%params);

    my $user = $media->{requestor} || $main::CURRENT_USER;
    warn "No user!" if !$user;

    my %headers = (
        'X-PMC-Username' => $user->name,
        'X-PMC-Password' => $user->password,
    );

    my $ua = LWP::UserAgent->new;
    warn "PUT $uri";
    my $res = $ua->put($uri, %headers);
    warn "Forwarded to leader $leader, got " . $res->status_line;
    if (!$res->is_success) {
      die $res->status_line;
    }

    return $res->header('X-PMC-Viewing');
}

1;

