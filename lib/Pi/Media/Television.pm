package Pi::Media::Television;
use 5.14.0;
use Mouse;
use AnyEvent::Run;

has config => (
    is       => 'ro',
    isa      => 'HashRef',
    required => 1,
);

has _handle => (
    is      => 'rw',
    clearer => '_clear_handle',
    lazy    => 1,
    builder => sub {
        my $self = shift;

        my $handle = AnyEvent::Run->new(cmd => "cec-client");
        $handle->on_read(sub {});
        $handle->on_eof(undef);
        $handle->on_error(sub {
            $self->_clear_handle;
            undef $handle;
        });

        return $handle;
    },
);

sub set_active_source {
    my $self = shift;
    my $then = shift;

    print STDERR "Setting self as active source for TV ... ";
    $self->_handle->push_write("on\n");
    $self->_handle->push_write("as\n");
    print STDERR "ok.\n";

    $then->() if $then;
}

sub power_off {
    my $self = shift;
    my $then = shift;

    $then->() if $then;
}

1;

