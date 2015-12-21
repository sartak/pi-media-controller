#!/usr/bin/env perl
use 5.14.0;
use warnings;
use utf8::all;
use JSON;
use Getopt::Whatever;
use Pi::Media::Library;

my $treeId = shift or die "usage: $0 treeId\n";

my $library = Pi::Media::Library->new(file => $ENV{PMC_DATABASE});
$library->begin;

my ($tree) = $library->trees(id => $treeId);
if (!$tree->query) {
    die "tree $treeId has no where clause";
}

my @media = $library->media(where => $tree->query);

my $sth = $library->_dbh->prepare("INSERT INTO tree_media_sort (mediaId, treeId, identifier, sort_order) VALUES (?, ?, ?, ?);");

my $i = 0;
for my $media (@media) {
    # no way we can guess something useful, so at least make it easy to manage
    my $identifier = $media->label->{en} || $media->label->{ja};
    $sth->execute($media->id, $treeId, $identifier, ++$i);
    print $media->id . " ($i): $identifier\n";
}

$library->commit;

