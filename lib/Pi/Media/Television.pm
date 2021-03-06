package Pi::Media::Television;
use 5.14.0;
use Mouse;
use Pi::Media::Config;
use AnyEvent::Run;
use JSON::Types;
use JSON 'encode_json';
use File::Slurp 'write_file';

has notify_cb => (
    is      => 'ro',
    default => sub { sub {} },
);

has config => (
    is       => 'ro',
    isa      => 'Pi::Media::Config',
    required => 1,
);

has is_on => (
    is      => 'ro',
    writer  => '_set_is_on',
    isa     => 'Bool',
    default => 1,
    trigger => sub { shift->_write_state },
);

has file => (
    is      => 'ro',
    isa     => 'Str',
    default => 'tv.json',
);

sub notify {
    my $self = shift;
    $self->notify_cb->(@_);
}

sub _write_state {
    my $self = shift;

    my $json = encode_json($self->state);
    write_file $self->file, $json;
}

sub power_status {
    my $self = shift;
    return { type => "television/power", is_on => bool($self->is_on), @_ };
}

sub state {
    my $self = shift;
    return {
        is_on => bool($self->is_on),
    };
}

1;

