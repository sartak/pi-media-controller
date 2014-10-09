#!/usr/bin/env perl
use 5.14.0;
use warnings;
use utf8::all;
use Getopt::Whatever;
use Pi::Media::Library;

my $treeId = $ARGV{treeId};
my $segments = ref $ARGV{segments} ? $ARGV{segments} : [$ARGV{segments}];

$treeId || $ARGV{segments} or usage("treeId or segments required");

my $identifier = $ARGV{identifier};
warn "identifier probably shouldn't start with 0\n"
	if $identifier && $identifier =~ /^0\d/;

my $spoken_langs   = $ARGV{spoken_langs} or usage("spoken_langs required");
defined(my $subtitle_langs = $ARGV{subtitle_langs}) or usage("subtitle_langs required");

$spoken_langs =~ m{^[a-z,\?]+$} or usage("spoken_langs must be a comma-separated list");
$subtitle_langs =~ m{^[a-z,\?]*$} or usage("subtitle_langs must be a comma-separated list");

exists($ARGV{immersible}) || exists($ARGV{noimmersible}) or usage("immersible or noimmersible required");
exists($ARGV{streamable}) || exists($ARGV{unstreamable}) or usage("streamable or unstreamable required");

my $label_en = $ARGV{label_en};
my $label_ja = $ARGV{label_ja};
$label_en || $label_ja or die usage("Must have at least one of label_en or label_ja");

my $path = $ARGV[0] or usage("path required");
@ARGV == 1 or usage("must have no stray args: " . join(', ', @ARGV));

$path =~ s/~/$ENV{HOME}/;
-r $path && !-d _
    or die "path $path must be a readable file";

my $immersible = $ARGV{immersible} ? 1 : 0;
my $streamable = $ARGV{streamable} ? 1 : 0;

my $library = Pi::Media::Library->new(file => $ENV{PMC_DATABASE});

if (!$treeId) {
    $treeId = $library->tree_from_segments(@$segments);
}

my $id = $library->insert_video(
    path           => $path,
    identifier     => $identifier,
    label_en       => $label_en,
    label_ja       => $label_ja,
    spoken_langs   => [split ',', $spoken_langs],
    subtitle_langs => [split ',', $subtitle_langs],
    immersible     => $immersible,
    streamable     => $streamable,
    treeId         => $treeId,
);

print "Added " . ($label_ja || $label_en) . " as video $id\n";

sub usage {
    my $reason = shift;
    die "$reason\nusage: $0 [--treeId=treeId OR --segments=foo --segments=bar] [--label_en=LABEL --label_ja=LABEL] [--identifier=IDENTIFIER] --spoken_langs=en,ja --subtitle_langs=en,ja --immersible|--noimmersible --streamable|--unstreamable PATH";
}

