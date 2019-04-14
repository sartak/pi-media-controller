#!/bin/bash
cd ~/pi-media-controller/

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

echo 'select path, spoken_langs from media where spoken_langs like "%?%" and treeId IN (1, 12);' | sqlite3 $PMC_DATABASE
