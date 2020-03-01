#!/usr/bin/env perl
use 5.14.0;
use warnings;
use utf8::all;
use JSON;
use File::Slurp 'slurp';
use Getopt::Whatever;
use Pi::Media::Library;
use Pi::Media::Config;
use Sort::Naturally;

my $treeId = shift or die "usage: $0 [--verbose] [--path] treeId\n";

my $config = Pi::Media::Config->new;

my $library = Pi::Media::Library->new(
  file   => $ENV{PMC_DATABASE},
  config => $config,
);

$library->begin;

my @media = (
    $library->media(treeId => $treeId, excludeViewing => 1),
    $library->trees(parentId => $treeId),
);

my %fixup = %{ $config->value('sort_fixup')->{$treeId} || {} };
my %saw_fixup;

if ($ARGV{path}) {
    @media = sort { ncmp($a->path, $b->path) } @media;
}
else {
    @media = sort {
        my $a_label = $a->label->{en} || $a->label->{ja};
        my $b_label = $b->label->{en} || $b->label->{ja};

        if ($fixup{$a_label}) {
            $saw_fixup{$a_label}++;
            $a_label = $fixup{$a_label};
        }
        if ($fixup{$b_label}) {
            $saw_fixup{$b_label}++;
            $b_label = $fixup{$b_label};
        }

        $a_label =~ s/^The //;
        $b_label =~ s/^The //;

        $a_label =~ s/^An? //;
        $b_label =~ s/^An? //;

        $a_label cmp $b_label ||
        ($b->path =~ m{/English/} <=> $a->path =~ m{/English/}) ||
        $a->path cmp $b->path
    } @media;
}

for my $i (1 .. $#media+1) {
    my $media = $media[$i-1];

    if (!defined($media->sort_order) || $media->sort_order != $i) {
        say(($media->sort_order // 'X') . ' -> ' . $i . ': ' . ($media->label->{en} || $media->label->{ja})) if $ARGV{verbose};

        if ($media->isa('Pi::Media::Tree')) {
            $library->update_tree($media, sort_order => $i);
        }
        else {
            $library->update_media($media, sort_order => $i);
        }
    }
    else {
        say $i . ': ' . ($media->label->{en} || $media->label->{ja}) if $ARGV{verbose};
    }
}

for my $key (keys %fixup) {
    if (!$saw_fixup{$key}) {
        warn "Unused fixup: $key\n";
    }
}

$library->commit;
