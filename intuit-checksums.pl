#!/usr/bin/env perl
use 5.14.0;
use warnings;
use utf8::all;
use Pi::Media::Library;
use Digest::SHA;

my $library = Pi::Media::Library->new;

my @media = $library->media(
    all            => 1,
    excludeViewing => 1,
    nullChecksum   => 1,
);

for my $media (@media) {
    next unless -e $media->path;

    open my $handle, '<:raw', $media->path;

    my $sha = Digest::SHA->new(1);
    $sha->addfile($handle);
    my $checksum = lc($sha->hexdigest);

    my @dupes = $library->media(
        all            => 1,
        excludeViewing => 1,
        checksum       => $checksum,
    );

    $library->update_media($media, (
        checksum => $checksum,
    ));

    print "fixed: [$checksum] " . $media->path . "\n";

    for my $dupe (@dupes) {
        print " ... same as " . $dupe->path . "\n";
    }
}

