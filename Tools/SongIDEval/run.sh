#!/bin/bash
# Scores song identification on the labelled sets. Needs network access and a
# Last.fm API key:
#
#   LASTFM_API_KEY=… Tools/SongIDEval/run.sh                 # all sets
#   LASTFM_API_KEY=… Tools/SongIDEval/run.sh sets/fresh.json
set -euo pipefail
cd "$(dirname "$0")"
: "${LASTFM_API_KEY:?Set LASTFM_API_KEY}"

APP=../../Walkman
BUILD=$(mktemp -d)
trap 'rm -rf "$BUILD"' EXIT

swiftc -O main.swift OnDeviceModel.swift \
  "$APP/Search/SongIdentifier.swift" "$APP/Search/TrackMatching.swift" "$APP/Search/LastFM.swift" \
  "$APP/Search/YouTubeSearch.swift" "$APP/Model/YouTubeVideoID.swift" "$APP/Model/HistoryEntry.swift" \
  -o "$BUILD/songid-eval"

if [ $# -eq 0 ]; then set -- sets/tuning.json sets/held-out.json sets/fresh.json; fi
"$BUILD/songid-eval" "$@"
