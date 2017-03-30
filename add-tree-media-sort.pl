#!/usr/bin/env perl
use 5.14.0;
use warnings;
use utf8::all;
use JSON;
use Getopt::Whatever;
use Pi::Media::Library;

my $library = Pi::Media::Library->new(file => $ENV{PMC_DATABASE});
my @trees = $library->trees(all => 1, media_sort => 1);
push @trees, $library->trees(id => $_) for @ARGV;

for my $tree (@trees) {
    next unless $tree->has_clause;

    $library->begin;
    my @media = $library->media(
        all            => 1,
        joins          => $tree->join_clause,
        where          => $tree->where_clause,
        order          => $tree->order_clause,
        group          => $tree->group_clause,
        limit          => $tree->limit_clause,
        source_tree    => $tree->id,
        excludeViewing => 1,
    );

    my $sth = $library->_dbh->prepare("INSERT OR IGNORE INTO tree_media_sort (mediaId, treeId, identifier, sort_order) VALUES (?, ?, ?, ?);");
    
    my $i = 0;
    for my $media (@media) {
        # no way we can guess something useful, so at least make it easy to manage
        my $identifier = $media->label->{en} || $media->label->{ja};
        my $result = $sth->execute($media->id, $tree->id, $identifier, ++$i);
        if ($result > 0) {
            print(($tree->label->{ja} || $tree->label->{en}) . " " . $media->id . " ($i): $identifier\n");
        }
    }

    $library->commit;
}
