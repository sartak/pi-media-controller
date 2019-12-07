#!/usr/bin/env perl
use 5.14.0;
use warnings;
use lib 'lib';
use lib 'extlib';
use utf8::all;
use Getopt::Whatever;
use autodie ':all';

die "--year required" unless $ARGV{year};
die "--weeks required" unless $ARGV{weeks};

my @weeks = ($ARGV{weeks} =~ /\d+/g);
my $label_weeks = join ', ', @weeks;
$label_weeks =~ s/, (\d+)$/ & $1/;

my $file_weeks = join '-', @weeks;

my $file = "/media/paul/Commercials/$ARGV{year}/$file_weeks.mp4";

unless (-e $file) {
    die "URL required" unless @ARGV == 1;
    my $url = "https://www.youtube.com/watch?v=" . shift;
    system qq{cd /media/paul/tmp; ~/youtube-dl --format=18 -o $file_weeks.mp4 "$url"};
    system "mv", "/media/paul/tmp/$file_weeks.mp4" => $file;
}

system(
    "perl",
    "-Ilib",
    "-Iextlib",
    "add-video.pl",
    "--streamable",
    "--tag=immersible",
    "--segments=Commercials",
    "--segments=Collection",
    "--segments=$ARGV{year}",
    "--label_en=Weeks $label_weeks",
    $file,
);

