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

my $ua = LWP::UserAgent->new;
$ua->default_header('X-PMC-Username' => $username);

my $json = JSON->new->utf8;

my $config = $json->decode(scalar slurp "$drive/pmc.config");
my %count;

while (1) {
  my @new_screenshots;
  $watcher->wait(sub {
    push @new_screenshots, map { $_->{path } } @_;
  });

  my $res = $ua->get("http://$pmc_addr/current");
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

  if (!exists($count{$dest})) {
    opendir(my $handle, $dest) or die "Cannot opendir $dest: $!";
    my $count = grep { !/^\./ } readdir($handle);
    $count{$dest} = $count;
  }

  for my $file (@new_screenshots) {
    next if !-e $file; # maybe already moved
    my ($ext) = $file =~ /\.(\w+)$/;
    if (!$ext) {
      warn "Could not extract extension from $file";
      next;
    }
    my $count = 1 + $count{$dest};
    my $d = "$dest/$count.png";
    if (-e $d) {
      warn "Could not move $file; $d already exists";
      next;
    }
    rename $file => $d;
    print "$file -> $d\n";
    ++$count{$dest};
  }
} continue {
  sleep 1;
}

