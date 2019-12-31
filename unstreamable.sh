#!/bin/sh
echo 'select media.id, media.label_en, media.label_ja, endTime-startTime from viewing join media on media.id = viewing.mediaId WHERE (elapsedSeconds IS NULL or completed) AND media.streamable=1 AND endTime-startTime < 60;' | sqlite3 $PMC_DATABASE
