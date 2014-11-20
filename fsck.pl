#!/usr/bin/env perl
use 5.14.0;
use warnings;
use utf8::all;
use Pi::Media::Library;

my $library = Pi::Media::Library->new(file => $ENV{PMC_DATABASE});
my %want_tree;
my %seen_tree;
my %want_tags;
my %seen_tags;

for my $video ($library->videos(all => 1, excludeViewing => 1)) {
    push @{ $want_tree{$video->treeId} }, $video;

    for my $label (values %{ $video->label }) {
        next unless $label =~ /^\s|\s$/;
        warn $video->id . ": label has extraneous space\n";
    }

    for my $tag ($video->tags) {
        $seen_tags{$tag} = 1;
    }

    unless (-r $video->path && !-d _) {
        warn $video->id . ': cannot read ' . $video->path . "\n";
    }
}

for my $tree ($library->trees(all => 1)) {
    push @{ $want_tree{$tree->parentId} }, $tree;
    $seen_tree{$tree->id}++;
}

delete $want_tree{0};
delete @want_tree{keys %seen_tree};

for my $want (sort keys %want_tree) {
    warn "Missing tree $want wanted by:\n";
    for my $by (@{ $want_tree{$want} }) {
        if ($by->isa('Pi::Media::Tree')) {
            warn "    tree " . $by->id . " (" . ($by->label->{en} || $by->label->{ja}) . ")";
        }
        elsif ($by->isa('Pi::Media::Video')) {
            warn "    video " . $by->id . " (" . ($by->label->{en} || $by->label->{ja}) . ")";
        }
        else {
            die $by;
        }
    }
}

for my $tag ($library->tags) {
    delete $seen_tags{$tag};
}

warn "Unknown tags found in videos: " . join ', ', keys %seen_tags
    if %seen_tags;
