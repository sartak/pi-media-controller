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

1;

