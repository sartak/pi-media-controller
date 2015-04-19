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

    my ($media) = $library->media(
        all  => 1,
        path => $library->_relativify_path($file),
    );

    return if $file =~ /\.DS_Store/
           || $file =~ /\.state\.auto$/
           || $file =~ /\.srm$/;

    print STDERR encode_utf8 "$file ... ";
    if (!$media) {
        print STDERR encode_utf8 "no media\n";
        return;
    }

    open my $handle, '<:raw', $file;

    my $sha = Digest::SHA->new(1);
    $sha->addfile($handle);
    my $got = lc($sha->hexdigest);
    my $expected = $media->checksum;

    if ($got ne $expected) {
        print STDERR encode_utf8 "checksum mismatch\ngot      $got\nexpected $expected\n";

        my ($match) = $library->media(
            all      => 1,
            checksum => $got,
        );

        if ($match) {
            print STDERR encode_utf8("you know, " . $match->path . " has that checksum!\n");
        }
    }
    else {
        print STDERR encode_utf8 "ok\n";
    }

}, @ARGV);

