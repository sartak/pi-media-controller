#!/usr/bin/env perl
use 5.14.0;
use warnings;
use Pi::Media::Library;

my $library = Pi::Media::Library->new;

for my $video ($library->videos) {
    next if -r $video->path && !-d _;

    warn $video->id . ': cannot read ' . $video->path . "\n";
}

