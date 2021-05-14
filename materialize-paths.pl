#!/usr/bin/env perl
use 5.14.0;
use warnings;
use utf8::all;
use Pi::Media::Library;

my $library = Pi::Media::Library->new;
my @roots = $library->trees(parentId => 0);
my @trees = map { ["", length(scalar(@roots)-1), $_] } @roots;
my %i_for;

$library->begin;

while ($_ = shift @trees) {
    my ($parent_path, $digits, $tree) = @$_;
    my $path;
    $path = $parent_path . "." if $parent_path;
    $path .= sprintf "%0${digits}d", $i_for{$parent_path}++;
    my @children = $library->trees(parentId => $tree->id);
    push @trees, map { [$path, (length scalar @children), $_] } @children;

    if (($tree->materialized_path||'') ne $path) {
        $library->update_tree($tree, (
            materialized_path => $path,
        ));
    }

    my $i = 0;
    my @media = $library->media(treeId => $tree->id, excludeViewing => 1, no_materialized_path_sort => 1);
    $digits = length(scalar(@media)-1);
    for my $media (@media) {
        my $media_path = sprintf "%s/%0${digits}d", $path, $i++;
        if (($media->materialized_path||'') ne $media_path) {
            $library->update_media($media, (
                materialized_path => $media_path,
            ));
        }
    }
}

$library->commit;
