package Pi::Media::Television::WeMo;
use 5.14.0;
use Mouse;
use Power::Outlet::WeMo;
extends 'Pi::Media::Television::HDMI';

sub host {
    return shift->config->{television}{host};
}

sub is_on {
    my $self = shift;
    my $outlet = Power::Outlet::WeMo->new(host => $self->host);
    return $outlet->query =~ /on/i ? 1 : 0;
}

sub power_on {
    my $self = shift;
    my $then = shift;

    print STDERR "Turning on television ... ";
    my $outlet = Power::Outlet::WeMo->new(host => $self->host);
    if ($self->is_on) {
        print STDERR "no need.\n";
        $then->() if $then;
        return 0;
    }
    else {
        $outlet->on;
        print STDERR "ok.\n";
        $then->() if $then;
        return 1;
    }
}

sub power_off {
    my $self = shift;
    my $then = shift;

    print STDERR "Turning off television ... ";
    my $outlet = Power::Outlet::WeMo->new(host => $self->host);
    if (!$self->is_on) {
        print STDERR "no need.\n";
        $then->() if $then;
        return 0;
    }
    else {
        $outlet->off;
        print STDERR "ok.\n";
        $then->() if $then;
        return 1;
    }
}

sub set_active_source {
    my $self = shift;
    my $then = shift;

    $self->power_on;

    print STDERR "Setting self as active source for TV ... ";
    $self->_handle->push_write("as\n");
    print STDERR "ok.\n";

    $then->() if $then;
}

1;
