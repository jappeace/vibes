#!/usr/bin/env bash
# Tile timestamped frames from a stretch of video into one image, so the
# footage can be looked at with the Read tool.
# Usage: contact-sheet.sh VIDEO START DURATION FPS COLS ROWS OUT.jpg
#   OUT containing %d (eg sheets/s_%02d.jpg) writes every sheet; otherwise
#   only the first COLS x ROWS frames are kept.
# Each tile is stamped bottom-left with its SOURCE time, so a moment found on
# a sheet can be used as a seek position directly. Bottom, because phone and
# WODProof recordings burn their own timers into the top.
set -euo pipefail

if [ $# -ne 7 ]; then
    echo "usage: $0 VIDEO START DURATION FPS COLS ROWS OUT.jpg" >&2
    exit 1
fi
video=$1 start=$2 duration=$3 fps=$4 cols=$5 rows=$6 out=$7

filter="fps=$fps,scale=180:-2,drawtext=text='%{pts\:hms\:$start}':x=4:y=h-22:fontsize=16:fontcolor=yellow:box=1:boxcolor=black@0.6,tile=${cols}x${rows}:padding=2:color=white"
frame_limit=(-frames:v 1)
if [[ $out == *%* ]]; then
    frame_limit=()
fi

mkdir -p "$(dirname "$out")"
# Fontconfig complains about a missing config in the container but drawtext
# still falls back to a built-in font; filter only that noise.
ffmpeg -hide_banner -v error -y -ss "$start" -i "$video" -t "$duration" -an \
    -vf "$filter" -fps_mode passthrough "${frame_limit[@]}" "$out" \
    2> >(grep -v '^Fontconfig error' >&2)
