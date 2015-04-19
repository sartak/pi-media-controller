#!/usr/bin/env perl
use 5.14.0;
use warnings;
use Pi::Media::Library;
use Digest::SHA;
use File::Find;
use Encode;

my $library = Pi::Media::Library->new(file => $ENV{PMC_DATABASE});

@ARGV or die "usage: $0 directories\n";

find(sub {
    return if -d $_;

    my $file = decode_utf8($File::Find::name);

    my ($media) = $library->media(path => $file);
    if (!$media) {
        warn "no media at path $file\n";
        return;
    }

    return if $file =~ /\.DS_Store/
           || $file =~ /\.state\.auto$/
           || $file =~ /\.srm$/;

    open my $handle, '<:raw', $file;

    my $sha = Digest::SHA->new(1);
    $sha->addfile($handle);
    my $got = lc($sha->hexdigest);
    my $expected = $media->checksum;

    if ($got ne $expected) {
        warn "$file\ngot      $got\nexpected $expected\n";
    }

}, @ARGV);

