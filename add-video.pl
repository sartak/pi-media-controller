#!/usr/bin/env perl
use 5.14.0;
use warnings;
use Getopt::Whatever;
use Pi::Media::Library;

my $medium = $ARGV{medium} or usage("medium required");
my $series = $ARGV{series};
my $season = $ARGV{season};
my $name   = $ARGV{name} or usage("name required");

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
    name       => $name,
    path       => $path,
    immersible => $immersible,
    streamable => $streamable,
    medium     => $medium,
    series     => $series,
    season     => $season,
);

sub usage {
    my $reason = shift;
    die "$reason\nusage: $0 --medium MEDIUM [--series SERIES] [--season SEASON] --name NAME --immersible|--noimmersible --streamable|--unstreamable PATH";
}

