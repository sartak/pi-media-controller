package Pi::Media::Television::WeMo;
use 5.14.0;
use Mouse;
extends 'Pi::Media::Television::HDMI';

sub host {
    return shift->config->{television}{host};
}

sub set_active_source {
    my $self = shift;
    my $then = shift;

    warn "Setting self as active source for TV ... \n";

    my $outlet = Power::Outlet::WeMo->new(host => $self->host);
    $outlet->on;

    $self->_handle->push_write("as\n");

    $then->() if $then;
}

sub power_off {
    my $self = shift;
    my $then = shift;

    my $outlet = Power::Outlet::WeMo->new(host => $self->host);
    $outlet->off;

    $then->() if $then;
}

1;
