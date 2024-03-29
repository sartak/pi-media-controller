#!/usr/bin/env perl
use 5.14.0;
use warnings;
use Pi::Media::Library;
use File::Find;
use Encode;

my $library = Pi::Media::Library->new;
my %seen = map { $_ => 1 } $library->paths;

@ARGV or die "usage: $0 directories\n";

my @bad;
find(sub {
    return if -d $_;

    my $file = decode_utf8($File::Find::name);

    return if $file =~ /\.DS_Store/
           || $file =~ /\.state\.(auto|\d+)$/
           || $file =~ /\.srm$/
           || $file =~ /\.srm\.\d+$/
           || $file =~ /\.ips$/
           || $file =~ /\.bps$/
           || $file =~ /\.ppf$/
           || $file =~ /\.xdelta$/
           || $file =~ /\.cfg$/
           || $file =~ /\.rtc$/
           || $file =~ /\.sav$/
           || $file =~ /\.ldci$/
           || $file =~ /\/\.address$/
           || $file =~ m{PSX/.*\.bin$}
           || $file =~ m{PSX/.*\.CD\d$};

    return if $file =~ m{/ROM/[^/]+/images/};
    return if $file =~ m{/ROM/[^/]+/videos/};
    return if $file =~ m{/ROM/[^/]+/gamelist\.xml(\.old)?$};
    return if $file =~ m{/ROM/BIOS/};

    return if $seen{$file};

    push @bad, $file;
}, @ARGV);

for my $file (sort @bad) {
    warn encode_utf8($file);
}

