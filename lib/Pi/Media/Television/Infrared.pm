package Pi::Media::Television::Infrared;
use 5.14.0;
use Mouse;
use JSON::Types;
extends 'Pi::Media::Television';

sub minimum_volume { 0 }
sub maximum_volume { 100 }

# only allow the ones I actually use, since the TV gets grumpy if I select
# an unconnected input
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

around state => sub {
    my $orig = shift;
    my $self = shift;
    my $state = $self->$orig(@_);
    return {
        %$state,
        volume => $self->volume,
        muted  => bool($self->muted),
        input  => $self->input,
    };
};

sub _transmit {
    my ($self, $cmd) = @_;

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

sub volume_status {
    my $self = shift;
    return {
        type   => "television/volume",
        volume => $self->volume,
        mute   => bool($self->muted),
        @_,
    };
}

sub notify_volume {
    my $self = shift;
    $self->notify($self->volume_status(@_));
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

    die "tv isn't on" if !$self->is_on;

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

    # turning volume up or down will unmute, but if there's a request to set
    # volume to current, we should helpfully unmute
    if ($self->volume == $volume) {
       $self->unmute;
    }

    while ($self->volume < $volume) {
        $self->volume_up(target => $volume);
    }

    while ($self->volume > $volume) {
        $self->volume_down(target => $volume);
    }
}

sub volume_up {
    my $self = shift;

    return if $self->volume >= $self->maximum_volume;

    die "tv isn't on" if !$self->is_on;

    $self->_transmit("VOLUP");
    $self->_set_muted(0);
    $self->_set_volume($self->volume + 1);
    $self->notify_volume(delta => 1, @_);
}

sub volume_down {
    my $self = shift;

    return if $self->volume <= $self->minimum_volume;

    die "tv isn't on" if !$self->is_on;

    $self->_transmit("VOLDOWN");
    $self->_set_muted(0);
    $self->_set_volume($self->volume - 1);
    $self->notify_volume(delta => -1, @_);
}

sub input_status {
    my $self = shift;
    return { type => "television/input", input => $self->input, @_ };
}

sub set_input {
    my $self = shift;
    my $input = shift;

    die "invalid input $input. valid are: @inputs" unless exists $input_index{$input};

    return if $self->input eq $input;

    die "tv isn't on" if !$self->is_on;

    $self->notify($self->input_status(input => $input, prospective => 1));

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
    $self->notify($self->input_status);
}

sub set_active_source {
    my $self = shift;

    if ($self->power_on) {
        warn "waiting to set active source because we just powered on";
        sleep 15;
    }

    $self->set_input('Pi');
}

sub power_off {
    my $self = shift;

    return 0 unless $self->is_on;

    if ($self->muted) {
        $self->_set_muted(0);
        $self->notify_volume;
    }

    $self->_transmit("POWER");
    $self->_set_is_on(0);
    $self->notify($self->power_status);
    return 1;
}

sub power_on {
    my $self = shift;

    return 0 if $self->is_on;

    if ($self->muted) {
        $self->_set_muted(0);
        $self->notify_volume;
    }

    $self->_transmit("POWER");
    $self->_set_is_on(1);
    $self->notify($self->power_status);
    return 1;
}

1;
