#!/bin/bash
pushd ~/pi-media-controller/

perl -Ilib -Iextlib untracked-media.pl /media/paul/Commercials /media/paul/LP /media/paul/Movies /media/paul/ROM/*/ /media/paul/Shorts /media/paul/Talks /media/paul/TV

perl -Ilib -Iextlib fsck.pl

perl -Ilib -Iextlib sort-tree.pl 1

perl -Ilib -Iextlib sort-tree.pl 2

perl -Ilib -Iextlib canonicalize-paths.pl NFC

perl -Ilib -Iextlib intuit-durations.pl

perl -Ilib -Iextlib track-counts.pl

perl -Ilib -Iextlib ./add-tree-media-sort.pl

perl -Ilib -Iextlib intuit-checksums.pl;

(echo 'select path, spoken_langs from media where spoken_langs like "?%" and spoken_langs != "??" order by id asc; select path, spoken_langs from media where spoken_langs like "%?%" and spoken_langs != "??" order by id asc;' | sqlite3 $PMC_DATABASE | grep Movies) | tee >(wc -l) >(head) >/dev/null

popd
