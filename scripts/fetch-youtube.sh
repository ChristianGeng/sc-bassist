#!/usr/bin/env bash
# Download a YouTube video's audio for --file playback (needs yt-dlp).
#   scripts/fetch-youtube.sh URL [DIR]   -> prints the file path
# Only download what you are allowed to; backing tracks made for
# practice are a good start (see the README).
set -euo pipefail
url="${1:?usage: $0 URL [DIR]}"
dir="${2:-$HOME/Music/sc-bassist}"
mkdir -p "$dir"
yt-dlp -q -x --audio-format wav --no-playlist \
	-o "$dir/%(title)s.%(ext)s" --print after_move:filepath "$url"
