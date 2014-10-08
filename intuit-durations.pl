#!/usr/bin/env perl
use 5.14.0;
use warnings;
use utf8::all;
use Pi::Media::Library;
use MP4::Info;

my $library = Pi::Media::Library->new(file => $ENV{PMC_DATABASE});
my @videos;

for my $extension ('mp4', 'm4v') {
    push @videos, $library->videos(
        excludeViewing => 1,
        pathLike       => "%.$extension",
        nullDuration   => 1,
    );
}

for my $video (@videos) {
    my $info = get_mp4info($video->path);
    my $secs = $info->{SECS};
    if (!$secs) {
        $secs = $info->{MM} * 60 + $info->{SS};
    }
    if ($secs) {
        $library->update_video($video, (
            durationSeconds => $secs,
        ));

        print "[$secs] " . $video->path . "\n";
    }
    else {
        warn $video->path
    }
}

