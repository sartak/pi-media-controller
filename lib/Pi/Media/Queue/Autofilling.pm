package Pi::Media::Queue::Autofilling;
use 5.14.0;
use Mouse;
use Pi::Media::User;
use List::Util 'shuffle';
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
                group       => $tree->group_clause,
                order       => $tree->order_clause,
                limit       => $tree->limit_clause,
                source_tree => $tree->id,
            );
        }
        else {
            @media = $self->library->media(treeId => $tree->id);
        }

        if (my $language = $tree->default_language) {
          my $alt = $language eq 'ja' ? '?/jpn'
                  : $language eq 'can' ? '?/zho'
                  : $language eq 'en' ? '?/eng'
                  : '';

          MEDIA: for my $media (@media) {
            my $tracks = $media->{spoken_langs};
            for my $l (grep { length } $language, $alt) {
              for my $i (0 .. @$tracks - 1) {
                if ($l eq $tracks->[$i]) {
                  $media->{audio_track} = $i;
                  next MEDIA;
                }
              }
            }
          }
        }

        local $main::CURRENT_USER = $self->requestor;
        $self->push(shuffle @media);

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

