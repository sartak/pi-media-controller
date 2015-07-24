package Pi::Media::AC;
use 5.14.0;
use Mouse;

sub minimum_temperature { 60 }
sub maximum_temperature { 86 }
my @modes = ("Cool", "Energy Saver", "Fan");
my @fanspeeds = (1, 2, 3);

my %mode_index = map { $modes[$_] => $_ } 0..$#modes;
my %fanspeed_index = map { $fanspeeds[$_] => $_ } 0..$#fanspeeds;

has is_on => (
    is      => 'ro',
    writer  => '_set_is_on',
    isa     => 'Bool',
    default => 0,
    trigger => sub { shift->_write_state },
);

has temperature => (
    is      => 'ro',
    writer  => '_set_temperature',
    isa     => 'Int',
    default => __PACKAGE__->minimum_temperature,
    trigger => sub { shift->_write_state },
);

has mode => (
    is      => 'ro',
    writer  => '_set_mode',
    isa     => 'Str',
    default => $modes[0],
    trigger => sub { shift->_write_state },
);

has fanspeed => (
    is      => 'ro',
    writer  => '_set_fanspeed',
    isa     => 'Int',
    default => $fanspeeds[-1],
    trigger => sub { shift->_write_state },
);

sub state {
    my $self = shift;
    return {
        is_on       => $self->is_on,
        temperature => $self->temperature,
        mode        => $self->mode,
        fanspeed    => $self->fanspeed,
    };
}

sub _transmit {
    my ($self, $cmd) = @_;

    # try twice before reporting failure

    warn(join ' ', qw(irsend SEND_ONCE AC), $cmd);
    system(qw(irsend SEND_ONCE AC), $cmd);

    if ($?) {
        warn "trying again!";
        warn(join ' ', qw(irsend SEND_ONCE AC), $cmd);
        system(qw(irsend SEND_ONCE AC), $cmd);

        if ($?) {
            die "irsend failed";
        }
    }
}

sub _write_state {
    my $self = shift;

    use JSON 'encode_json';
    use File::Slurp 'write_file';

    my $json = encode_json($self->state);
    write_file "ac.json", $json;
}

sub power_on {
    my $self = shift;
    if ($self->is_on) {
        return;
    }
    $self->toggle_power;
}

sub power_off {
    my $self = shift;
    if (!$self->is_on) {
        return;
    }
    $self->toggle_power;
}

sub toggle_power {
    my $self = shift;

    $self->_transmit("POWER");
    $self->_set_is_on(!$self->is_on);
}

sub set_temperature {
    my $self = shift;
    my $temp = shift;

    if ($temp < $self->minimum_temperature || $temp > $self->maximum_temperature) {
        die "invalid temperature $temp. valid between " . $self->minimum_temperature . " and " . $self->maximum_temperature;
    }

    while ($self->temperature < $temp) {
        $self->temperature_up;
    }

    while ($self->temperature > $temp) {
        $self->temperature_down;
    }
}

sub temperature_up {
    my $self = shift;
    return if $self->temperature >= $self->maximum_temperature;

    $self->_transmit("UP");
    $self->_set_temperature($self->temperature + 1);
}

sub temperature_down {
    my $self = shift;
    return if $self->temperature <= $self->minimum_temperature;

    $self->_transmit("DOWN");
    $self->_set_temperature($self->temperature - 1);
}

sub set_mode {
    my $self = shift;
    my $mode = shift;

    die "invalid mode $mode. valid are: @modes" unless exists $mode_index{$mode};

    until ($self->mode eq $mode) {
        $self->toggle_mode;
    }
}

sub toggle_mode {
    my $self = shift;
    my $index = $mode_index{ $self->mode };
    $index = ($index + 1) % @modes;

    $self->_transmit("MODE");
    $self->_set_mode($modes[$index]);
}

sub set_fanspeed {
    my $self = shift;
    my $fanspeed = shift;

    die "invalid fanspeed $fanspeed. valid are: @modes" unless grep { $_ eq $fanspeed } @fanspeeds;

    until ($self->fanspeed eq $fanspeed) {
        $self->toggle_fanspeed;
    }
}

sub toggle_fanspeed {
    my $self = shift;
    my $index = $fanspeed_index{ $self->fanspeed };
    $index = ($index + 1) % @fanspeeds;

    $self->_transmit("FAN");
    $self->_set_fanspeed($fanspeeds[$index]);
}

1;

