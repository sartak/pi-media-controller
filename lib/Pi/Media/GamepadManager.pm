package Pi::Media::GamepadManager;
use 5.14.0;
use Mouse;
use Pi::Media::Gamepad::Wiimote;
use Pi::Media::Controller;
use Pi::Media::Config;

has config => (
    is       => 'ro',
    isa      => 'Pi::Media::Config',
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

has library => (
    is       => 'ro',
    isa      => 'Pi::Media::Library',
    required => 1,
);

has queue => (
    is       => 'ro',
    isa      => 'Pi::Media::Queue',
    required => 1,
);

has television => (
    is       => 'ro',
    isa      => 'Pi::Media::Television',
    required => 1,
);

has start_cb => (
  is  => 'ro',
  isa => 'CodeRef',
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

    my $pmc_location = $self->config->location;

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

        my $current_location = `./get-location.pl`;
        chomp $current_location;
        if ($current_location ne $pmc_location) {
            warn "Opting out of auto-wiimote connection because current location ($current_location) doesn't match ($pmc_location)\n";
            return;
        }

        for my $id ($self->_wiimote_buffer =~ m{(\w\w:\w\w:\w\w:\w\w:\w\w:\w\w)[\s\t]*Nintendo}g) {
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
                if (!$self->controller->current_media) {

                  # TODO extract current user from most recent game
                  local $main::CURRENT_USER = $self->library->login_without_password('shawn');

                  my $game = $self->library->last_game_played;
                  if ($game) {
                    my $tv_is_off = !$self->television->is_on;
                    warn "Automatically resuming most recent game\n";
                    $game->{initial_seconds} = 0;
                    $game->{audio_track} = 0;
                    $game->{save_state} = 0;
                    $game->{auto_poweroff_tv} = $tv_is_off;

                    $self->queue->push($game);

                    $self->controller->play_next_in_queue;

                    # we do this last so the game is ready by the time
                    # the tv is on
                    $self->television->set_active_source
                        if $self->television->can('set_active_source');

                    if ($self->start_cb) {
                      $self->start_cb->();
                    }

                  } else {
                    warn "But! There's no game that I can kick off\n";
                  }
                } elsif ($self->controller->current_media->type ne 'game') {
                  warn "But! We're not playing a game, so I'm turning it back off in 5...\n";
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
    $self->_disconnect_handle(undef);
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

        if ($self->_disconnect_handle) {
            warn "Started a game! Turning off delayed execution of gamepads";
        }
        else {
            warn "Started a game! But I don't think there are any gamepads yet";
        }

        $self->_disconnect_handle(undef);
    }
    elsif ($event->{type} eq 'finished') {
        return unless $event->{media}->type eq 'game';

        if ($event->{media}->{auto_poweroff_tv} && !$self->controller->current_media && !$self->queue->has_media) {
          warn "Just finished the launch game and there's nothing in the hopper; disconnecting";
          $self->television->power_off;
          $self->disconnect_all();
        } else {
          warn "Just finished a game! Disconnecting gamepads in 5...";
          $self->disconnect_all_after(5*60);
        }
    }
}

1;

