#!/usr/bin/env perl
use 5.14.0;
use warnings;
use utf8::all;
use Getopt::Whatever;
use Pi::Media::Library;

my $library = Pi::Media::Library->new(file => $ENV{PMC_DATABASE});
$library->begin;

my @media = $library->media(treeId => 1);

my %fixup = (
    'Airplane II: The Sequel' => 'Airplane! 2',

    'Batman Begins'           => 'Batman Nolan 1',
    'The Dark Knight'         => 'Batman Nolan 2',
    'The Dark Knight Rises'   => 'Batman Nolan 3',

    "Bill & Ted's Excellent Adventure" => 'Bill & Ted 1',
    "Bill & Ted's Bogus Journey"       => 'Bill & Ted 2',

    'Blade: Trinity' => 'Blade III',

    "Blade Runner (Domestic)"       => 'Blade Runner 1',
    "Blade Runner (International)"  => 'Blade Runner 2',
    "Blade Runner (Director's Cut)" => 'Blade Runner 3',

    'Escape from L.A.' => 'Escape from New York 2',

    'Live Free or Die Hard' => 'Die Hard with a Vengeance 2',

    "National Lampoon's European Vacation"  => "National Lampoon's Vacation 2",
    "National Lampoon's Christmas Vacation" => "National Lampoon's Vacation 3",
    "National Lampoon's Vegas Vacation"     => "National Lampoon's Vacation 4",

    "Ocean's Eleven"   => "Ocean's 11",
    "Ocean's Thirteen" => "Ocean's 12",
    "Ocean's Twelve"   => "Ocean's 13",

    "Rambo: First Blood" => "Rambo 1",
    "Rambo (2008)"       => "Rambo 4",

    "The Matrix"             => "Matrix 1",
    "The Matrix Reloaded"    => "Matrix 2",
    "The Matrix Revolutions" => "Matrix 3",
    "The Animatrix"          => "Matrix 4",

    "The Philosopher's Stone"    => "Harry Potter 1",
    "The Chamber of Secrets"     => "Harry Potter 2",
    "The Prisoner of Azkaban"    => "Harry Potter 3",
    "The Goblet of Fire"         => "Harry Potter 4",
    "The Order of the Phoenix"   => "Harry Potter 5",
    "The Half-Blood Prince"      => "Harry Potter 6",
    "The Deathly Hallows Part 1" => "Harry Potter 7.1",
    "The Deathly Hallows Part 2" => "Harry Potter 7.2",

    "Pitch Black"               => "Chronicles of Riddick 1",
    "The Chronicles of Riddick" => "Chronicles of Riddick 2",

    "The Fellowship of the Ring"                => "Lord of the Rings 1",
    "The Two Towers"                            => "Lord of the Rings 2",
    "The Return of the King"                    => "Lord of the Rings 3",
    "The Hobbit: An Unexpected Journey"         => "Lord of the Rings 4",
    "The Hobbit: The Desolation of Smaug"       => "Lord of the Rings 5",
    "The Hobbit: The Battle of the Five Armies" => "Lord of the Rings 6",

    "¡Three Amigos!" => "Three Amigos",

    "12 Monkeys" => "Twelve Monkeys",
);
my %saw_fixup;

@media = sort {
    my $a_label = $a->label->{en} || $a->label->{ja};
    my $b_label = $b->label->{en} || $b->label->{ja};

    if ($fixup{$a_label}) {
        $saw_fixup{$a_label}++;
        $a_label = $fixup{$a_label};
    }
    if ($fixup{$b_label}) {
        $saw_fixup{$b_label}++;
        $b_label = $fixup{$b_label};
    }

    $a_label =~ s/^The //;
    $b_label =~ s/^The //;

    $a_label =~ s/^An? //;
    $b_label =~ s/^An? //;

    $a_label cmp $b_label ||
    ($b->path =~ m{/English/} <=> $a->path =~ m{/English/}) ||
    $a->path cmp $b->path
} @media;

for my $i (1 .. $#media) {
    my $media = $media[$i];

    if (!defined($media->sort_order) || $media->sort_order != $i) {
        say(($media->sort_order // 'X') . ' -> ' . $i . ': ' . ($media->label->{en} || $media->label->{ja})) if $ARGV{verbose};

        $library->update_media($media, sort_order => $i);
    }
    else {
        say $i . ': ' . ($media->label->{en} || $media->label->{ja}) if $ARGV{verbose};
    }
}

for my $key (keys %fixup) {
    if (!$saw_fixup{$key}) {
        warn "Unused fixup: $key\n";
    }
}

$library->commit;
