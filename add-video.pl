#!/usr/bin/env perl
use 5.14.0;
use warnings;
use utf8::all;
use Getopt::Whatever;
use Pi::Media::Library;

my $medium = $ARGV{medium};
my $series = $ARGV{series};

$medium || $series or usage("medium or series required");

my $season = $ARGV{season};
if ($season && !$series) { usage("series required if season present"); }

my $identifier     = $ARGV{identifier};
my $name           = $ARGV{name} or usage("name required");
my $spoken_langs   = $ARGV{spoken_langs} or usage("spoken_langs required");
my $subtitle_langs = $ARGV{subtitle_langs} or usage("subtitle_langs required");

$spoken_langs =~ m{^[a-z,\?]+$} or usage("spoken_langs must be a comma-separated list");
$subtitle_langs =~ m{^[a-z,\?]+$} or usage("subtitle_langs must be a comma-separated list");

exists($ARGV{immersible}) || exists($ARGV{noimmersible}) or usage("immersible or noimmersible required");
exists($ARGV{streamable}) || exists($ARGV{unstreamable}) or usage("streamable or unstreamable required");

my $label_en = $ARGV{label_en};
my $label_ja = $ARGV{label_ja};
$label_en || $label_ja or die usage("Must have at least one of label_en or label_ja");

my $path = shift or usage("path required");
@ARGV == 0 or usage("must have no stray args");

$path =~ s/~/$ENV{HOME}/;
-r $path && !-d _
    or die "path $path must be a readable file";

my $immersible = $ARGV{immersible} ? 1 : 0;
my $streamable = $ARGV{streamable} ? 1 : 0;

my $library = Pi::Media::Library->new;
$library->insert_video(
    path           => $path,
    identifier     => $identifier,
    label_en       => $label_en,
    label_ja       => $label_ja,
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
    die "$reason\nusage: $0 [--medium=MEDIUM --series=SERIES] [--season=SEASON] [--label_en=LABEL --label_ja=LABEL] [--identifier=IDENTIFIER] --spoken_langs=en,ja --subtotle_langs=en,ja --immersible|--noimmersible --streamable|--unstreamable PATH";
}

