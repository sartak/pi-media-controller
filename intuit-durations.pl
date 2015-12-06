#!/usr/bin/env perl
use 5.14.0;
use warnings;
use utf8::all;
use Pi::Media::Library;
use MP4::Info;
use Image::ExifTool ':Public';

my $library = Pi::Media::Library->new(file => $ENV{PMC_DATABASE});

# mp4, m4v
{
    my @videos;

    for my $extension ('mp4', 'm4v') {
        push @videos, $library->media(
            all            => 1,
            type           => 'video',
            excludeViewing => 1,
            pathLike       => "%.$extension",
            nullDuration   => 1,
        );
    }

    for my $video (@videos) {
        next unless -e $video->path;

        my $info = get_mp4info($video->path);
        my $secs = $info->{SECS};
        if (!$secs) {
            $secs = $info->{MM} * 60 + $info->{SS};
        }
        if ($secs) {
            $library->update_media($video, (
                durationSeconds => $secs,
            ));

            print "[$secs] " . $video->path . "\n";
        }
        else {
            warn $video->path
        }
    }
}

# mkv
{
    my @videos;

    for my $extension ('mkv', 'avi') {
        push @videos, $library->media(
            all            => 1,
            type           => 'video',
            excludeViewing => 1,
            pathLike       => "%.$extension",
            nullDuration   => 1,
        );
    }

    for my $video (@videos) {
        next unless -e $video->path;

        my $info = ImageInfo($video->path);
        my $secs;
        if (my ($h, $m, $s) = $info->{Duration} =~ /^(\d+):(\d+):(\d+)$/) {
            $secs = $h * 3600 + $m * 60 + $s;
        }

        if (my ($s) = $info->{Duration} =~ /^(\d+)(?:\.\d*)? s$/) {
            $secs = $s;
        }

        if ($secs) {
            $library->update_media($video, (
                durationSeconds => $secs,
            ));

            print "[$secs] " . $video->path . "\n";
        }
        else {
            warn $video->path;
        }
    }
}
