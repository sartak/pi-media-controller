package Pi::Media::GamepadManager;
use 5.14.0;
use Mouse;
use Pi::Media::Gamepad::Wiimote;
use Pi::Media::Controller;

has config => (
    is       => 'ro',
    isa      => 'HashRef',
    required => 1,
);

has gamepads => (
    is      => 'ro',
    isa     => 'ArrayRef[Pi::Media::Gamepad]',
    default => sub { [] },
);

has controller => (
    is       => 'ro',
    isa      => 'Pi::Media::Controller',
    required => 1,
);

has _wiimote_handle => (
    is      => 'rw',
    clearer => '_clear_wiimote_handle',
);

has _wiimote_buffer => (
    is      => 'rw',
    isa     => 'Str',
    default => '',
);

has _disconnect_handle => (
    is      => 'rw',
    clearer => '_clear_disconnect_handle',
);

sub scan {
    my $self = shift;
    $self->scan_wiimote;
}

sub scan_wiimote {
    my $self = shift;

    $self->_wiimote_buffer('');

    my $handle = AnyEvent::Run->new(
        cmd => ['hcitool', 'scan'],
    );

    $self->_wiimote_handle($handle);

    $handle->on_read(sub {
        my ($handle) = @_;
        my $buf = $handle->{rbuf};
        $handle->{rbuf} = '';

        $self->_wiimote_buffer($self->_wiimote_buffer . $buf);
    });

    $handle->on_eof(undef);

    $handle->on_error(sub {
        undef $handle;
        $self->_wiimote_handle(undef);

        for my $id ($self->_wiimote_buffer =~ m{(\w\w:\w\w:\w\w:\w\w:\w\w:\w\w)}g) {
            if (!$self->gamepad_with_id($id)) {
                my $gamepad = Pi::Media::Gamepad::Wiimote->new(
                    config  => $self->config,
                    led     => (1 + @{ $self->gamepads }),
                    id      => $id,
                    manager => $self,
                );

                $gamepad->scan;

                push @{ $self->gamepads }, $gamepad;

                # if there's no game, ok, but turn off wiimote in 5 minutes
                if (!$self->controller->current_media || $self->controller->current_media->type ne 'game') {
                    warn "But! there's no game, so I'm turning it back off in 5...";
                    $self->disconnect_all_after(5*60);
                }
            }
        }

        # take a breather
        sleep 1;

        # immediately start scanning again
        $self->scan_wiimote;
    });
}

sub gamepad_with_id {
    my $self = shift;
    my $id   = shift;

    for my $gamepad (@{ $self->gamepads }) {
        if ($gamepad->id eq $id) {
            return $gamepad;
        }
    }

    return 0;
}

sub disconnect_all {
    my $self = shift;

    warn "Disconnecting all gamepads";

    for my $gamepad (@{ $self->gamepads }) {
        $gamepad->disconnect;
    }

    @{ $self->gamepads } = ();
}

sub remove_gamepad {
    my $self = shift;
    my $pad  = shift;

    warn "Removing gamepad " . $pad->led . " " . $pad->id;
    @{ $self->gamepads } = grep { $_ != $pad } @{ $self->gamepads };
}

sub disconnect_all_after {
    my $self = shift;
    my $secs = shift;

    my $handle = AnyEvent->timer(after => $secs, cb => sub {
        $self->_disconnect_handle(undef);

        $self->disconnect_all;
    });
    $self->_disconnect_handle($handle);
}

sub got_event {
    my $self  = shift;
    my $event = shift;

    if ($event->{type} eq 'started') {
        return unless $event->{media}->type eq 'game';
        $self->_disconnect_handle(undef);

        warn "Started a game! Turning off delayed execution of gamepads";
    }
    elsif ($event->{type} eq 'finished') {
        return unless $event->{media}->type eq 'game';

        warn "Just finished a game! Disconnecting gamepads in 5...";
        $self->disconnect_all_after(5*60);
    }
}

1;

