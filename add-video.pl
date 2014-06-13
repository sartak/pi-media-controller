#!/usr/bin/env perl
use 5.14.0;
use warnings;
use Getopt::Whatever;
use Pi::Media::Library;

my $medium         = $ARGV{medium} or usage("medium required");
my $series         = $ARGV{series};
my $season         = $ARGV{season};
my $name           = $ARGV{name} or usage("name required");
my $spoken_langs   = $ARGV{spoken_langs} or usage("spoken_langs required");
my $subtitle_langs = $ARGV{subtitle_langs} or usage("subtitle_langs required");

$spoken_langs =~ m{^[a-z,\?]+$} or usage("spoken_langs must be a comma-separated list");
$subtitle_langs =~ m{^[a-z,\?]+$} or usage("subtitle_langs must be a comma-separated list");

my $path = shift or usage("path required");
@ARGV == 0 or usage("must have no stray args");

exists($ARGV{immersible}) || exists($ARGV{noimmersible}) or usage("immersible or noimmersible required");
exists($ARGV{streamable}) || exists($ARGV{unstreamable}) or usage("streamable or unstreamable required");

$path =~ s/~/$ENV{HOME}/;
-r $path && !-d _
    or die "path $path must be a readable file";

my $immersible = $ARGV{immersible} ? 1 : 0;
my $streamable = $ARGV{streamable} ? 1 : 0;

my $library = Pi::Media::Library->new;
$library->insert_video(
    name           => $name,
    path           => $path,
    spoken_langs   => [split ',', $spoken_langs],
    subtitle_langs => [split ',', $subtitle_langs],
    immersible     => $immersible,
    streamable     => $streamable,
    medium         => $medium,
    series         => $series,
    season         => $season,
);

sub usage {
    my $reason = shift;
    die "$reason\nusage: $0 --medium=MEDIUM [--series=SERIES] [--season=SEASON] --name=NAME --spoken_langs=en,ja --subtotle_langs=en,ja --immersible|--noimmersible --streamable|--unstreamable PATH";
}

