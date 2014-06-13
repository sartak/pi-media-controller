#!/usr/bin/env perl
use 5.14.0;
use warnings;
use utf8::all;
use Pi::Media::Library;
use File::Next;
use Path::Class 'file';

my $library = Pi::Media::Library->new;
my %seen = map { $_ => 1 } $library->paths;
my $iterator = File::Next::files(@ARGV ? @ARGV : '.');
while (defined(my $file = $iterator->())) {
    next if $file =~ /\.DS_Store/;

    my $full = file($file)->absolute;
    next if $seen{$full};
    warn "$full\n";
}
