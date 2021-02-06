#!/usr/bin/env perl
use 5.14.0;
use warnings;
use utf8::all;
use JSON ();
use LWP::UserAgent;
use File::Slurp 'slurp';

my $JSON = JSON->new->utf8->convert_blessed->allow_blessed;
my $config = $JSON->decode(scalar slurp "config.json");

my $ua = LWP::UserAgent->new;
my $res = $ua->get($config->{get_presence_url});
die $res->status_line if !$res->is_success;

my $distances = $JSON->decode($res->decoded_content)->{content};
my $closest;

for my $room (keys %$distances) {
  $closest = $room if !$closest || $distances->{$room}{distance} < $distances->{$closest}{distance};
}
die "No distances" if !$closest;

print "$closest\n";
