#!/usr/bin/env perl
use 5.14.0;
use warnings;
use lib 'lib';
use lib 'extlib';
use utf8::all;
use Pi::Media::Config;
use IPC::Run3;

my $config = Pi::Media::Config->new;

@ARGV == 1 or die "usage: $0 url\n";
my $url = shift;

my @command = ('streamlink');
push @command, ('--verbose-player', '-l', 'debug');
push @command, ('-np', 'omxplayer -b -o hdmi');

$url =~ s!^twitch[:/]!https://twitch.tv/!;
$url =~ s!^youtube[:/]!https://youtube.com/watch?v=!;

if ($url =~ m{^https?://(?:www\.)twitch\.tv/}) {
  my $auth = $config->value('twitch_oauth') or die "Need twitch_oauth\n";
  push @command, "--http-header";
  push @command, "Authorization=OAuth $auth";
}

push @command, $url;
my $quality = 'best';
my %seen = (
  # YouTube encodes these with a8
  '1440p60' => 1,
  '2160p60' => 1,
);

QUALITY: while (1) {
  die "No usable quality levels\n" unless $quality;

  $seen{$quality}++;

  my $retry = 0;

  my $handle = sub {
    my $is_err = shift;
    return sub {
      my $line = shift;
      chomp $line;

      if ($is_err) {
        warn "$line\n";
      } else {
        print "$line\n";
      }

      if ($line =~ /^\s*(?:\[[^\]]*\])*\s*Available streams: (.+)/) {
        my @qualities = map { s/\([^)]*\)//; s/^\s+//; s/\s+$//; $_ } split ',', $1;
        $quality = (grep { !$seen{$_} } @qualities)[-1];
      }

      if ($line =~ /^Vcodec id unknown:/) {
        warn "Will attempt to retry due to unusable quality level\n";
        $retry = 1;
      }
    };
  };

  warn "@command $quality\n";

  run3 [@command, $quality], \undef, $handle->(0), $handle->(1);

  last unless $retry;
}

while (`pgrep omxplayer`) {
    warn "Streamlink exited; waiting for omxplayer\n";
    sleep 1;
}

warn "Exiting from stream.pl\n";
