package Pi::Media::Television::Shawn;
use 5.14.0;
use Mouse;
extends 'Pi::Media::Television::WeMo';

sub minimum_volume { 0 }
sub maximum_volume { 100 }

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

sub state {
    my $self = shift;
    return {
        volume => $self->volume,
        muted  => $self->muted,
    };
}

sub _transmit {
    my ($self, $cmd) = @_;
    system(qw(irsend SEND_ONCE TV), $cmd);

    if ($?) {
        die "irsend failed";
    }
}

sub _write_state {
    my $self = shift;

    use JSON 'encode_json';
    use File::Slurp 'write_file';

    my $json = encode_json($self->state);
    write_file "tv.json", $json;
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
}

sub set_volume {
    my $self = shift;
    my $temp = shift;

    if ($temp < $self->minimum_volume || $temp > $self->maximum_volume) {
        die "invalid volume $temp. valid between " . $self->minimum_volume . " and " . $self->maximum_volume;
    }

    while ($self->volume < $temp) {
        $self->volume_up;
    }

    while ($self->volume > $temp) {
        $self->volume_down;
    }
}

sub volume_up {
    my $self = shift;
    return if $self->volume >= $self->maximum_volume;

    $self->_transmit("VOLUP");
    $self->_set_muted(0);
    $self->_set_volume($self->volume + 1);
}

sub volume_down {
    my $self = shift;
    return if $self->volume <= $self->minimum_volume;

    $self->_transmit("VOLDOWN");
    $self->_set_muted(0);
    $self->_set_volume($self->volume - 1);
}

1;
