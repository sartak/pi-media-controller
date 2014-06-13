package Pi::Media::Library;
use 5.14.0;
use Mouse;
use Pi::Media::Video;

sub videos {
    my @videos = `find /mnt/Shawn/TV/.all/E-J /mnt/Shawn/TV/.all/Japanese/ /mnt/Shawn/Movies/.all/E-J /mnt/Shawn/Movies/.all/Japanese/ -type f | grep -v DS_Store | grep -v '/\\._'`;
    return map { Pi::Media::Video->new(path => $_, name => $_) } @videos;
}

1;

