#!/bin/bash
cd ~/pi-media-controller/

export PMC_LOCATION=Office

perl -Ilib -Iextlib untracked-media.pl /media/trocadero/Commercials /media/trocadero/LP /media/trocadero/Movies /media/trocadero/ROM/*/ /media/trocadero/Shorts /media/trocadero/Go /media/trocadero/TV

perl -Ilib -Iextlib fsck.pl

perl -Ilib -Iextlib sort-tree.pl 1

perl -Ilib -Iextlib sort-tree.pl 2

perl -Ilib -Iextlib materialize-paths.pl

perl -Ilib -Iextlib canonicalize-paths.pl NFC

perl -Ilib -Iextlib intuit-durations.pl

perl -Ilib -Iextlib track-counts.pl

perl -Ilib -Iextlib add-tree-media-sort.pl

perl -Ilib -Iextlib intuit-checksums.pl

echo 'update viewing set elapsedSeconds=(select durationSeconds from media where media.rowid=viewing.mediaId) where elapsedSeconds is null and location != "unknown" and exists (select 1 from media where media.rowid=viewing.mediaId and media.durationSeconds IS NOT NULL);' | sqlite3 $PMC_DATABASE

echo 'select media.rowid, path, viewing.elapsedSeconds, viewing.startTime, viewing.endTime, viewing.location, viewing.who from viewing left join media on media.rowid = viewing.mediaId where viewing.elapsedSeconds IS NULL and media.rowid IS NOT NULL and viewing.location != "unknown" order by viewing.rowid asc;' | sqlite3 $PMC_DATABASE

echo 'select rowid, path, spoken_langs from media where spoken_langs like "%?%" and path like "Movies/%" and media.checksum is not null;' | sqlite3 $PMC_DATABASE

echo 'select media.rowid, path, viewing.startTime, viewing.endTime, viewing.location, viewing.who from viewing left join media on media.rowid = viewing.mediaId where audioTrack IS NULL and media.rowid IS NOT NULL order by viewing.rowid asc;' | sqlite3 $PMC_DATABASE

echo 'select media.rowid, media.path, viewing.audioTrack, media.spoken_langs from viewing left join media on media.rowid = viewing.mediaid where media.rowid is not null and (media.spoken_langs="" or media.spoken_langs is null) and media.checksum is not null order by viewing.rowid asc;' | sqlite3 $PMC_DATABASE

echo 'select media.rowid, media.path, viewing.audioTrack, media.spoken_langs from viewing left join media on media.rowid = viewing.mediaid where media.rowid is not null and media.spoken_langs LIKE "%?%" and media.checksum is not null order by viewing.rowid asc;' | sqlite3 $PMC_DATABASE | perl -nle 's/\|(\d+)\|([^|]+)$/$x = (split ",", $2)[$1]; "|$1|$2|$x"/e; print if $x =~ /\?/'
