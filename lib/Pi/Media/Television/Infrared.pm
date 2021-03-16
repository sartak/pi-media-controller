package Pi::Media::Television::Infrared;
use 5.14.0;
use Mouse;
use JSON::Types;
extends 'Pi::Media::Television';

has infrared_name => (
    is      => 'ro',
    isa     => 'Str',
    default => 'TV',
);

has minimum_volume => (
    is      => 'ro',
    isa     => 'Int',
    default => 0,
);

has maximum_volume => (
    is      => 'ro',
    isa     => 'Int',
    default => 100,
);

has inputs => (
    is      => 'ro',
    isa     => 'ArrayRef[Str|HashRef]',
    default => sub { ['Pi'] },
);

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
    my $self = shift;
    my $cmd  = shift;
    my $name = shift || $self->infrared_name;

    # try twice before reporting failure

    warn(join ' ', 'irsend', 'SEND_ONCE', $name, $cmd);
    eval {
        local $SIG{ALRM} = sub { die "alarm\n" };
	alarm 2;
        system('irsend', 'SEND_ONCE', $name, $cmd);
	alarm 0;
    };

    if ($@) {
        return if $@ eq "alarm\n";
	warn $@;
    } elsif (!$?) {
        return;
    }

    warn "trying again!";
    warn(join ' ', 'irsend', 'SEND_ONCE', $name, $cmd);

    eval {
        local $SIG{ALRM} = sub { die "alarm\n" };
	alarm 2;
        system('irsend', 'SEND_ONCE', $name, $cmd);
	alarm 0;
    };

    if ($@) {
        return if $@ eq "alarm\n";
	warn $@;
    }
    elsif ($?) {
        die "irsend failed";
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

sub _set_input_infrared {
    my $self = shift;
    my $current = shift;
    my $desired = shift;

    $self->_transmit("INPUT");

    while ($current > $desired) {
        $self->_transmit("LEFT");
        $current--;
    }

    while ($current < $desired) {
        $self->_transmit("RIGHT");
        $current++;
    }

    $self->_transmit("OK");
}

sub _set_input_techole {
    my $self = shift;
    my $desired = 1 + shift; # 0 index

    $self->_transmit("CHANNEL$desired", "TECHOLE");
}

sub _find_input {
    my $self = shift;
    my $name = shift;

    my $inputs = $self->inputs;

    for my $i (0..$#$inputs) {
        my $spec = $inputs->[$i];

        if (ref($spec) eq 'HASH') {
            my ($type) = keys %$spec;
            my $subspecs = $spec->{$type};
            for my $j (0..$#$subspecs) {
                if ($subspecs->[$j] eq $name) {
                    return ($i, $type, $j);
                }
            }
        } elsif ($spec eq $name) {
            return ($i);
        }
    }

    return;
}

sub set_input {
    my $self = shift;
    my $desired = shift;
    my $current = $self->input;

    return if $desired eq $current;

    my ($from_infrared_index, $from_subtype, $from_subindex) = $self->_find_input($current);
    my ($to_infrared_index, $to_subtype, $to_subindex) = $self->_find_input($desired);

    die "invalid input $desired" unless defined $to_infrared_index;

    die "tv isn't on" if !$self->is_on;

    $self->notify($self->input_status(input => $desired, prospective => 1));

    if ($from_infrared_index != $to_infrared_index) {
      $self->_set_input_infrared($from_infrared_index, $to_infrared_index);
    }

    if (($to_subtype || '') eq 'Techole') {
      $self->_set_input_techole($to_subindex);
    }

    $self->_set_input($desired);
    $self->notify($self->input_status);
}

sub set_active_source {
    my $self = shift;

    if ($self->power_on) {
        warn "waiting to set active source because we just powered on";
        sleep 10;
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
