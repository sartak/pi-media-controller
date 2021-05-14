#!/usr/bin/env perl
use 5.14.0;
use warnings;
use utf8::all;
use Pi::Media::Library;
use Unicode::Normalize 'normalize';

my $form = shift or die "usage: $0 [form]";

my $library = Pi::Media::Library->new;

for my $media ($library->media(all => 1, excludeViewing => 1)) {
    my $path = $library->_relativify_path($media->path);
    my $normalized = normalize($form, $path);
    if ($normalized ne $path) {
        $library->update_media($media, (
            path => $normalized,
        ));
    }
}

