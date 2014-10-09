#!/usr/bin/env perl
use 5.14.0;
use warnings;
use utf8::all;
use Getopt::Whatever;
use Pi::Media::Library;

my $parent   = $ARGV{parent} or usage("parent required");
my $label_en = $ARGV{label_en};
my $label_ja = $ARGV{label_ja};
$label_en || $label_ja or die usage("Must have at least one of label_en or label_ja");

@ARGV == 0 or usage("must have no stray args");

my $library = Pi::Media::Library->new(file => $ENV{PMC_DATABASE});
$library->insert_tree(
    label_en       => $label_en,
    label_ja       => $label_ja,
    parentId       => $parent,
);

sub usage {
    my $reason = shift;
    die "$reason\nusage: $0 --parent=PARENT [--label_en=LABEL --label_ja=LABEL]";
}
