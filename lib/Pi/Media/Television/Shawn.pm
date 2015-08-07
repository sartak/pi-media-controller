package Pi::Media::Television::Shawn;
use 5.14.0;
use Mouse;
use JSON::Types;
extends 'Pi::Media::Television::WeMo';

sub minimum_volume { 0 }
sub maximum_volume { 100 }

# only allow the ones I actually use, since the TV gets grumpy
my @inputs = ("RCA", "Pi", "AppleTV");
# my @inputs = ("TV", "RCA", "Pi", "AppleTV", "USB", "Component");

my %input_index = map { $inputs[$_] => $_ } 0..$#inputs;

has muted => (
    is      => 'ro',
    writer  => '_set_muted',
    isa     => 'Bool',
    default => 0,
    trigger => sub { shift->_write_state },
);

has volume => (
    is      => 'ro',
    writer  => '_set_volume',
    isa     => 'Int',
    default => __PACKAGE__->minimum_volume,
    trigger => sub { shift->_write_state },
);

has input => (
    is      => 'ro',
    writer  => '_set_input',
    isa     => 'Str',
    default => 'Pi',
    trigger => sub { shift->_write_state },
);

sub state {
    my $self = shift;
    return {
        volume => $self->volume,
        muted  => $self->muted,
        input  => $self->input,
    };
}

sub _transmit {
    my ($self, $cmd) = @_;

    if (!$self->is_on) {
        die "refusing to transmit with the TV being off";
    }

    # try twice before reporting failure

    warn(join ' ', qw(irsend SEND_ONCE TV), $cmd);
    system(qw(irsend SEND_ONCE TV), $cmd);

    if ($?) {
        warn "trying again!";
        warn(join ' ', qw(irsend SEND_ONCE TV), $cmd);
        system(qw(irsend SEND_ONCE TV), $cmd);

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
    write_file "tv.json", $json;
}

sub notify_volume {
    my $self = shift;

    $self->notify({
        type   => "television/volume",
        volume => $self->volume,
        mute   => bool($self->muted),
        @_,
    });
}

sub mute {
    my $self = shift;
    if ($self->muted) {
        return;
    }
    $self->toggle_mute;
}

sub unmute {
    my $self = shift;
    if (!$self->muted) {
        return;
    }
    $self->toggle_mute;
}

sub toggle_mute {
    my $self = shift;

    $self->_transmit("MUTE");
    $self->_set_muted(!$self->muted);
    $self->notify_volume;
}

sub set_volume {
    my $self = shift;
    my $volume = shift;

    if ($volume < $self->minimum_volume || $volume > $self->maximum_volume) {
        die "invalid volume $volume. valid between " . $self->minimum_volume . " and " . $self->maximum_volume;
    }

    while ($self->volume < $volume) {
        $self->volume_up;
    }

    while ($self->volume > $volume) {
        $self->volume_down;
    }
}

sub volume_up {
    my $self = shift;
    return if $self->volume >= $self->maximum_volume;

    $self->_transmit("VOLUP");
    $self->_set_muted(0);
    $self->_set_volume($self->volume + 1);
    $self->notify_volume(delta => 1);
}

sub volume_down {
    my $self = shift;
    return if $self->volume <= $self->minimum_volume;

    $self->_transmit("VOLDOWN");
    $self->_set_muted(0);
    $self->_set_volume($self->volume - 1);
    $self->notify_volume(delta => -1);
}

sub set_input {
    my $self = shift;
    my $input = shift;

    die "invalid input $input. valid are: @inputs" unless exists $input_index{$input};

    return if $self->input eq $input;

    $self->_transmit("INPUT");

    my $current = $input_index{$self->input};
    my $desired = $input_index{$input};

    while ($current > $desired) {
        $self->_transmit("LEFT");
        $current--;
    }

    while ($current < $desired) {
        $self->_transmit("RIGHT");
        $current++;
    }

    $self->_transmit("OK");

    $self->_set_input($input);
    $self->notify({ type => "television/input", input => $self->input });
}

sub set_active_source {
    my $self = shift;
    my $then = shift;

    if ($self->power_on) {
        warn "waiting to set active source because we just powered on";
        sleep 15;
    }

    $self->set_input('Pi');

    $then->() if $then;
}

# cycling power disables mute
before power_off => sub {
    my $self = shift;

    if ($self->muted) {
        $self->_set_muted(0);
        $self->notify_volume;
    }
};

around power_on => sub {
    my $orig = shift;
    my $self = shift;

    my $ret = $self->$orig(@_);
    if ($ret) {
        if ($self->muted) {
            $self->_set_muted(0);
            $self->notify_volume;
        }
    }
    return $ret;
};

1;
