#!/usr/bin/env perl
use 5.14.0;
use warnings;
use Pi::Media::Library;
use File::Find;
use Encode;

my $library = Pi::Media::Library->new(file => $ENV{PMC_DATABASE});
my %seen = map { $_ => 1 } $library->paths;

@ARGV or die "usage: $0 directories\n";

my @bad;
find(sub {
    return if -d $_;

    my $file = decode_utf8($File::Find::name);

    return if $file =~ /\.DS_Store/
           || $file =~ /\.state\.(auto|\d+)$/
           || $file =~ /\.srm$/
           || $file =~ /\.cfg$/
           || $file =~ /\.sav$/;

    return if $seen{$file};

    push @bad, $file;
}, @ARGV);

for my $file (sort @bad) {
    warn encode_utf8($file);
}

