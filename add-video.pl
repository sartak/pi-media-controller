#!/usr/bin/env perl
use 5.14.0;
use warnings;
use utf8::all;
use Getopt::Whatever;
use Pi::Media::Library;

for my $key (keys %ARGV) {
    next if $key eq 'segments' || $key eq 'tag';
    die "Argument $key repeated. Accident?" if ref $ARGV{$key} eq 'ARRAY';
}

die "--tag not --tags" if $ARGV{tags};

my $treeId = $ARGV{treeId};
my $segments = ref $ARGV{segments} ? $ARGV{segments} : [$ARGV{segments}];

my $tags = ref $ARGV{tag} ? $ARGV{tag} : $ARGV{tag} ? [$ARGV{tag}] : undef;

$treeId || $ARGV{segments} or usage("treeId or segments required");

my $identifier = $ARGV{identifier};
warn "identifier probably shouldn't start with 0\n"
	if $identifier && $identifier =~ /^0\d/;

my $sort_order = $ARGV{sort_order};

exists($ARGV{streamable}) || exists($ARGV{unstreamable}) or usage("streamable or unstreamable required");

my $label_en = $ARGV{label_en};
my $label_ja = $ARGV{label_ja};
$label_en || $label_ja or die usage("Must have at least one of label_en or label_ja");

if (exists($ARGV{viewing}) && !length($ARGV{viewing})) {
    die usage("viewing needs a device name");
}

my $path = $ARGV[0] or usage("path required");
@ARGV == 1 or usage("must have no stray args: " . join(', ', @ARGV));

$path =~ s/~/$ENV{HOME}/;
$ARGV{'ignore-missing-file'} || (-e $path && !-d _)
    or die "path $path must be a readable file, or pass --ignore-missing-file";

my $streamable = $ARGV{streamable} ? 1 : 0;

my $spoken_langs = ['??'];
if (exists $ARGV{spoken_langs}) {
    $spoken_langs = [map { defined($_) ? $_ : '' } split / *, */, $ARGV{spoken_langs}];
}

my $subtitle_langs = ['??'];
if (exists $ARGV{subtitle_langs}) {
    $subtitle_langs = [map { defined($_) ? $_ : '' } split / *, */, $ARGV{subtitle_langs}];
}

my $library = Pi::Media::Library->new;

if (!$treeId) {
    $treeId = $library->tree_from_segments(@$segments);
}

my $duration = duration_of($path);

my $id = $library->insert_video(
    path            => $path,
    identifier      => $identifier,
    label_en        => $label_en,
    label_ja        => $label_ja,
    spoken_langs    => $spoken_langs,
    subtitle_langs  => $subtitle_langs,
    streamable      => $streamable,
    durationSeconds => $duration,
    treeId          => $treeId,
    tags            => $tags,
    sort_order      => $sort_order,
);

if ($ARGV{'ignore-missing-file'}) {
    print "Added nonexistent " . ($label_ja || $label_en) . " as video $id\n";
}
else {
    print "Added " . ($label_ja || $label_en) . " as video $id\n";
}

if ($ARGV{'viewing'}) {
    my $viewing = $library->add_viewing(
        media_id => $id,
        start_time => undef,
        end_time => undef,
        initial_seconds => 0,
        elapsed_seconds => $duration,
        completed => 1,
        location => $ARGV{'viewing'},
        who => 'shawn',
    );
    print "Added viewing on device '$ARGV{viewing}' $viewing\n";
}

sub usage {
    my $reason = shift;
    die "$reason\nusage: $0 [--treeId=treeId OR --segments=foo --segments=bar] [--label_en=LABEL --label_ja=LABEL] [--identifier=IDENTIFIER] [--ignore-missing-file] --streamable|--unstreamable [--tag=TAG] PATH";
}

sub duration_of {
    my $path = shift;
    if ($ARGV{'ignore-missing-file'}) {
        return undef;
    }

    my $secs;
    if ($path =~ /\.(mp4|m4v)$/) {
        require MP4::Info;
        my $info = MP4::Info::get_mp4info($path);
        $secs = $info->{SECS};
        if (!$secs && ($info->{MM} || $info->{SS})) {
            $secs = $info->{MM} * 60 + $info->{SS};
        }
    }
    elsif ($path =~ /\.(mkv|avi)$/) {
        require Image::ExifTool;
        my $info = Image::ExifTool::ImageInfo($path);
        if (my ($h, $m, $s) = $info->{Duration} =~ /^(\d+):(\d+):(\d+)$/) {
            $secs = $h * 3600 + $m * 60 + $s;
        }

        if (my ($s) = $info->{Duration} =~ /^(\d+)(?:\.\d*)? s$/) {
            $secs = $s;
        }
    }
    else {
        die "Unable to intuit duration of file type $path\n";
    }

    if (!$secs) {
        die "Unable to intuit duration of $path\n";
    }

    return $secs;
}

