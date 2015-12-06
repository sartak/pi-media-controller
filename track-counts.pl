#!/usr/bin/env perl
use 5.14.0;
use warnings;
use utf8::all;
use Pi::Media::Library;
use IPC::Run3;
use Encode 'encode_utf8';

my $library = Pi::Media::Library->new(file => $ENV{PMC_DATABASE});

my @media = $library->media(
    all            => 1,
    type           => 'video',
    excludeViewing => 1,
    emptyLangs     => 1,
);

my %seen;

for my $media (@media) {
    next unless -e $media->path;
    run3 [ "ffmpeg", "-i", $media->path ], \undef, \undef, \my $ffmpeg;

    my @streams = ($ffmpeg =~ /(Stream #\d+.\d+(?:\(\w+\))?: .*)/g);
    die $media->path . " no streams: " . $ffmpeg if !@streams;

    my (@video, @spoken, @subtitle);

    # assume softsubs
    push @subtitle, '';

    for my $stream (@streams) {
        my ($hint, $type, $next) = $stream =~ /^Stream #\d+.\d+(?:\((\w+)\))?: (\w+): (\w+)/ or die $media->path . " unparseable stream: " . $stream;
        my $lang = '?';
        $lang .= '/' . $hint if $hint && $hint ne 'und';

        if ($type eq 'Video' && $next eq 'mjpeg') {
            $type = 'Subtitle';
        }

        if ($type eq 'Video') {
            push @video, $stream;
        }
        elsif ($type eq 'Audio') {
            push @spoken, $lang;
            $seen{$lang}++;
        }
        elsif ($type eq 'Subtitle') {
            push @subtitle, $lang;
            $seen{$lang}++;
        }
        else {
            die $media->path . " invalid type $type: $stream";
        }
    }

    die $media->path . " not just 1 video: " . $ffmpeg if @video != 1;

    my $spoken = join ',', @spoken;
    my $subtitle = join ',', @subtitle;

    if ($media->path =~ m{/TV/日本語/} && ($spoken eq '?' || $spoken eq '?/jpn')) {
        $spoken = 'ja';
    }

    my %updates;
    $updates{spoken_langs} = $spoken if join('', @{ $media->spoken_langs }) eq '??';
    $updates{subtitle_langs} = $subtitle if join('', @{ $media->subtitle_langs }) eq '??';

    $library->update_media($media, %updates);

    print "[$spoken] [$subtitle] " if defined($updates{spoken_langs}) && defined($updates{subtitle_langs});
    print "[spoken:$spoken] " if defined($updates{spoken_langs}) && !defined($updates{subtitle_langs});
    print "[subs:$subtitle] " if !defined($updates{spoken_langs}) && defined($updates{subtitle_langs});

    print encode_utf8($media->path), "\n";
}

use Data::Dumper; warn Dumper(\%seen) if @media > 10;