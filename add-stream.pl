#!/usr/bin/env perl
use 5.14.0;
use warnings;
use utf8::all;
use Getopt::Whatever;
use Pi::Media::Library;
use Pi::Media::Config;

for my $key (keys %ARGV) {
    next if $key eq 'segments';
    die "Argument $key repeated. Accident?" if ref $ARGV{$key} eq 'ARRAY';
}

my $treeId = $ARGV{treeId};
my $segments = ref $ARGV{segments} ? $ARGV{segments} : [$ARGV{segments}];

$treeId || $ARGV{segments} or usage("treeId or segments required");

my $identifier = $ARGV{identifier};
warn "identifier probably shouldn't start with 0\n"
	if $identifier && $identifier =~ /^0\d/;

my $label_en = $ARGV{label_en};
my $label_ja = $ARGV{label_ja};
$label_en || $label_ja or die usage("Must have at least one of label_en or label_ja");

my $path = $ARGV[0] or usage("url required");
@ARGV == 1 or usage("must have no stray args: " . join(', ', @ARGV));

my @spoken_langs = map { defined($_) ? $_ : '' } split / *, */, $ARGV{spoken_langs};
@spoken_langs == 1 or die usage("Must have exactly 1 spoken_langs");

my $library = Pi::Media::Library->new(
  file   => $ENV{PMC_DATABASE},
  config => Pi::Media::Config->new,
);

if (!$treeId) {
    $treeId = $library->tree_from_segments(@$segments);
}

my $id = $library->insert_stream(
    path            => $path,
    identifier      => $identifier,
    label_en        => $label_en,
    label_ja        => $label_ja,
    spoken_langs    => \@spoken_langs,
    treeId          => $treeId,
);

print "Added " . ($label_ja || $label_en) . " as stream $id\n";

sub usage {
    my $reason = shift;
    die "$reason\nusage: $0 [--treeId=treeId OR --segments=foo --segments=bar] [--label_en=LABEL --label_ja=LABEL] [--identifier=IDENTIFIER] url";
}
