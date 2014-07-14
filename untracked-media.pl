#!/usr/bin/env perl
use 5.14.0;
use warnings;
use utf8::all;
use Pi::Media::Library;
use Path::Class 'file';
use File::Find;

my $library = Pi::Media::Library->new(file => $ENV{PMC_DATABASE});
my %seen = map { $_ => 1 } $library->paths;

@ARGV or die "usage: $0 directories\n";

find(sub {
    return if -d $_;

    my $file = $File::Find::name;
    return if $file =~ /\.DS_Store/;
    return if $seen{$file};

    warn $file;
}, @ARGV);
