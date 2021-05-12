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

my @dirs = do {
  my @d;
  my $dir = "$drive/ROM/Screenshots/";
  opendir(my $handle, $dir) or die $!;
  while ($_ = readdir($handle)) {
    next if /^\.+$/;
    my $path = "$dir$_";
    next unless -d $path;
    push @d, $path;
  }
  @d
};

my $watcher = Filesys::Notify::Simple->new(\@dirs);

my $pmc_ua = LWP::UserAgent->new;

my $pubsub_ua = LWP::UserAgent->new(agent => 'watch-game-screenshots');

my $json = JSON->new->utf8;

my $config = $json->decode(scalar slurp "$drive/pmc.config");
my %highest;
my %pmc_addr_for_hostname;

while (1) {
  my $hupped = 0;

  $SIG{HUP} = sub {
    warn "Got SIGHUP; clearing fs cache…\n";
    %highest = ();
    $hupped++;
  };

  my @new_screenshots;
  $watcher->wait(sub {
    push @new_screenshots, map { $_->{path } } @_;
  });

  next if $hupped && !@new_screenshots;

  my %dest_for_hostname;

  my $time = time;

  for my $file (@new_screenshots) {
    next if !-e $file; # maybe already moved

    my ($hostname, $ext) = $file =~ m{/([^/]+)/[^/]+\.(\w+)$};
    if (!$hostname || !$ext) {
      warn "Could not extract hostname and extension from $file";
      next;
    }

    if (!$dest_for_hostname{$hostname}) {
      my ($pmc_addr, $pmc_user, $pmc_pass) = @{ $pmc_addr_for_hostname{$hostname} ||= do {
        my $addr_file = $file;
        $file =~ s{/[^/]+\.\w+$}{/.address};
        [split "\n", scalar slurp $file];
      } };

      my $res = $pmc_ua->get(
        "$pmc_addr/current",
	'X-PMC-Username' => $pmc_user,
	'X-PMC-Password' => $pmc_pass,
      );

      if ($res->code != 200) {
        warn "Got unexpected result from $pmc_addr " . $res->status_line;
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
          my ($id) = $file =~ /^(\d+)\.\w+$/;
          next if !$id;
          $highest{$dest} = $id if $id > ($highest{$dest} || 0);
        }
      }

      $dest_for_hostname{$hostname} = $dest;
    }

    my $dest = $dest_for_hostname{$hostname};

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
    $path =~ s!^\Q$drive\E/$directory!!;

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
