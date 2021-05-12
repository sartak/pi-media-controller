#!/usr/bin/env perl
use strict;
use warnings;
use utf8::all;
use Filesys::Notify::Simple;
use File::Spec;
use LWP::UserAgent;
use JSON;
use File::Slurp 'slurp';
use HTTP::Date;
use Digest::SHA;

@ARGV == 2 or die "usage: $0 /media/trocadero Pictures/study";
my $drive = shift;

my $directory = shift;
$directory =~ s!/+!/!g;
$directory =~ s!^/!!;
$directory =~ s!/$!!;

my $watcher = Filesys::Notify::Simple->new(["$drive/tmp/snagit/"]);

my $pubsub_ua = LWP::UserAgent->new(agent => 'watch-snagit-screenshots');

my $json = JSON->new->utf8;

my $config = $json->decode(scalar slurp "$drive/pmc.config");
my %highest;

my $intake_ua = LWP::UserAgent->new;
my %headers = %{ $config->{snagit_playing_headers} };
for my $key (keys %headers) {
  $intake_ua->default_header($key => $headers{$key});
}

my %seen;

while (1) {
  my $hupped = 0;

  $SIG{HUP} = sub {
    warn "Got SIGHUP; clearing fs cache…\n";
    %highest = ();
    %seen = ();
    $hupped++;
  };

  my @new_screenshots;
  $watcher->wait(sub {
    push @new_screenshots, map { $_->{path } } @_;
  });

  @new_screenshots = grep { !$seen{$_}++ } @new_screenshots;

  next if $hupped && !@new_screenshots;

  # let file finish transferring
  sleep 2;

  my $res = $intake_ua->get($config->{snagit_playing_url});
  if ($res->code != 200) {
    warn "Got unexpected result from PC: " . $res->status_line;
    next;
  }

  my $current = $json->decode($res->decoded_content);
  if (ref($current) ne 'ARRAY' && @$current != 1) {
    warn "Did not get an array of one result back from intake, got $current";
    next;
  }
  ($current) = @$current;

  my $subdir = $config->{snagit_subdir}{$current->{game}};
  if (!$subdir) {
    warn "No configured snagit_subdir for $current->{game}";
    next;
  }
  my $dest = "$drive/$subdir";

  if (!exists($highest{$dest})) {
    opendir(my $handle, $dest) or die "Cannot opendir $dest: $!";
    while (my $file = readdir($handle)) {
      my ($id) = $file =~ /^(\d+)\.\w+$/;
      next if !$id;
      $highest{$dest} = $id if $id > ($highest{$dest} || 0);
    }
  }

  my $time = time;

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
    system("cp", $file => $d);
    print "$file -> $d\n";
    ++$highest{$dest};

    my %notify_headers = (
      %{ $config->{notify_headers} || {} },
      %{ $config->{notify_headers_wgs} || {} },
    );

    my ($width, $height);
    while (1) {
      my $info = `file $d`;
      if ($info =~ /: empty$/) {
        warn "Sleeping because $d still appears empty…\n";
        sleep 1;
        next;
      }
      ($width, $height) = $info =~ /, (\d+) ?x ?(\d+), /;
      warn "Unable to parse: $info" unless $width && $height;
      last;
    }

    my $sha = Digest::SHA->new(1);
    $sha->addfile($d);
    my $digest = $sha->hexdigest;

    utime $time, $time, "$dest/.time";

    my $path = $d;
    $path =~ s!^\Q$drive\E/\Q$directory\E!!;

    $pubsub_ua->post(
      "$config->{notify_url}/screenshot",
      'Content-Type' => 'application/json',
      Content => $json->encode({
        file => $d,
        path => $path,
        last_modified => time2str($time),
        digest => $digest,
        width => $width,
        height => $height,
      }),
      %notify_headers,
    );
  }

  utime $time, $time, "$drive/$directory/.time";
}
