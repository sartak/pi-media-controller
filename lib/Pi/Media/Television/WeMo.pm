package Pi::Media::Television::WeMo;
use 5.14.0;
use Mouse;
use Power::Outlet::WeMo;
extends 'Pi::Media::Television::HDMI';

sub host {
    return shift->config->{television}{host};
}

sub set_active_source {
    my $self = shift;
    my $then = shift;

    print STDERR "Turning on television ... ";
    my $outlet = Power::Outlet::WeMo->new(host => $self->host);
    $outlet->on;
    print STDERR "ok.\n";

    print STDERR "Setting self as active source for TV ... ";
    $self->_handle->push_write("as\n");
    print STDERR "ok.\n";

    $then->() if $then;
}

sub power_off {
    my $self = shift;
    my $then = shift;

    print STDERR "Turning on television ... ";
    my $outlet = Power::Outlet::WeMo->new(host => $self->host);
    $outlet->off;
    print STDERR "ok.\n";

    $then->() if $then;
}

1;
