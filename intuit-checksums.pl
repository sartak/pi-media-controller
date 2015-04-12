#!/usr/bin/env perl
use 5.14.0;
use warnings;
use utf8::all;
use Pi::Media::Library;
use Digest::SHA1;

my $library = Pi::Media::Library->new(file => $ENV{PMC_DATABASE});

my @media = $library->media(
    all            => 1,
    excludeViewing => 1,
    nullChecksum   => 1,
);

for my $media (@media) {
    next unless -e $media->path;

    open my $handle, '<', $media->path;

    my $sha = Digest::SHA1->new;
    $sha->addfile($handle);
    my $checksum = lc($sha->hexdigest);

    $library->update_media($media, (
        checksum => $checksum,
    ));

    print "[$checksum] " . $media->path . "\n";
}

