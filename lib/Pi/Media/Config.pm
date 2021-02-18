package Pi::Media::Config;
use utf8;
use 5.14.0;
use Mouse;
use JSON;
use File::Slurp 'slurp';

has file => (
  is      => 'ro',
  isa     => 'Str',
  default => 'config.json',
);

has location => (
  is      => 'ro',
  isa     => 'Str',
  default => $ENV{PMC_LOCATION},
);

has hostname => (
  is => 'ro',
  isa => 'Str',
  lazy => 1,
  default => sub {
    my $hostname = `hostname`;
    chomp $hostname;
    return $hostname;
  },
);

has config => (
  is => 'ro',
  isa => 'HashRef',
  lazy => 1,
  default => sub {
    my $self = shift;
    my $file = $self->file;
    my $location = $self->location;
    my $json = JSON->new->utf8;

    my $config = $json->decode(scalar slurp $file);

    $config->{location} = $location if $location;

    if ($config->{by_location}) {
        %$config = (
            %$config,
            %{ $config->{by_location}{$config->{location}} || {} },
        );
    }

    return $config;
  },
);

sub BUILD {
  my $self = shift;
  my $file = $self->file;

  die "Missing config file: " . $file unless -e $file;
}

sub value {
  return $_[0]->config->{$_[1]};
}

1;

