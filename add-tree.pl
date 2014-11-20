#!/usr/bin/env perl
use 5.14.0;
use warnings;
use utf8::all;
use Getopt::Whatever;
use Pi::Media::Library;

for my $key (keys %ARGV) {
    next if $key eq 'segments';
    die "Argument $key repeated. Accident?" if ref $ARGV{$key} eq 'ARRAY';
}

my $parent   = $ARGV{parent};
my $segments = ref $ARGV{segments} ? $ARGV{segments} : [$ARGV{segments}];

$parent || $ARGV{segments} or usage("parent or segments required");

my $label_en = $ARGV{label_en};
my $label_ja = $ARGV{label_ja};
$label_en || $label_ja or die usage("Must have at least one of label_en or label_ja");

@ARGV == 0 or usage("must have no stray args");

my $library = Pi::Media::Library->new(file => $ENV{PMC_DATABASE});

if (!$parent) {
    $parent = $library->tree_from_segments(@$segments);
}

my $id = $library->insert_tree(
    label_en       => $label_en,
    label_ja       => $label_ja,
    parentId       => $parent,
);

print "Added " . ($label_ja || $label_en) . " as tree $id\n";

sub usage {
    my $reason = shift;
    die "$reason\nusage: $0 [--parent=PARENT OR --segments=foo --segments=bar] [--label_en=LABEL --label_ja=LABEL]";
}
