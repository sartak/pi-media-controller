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

my $treeId = $ARGV{treeId};
my $segments = ref $ARGV{segments} ? $ARGV{segments} : [$ARGV{segments}];

$treeId || $ARGV{segments} or usage("treeId or segments required");

my $identifier = $ARGV{identifier};
warn "identifier probably shouldn't start with 0\n"
	if $identifier && $identifier =~ /^0\d/;

exists($ARGV{streamable}) || exists($ARGV{unstreamable}) or usage("streamable or unstreamable required");

my $label_en = $ARGV{label_en};
my $label_ja = $ARGV{label_ja};
$label_en || $label_ja or die usage("Must have at least one of label_en or label_ja");

my $path = $ARGV[0] or usage("path required");
@ARGV == 1 or usage("must have no stray args: " . join(', ', @ARGV));

$path =~ s/~/$ENV{HOME}/;
$ARGV{'ignore-missing-file'} || $path =~ /^real:/ || (-e $path && !-d _)
    or die "path $path must be a readable file, or real:..., or pass --ignore-missing-file";

my $streamable = $ARGV{streamable} ? 1 : 0;

my $library = Pi::Media::Library->new;

if (!$treeId) {
    $treeId = $library->tree_from_segments(@$segments);
}

my $checksum;
if (-e $path && !$ARGV{'defer-checksum'}) {
  require Digest::SHA;
  my $sha = Digest::SHA->new(1);
  $sha->addfile($path);
  $checksum = lc($sha->hexdigest);
}

my $spoken_langs;
if (exists $ARGV{spoken_langs}) {
  $spoken_langs = [map { defined($_) ? $_ : '' } split / *, */, $ARGV{spoken_langs}];
} else {
  if ($path =~ m{/Japanese/}) {
    $spoken_langs = ['ja'];
  } elsif ($path =~ m{/Chinese/}) {
    $spoken_langs = ['can'];
  } elsif ($path =~ m{/English/} || $path =~ m{/Unsorted/}) {
    $spoken_langs = ['en'];
  } else {
    $spoken_langs = ['?'];
  }
}

my $id = $library->insert_game(
    path            => $path,
    identifier      => $identifier,
    label_en        => $label_en,
    label_ja        => $label_ja,
    streamable      => $streamable,
    treeId          => $treeId,
    checksum        => $checksum,
);

if ($ARGV{'ignore-missing-file'}) {
    print "Added nonexistent " . ($label_ja || $label_en) . " as game $id\n";
}
else {
    print "Added " . ($label_ja || $label_en) . " as game $id\n";
}

sub usage {
    my $reason = shift;
    die "$reason\nusage: $0 [--treeId=treeId OR --segments=foo --segments=bar] [--label_en=LABEL --label_ja=LABEL] [--identifier=IDENTIFIER] [--ignore-missing-file] --streamable|--unstreamable PATH|real:...";
}

