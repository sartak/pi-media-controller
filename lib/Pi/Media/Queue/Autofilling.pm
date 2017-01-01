package Pi::Media::Queue::Autofilling;
use 5.14.0;
use Mouse;
use Pi::Media::User;
extends 'Pi::Media::Queue';

has source => (
    is      => 'rw',
    isa     => 'Pi::Media::Tree',
    clearer => 'clear_autofill_source',
);

has requestor => (
    is      => 'rw',
    isa     => 'Pi::Media::User',
    clearer => 'clear_requestor',
);

sub shift {
    my $self = CORE::shift(@_);

    if (!$self->SUPER::has_media(@_) && $self->source) {
        $self->notify({ type => 'queue', autofill => 1 });

        my $tree = $self->source;
        my @media;
        if ($tree->has_clause) {
            @media = $self->library->media(
                all         => 1,
                joins       => $tree->join_clause,
                where       => $tree->where_clause,
                order       => $tree->order_clause,
                limit       => $tree->limit_clause,
                source_tree => $tree->id,
            );
        }
        else {
            @media = $self->library->media(treeId => $tree->id);
        }

        local $main::CURRENT_USER = $self->requestor;
        $self->push(@media);

        $self->clear_autofill_source;
        $self->clear_requestor;
    }

    return $self->SUPER::shift(@_);
}

sub has_media {
    my $self = CORE::shift(@_);

    if ($self->source) {
        return 1;
    }
    else {
        return $self->SUPER::has_media(@_);
    }
}

1;

