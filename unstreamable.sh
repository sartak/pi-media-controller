#!/bin/sh
echo 'select video.id, video.label_en, video.label_ja, endTime-startTime from viewing join video on video.id = viewing.videoId WHERE elapsedSeconds IS NULL AND video.streamable=1 AND endTime-startTime < 60;' | sqlite3 $PMC_DATABASE
