package Pi::Media::Television::WeMo;
use 5.14.0;
use Mouse;
use Power::Outlet::WeMo;
use JSON::Types;
extends 'Pi::Media::Television';

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

    print STDERR "Turning on television ... ";
    my $outlet = Power::Outlet::WeMo->new(host => $self->host);
    if ($self->is_on) {
        print STDERR "no need.\n";
        return 0;
    }
    else {
        $outlet->on;
        print STDERR "ok.\n";
        $self->notify($self->power_status);
        return 1;
    }
}

sub power_off {
    my $self = shift;

    print STDERR "Turning off television ... ";
    my $outlet = Power::Outlet::WeMo->new(host => $self->host);
    if (!$self->is_on) {
        print STDERR "no need.\n";
        return 0;
    }
    else {
        $outlet->off;
        print STDERR "ok.\n";
        $self->notify($self->power_status);
        return 1;
    }
}

sub set_active_source {
    my $self = shift;

    $self->power_on;
}

1;
