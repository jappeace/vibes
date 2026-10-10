#!/usr/bin/env bash
# Identify the music audible in a recording with Shazam. songrec sends only a
# fingerprint of each clip, never the audio.
# Usage: song-id.sh MEDIA START [START...]     (one 12 s clip per START, seconds)
# Run inside: nix-shell -p songrec ffmpeg python3
# Prints per clip: artist - title, the song position at the clip start, and
# song minus media time. A constant difference across clips means one song
# plays straight through; that difference maps media time to song time.
set -euo pipefail

if [ $# -lt 2 ]; then
    echo "usage: $0 MEDIA START [START...]" >&2
    exit 1
fi
media=$1
shift

# GLib's GnuTLS backend ignores SSL_CERT_FILE and reads only
# NIX_SSL_CERT_FILE; unset, songrec panics with "Unacceptable TLS certificate".
export NIX_SSL_CERT_FILE=${NIX_SSL_CERT_FILE:-/etc/ssl/certs/ca-bundle.crt}

clip=$(mktemp --suffix=.wav)
errors=$(mktemp)
trap 'rm -f "$clip" "$errors"' EXIT

for start in "$@"; do
    ffmpeg -hide_banner -v error -y -ss "$start" -t 12 -i "$media" -vn -ac 1 -ar 16000 "$clip"
    printf '%7ss: ' "$start"
    timeout 60 songrec audio-file-to-recognized-song "$clip" 2>"$errors" \
        | START="$start" python3 -c '
import json, os, sys
raw = sys.stdin.read()
try:
    data = json.loads(raw)
except ValueError:
    print("songrec gave no JSON, see its stderr below")
    sys.exit(1)
track = data.get("track")
if not track:
    print("no match")
    sys.exit()
offset = float(data["matches"][0]["offset"])
start = float(os.environ["START"])
artist, title = track["subtitle"], track["title"]
print(f"{artist} - {title} | song at {offset:.3f}s | song - media = {offset - start:+.3f}s")
' || sed 's/^/    /' "$errors" >&2
done
