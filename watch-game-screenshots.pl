#!/usr/bin/env perl
use strict;
use warnings;
use utf8::all;
use Filesys::Notify::Simple;
use File::Spec;
use LWP::UserAgent;
use JSON;
use File::Slurp 'slurp';

@ARGV == 3 or die "usage: $0 [/media/trocadero] [pmc-addr] [username]";
my $drive = shift;
my $pmc_addr = shift;
my $username = shift;

my $watcher = Filesys::Notify::Simple->new(["$drive/ROM/Screenshots/"]);

my $pmc_ua = LWP::UserAgent->new;
$pmc_ua->default_header('X-PMC-Username' => $username);

my $pubsub_ua = LWP::UserAgent->new(agent => 'watch-game-screenshots');

my $json = JSON->new->utf8;

my $config = $json->decode(scalar slurp "$drive/pmc.config");
my %highest;

while (1) {
  my @new_screenshots;
  $watcher->wait(sub {
    push @new_screenshots, map { $_->{path } } @_;
  });

  my $res = $pmc_ua->get("http://$pmc_addr/current");
  if ($res->code != 200) {
    warn "Got unexpected result from PC: " . $res->status_line;
    next;
  }

  my $current = $json->decode($res->decoded_content);
  my $rom = $current->{path};
  $rom =~ m{^\Q$drive\E/?(ROM/.*)};
  my $dir = $1;
  if (!$dir) {
    warn "Could not extract directory from path $rom";
    next;
  }
  my $subdir = $config->{screenshot_subdir}{$1};
  if (!$subdir) {
    warn "No configured screenshot_subdir for $1";
    next;
  }
  my $dest = "$drive/$subdir";

  if (!exists($highest{$dest})) {
    opendir(my $handle, $dest) or die "Cannot opendir $dest: $!";
    while (my $file = readdir($handle)) {
      my ($id) = $file =~ /^(\d+)\.png$/;
      next if !$id;
      $highest{$dest} = $id if $id > ($highest{$dest} || 0);
    }
  }

  for my $file (@new_screenshots) {
    next if !-e $file; # maybe already moved
    my ($ext) = $file =~ /\.(\w+)$/;
    if (!$ext) {
      warn "Could not extract extension from $file";
      next;
    }
    my $id = 1 + $highest{$dest};
    my $d = "$dest/$id.png";
    if (-e $d) {
      warn "Could not move $file; $d already exists";
      next;
    }
    rename $file => $d;
    print "$file -> $d\n";
    ++$highest{$dest};

    my %notify_headers = (
      %{ $config->{notify_headers} || {} },
      %{ $config->{notify_headers_wgs} || {} },
    );

    $pubsub_ua->post(
      "$config->{notify_url}/screenshot",
      'Content-Type' => 'application/json',
      Content => $json->encode({
        rom => $dir,
        file => $d,
      }),
      %notify_headers,
    );
  }
} continue {
  sleep 1;
}
