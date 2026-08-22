#!/usr/bin/env bash
#
# vlog-prep.sh — prepare a vlog episode for calvinpriice.com
#
#   ./tools/vlog-prep.sh <input-video> <slug> [options]
#
# Options:
#   --height 720      output height (default 720; use 1080 only for short eps)
#   --max-mb 48       hard size ceiling in MB (default 48)
#   --poster 00:00:03 timestamp to grab the poster frame from (default 3s)
#   --srt file.srt    also convert a Descript/whatever SRT into captions (.vtt)
#   --preset medium   x264 preset (default slow = smallest file, slowest encode;
#                     use "medium" or "fast" when you'd rather not wait)
#
# What it does:
#   1. tone-maps HDR (iPhone) footage down to SDR so it isn't washed out
#   2. encodes H.264 720p with faststart so playback begins instantly
#   3. if the result is over --max-mb, automatically re-encodes two-pass to fit
#   4. pulls a poster frame
#   5. prints the exact HTML + schema values to paste into the episode page
#
# WHY THE SIZE CEILING: these files are committed to git and served by Netlify.
#   - GitHub hard-rejects any single file over 100 MB (warns at 50 MB)
#   - Netlify bills 20 credits per GB; the free tier is 300 credits (~15 GB/mo)
# Staying near 48 MB keeps ~300 plays/month inside the free allowance.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NODE="${NODE_BIN:-node}"
FFMPEG="$("$NODE" -p "require('$ROOT/tools/node_modules/ffmpeg-static')")"
FFPROBE="$("$NODE" -p "require('$ROOT/tools/node_modules/ffprobe-static').path")"

if [ $# -lt 2 ]; then
  sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 1
fi

INPUT="$1"; SLUG="$2"; shift 2
HEIGHT=720; MAX_MB=48; POSTER_AT="00:00:03"; SRT=""; PRESET="slow"

while [ $# -gt 0 ]; do
  case "$1" in
    --height) HEIGHT="$2"; shift 2 ;;
    --max-mb) MAX_MB="$2"; shift 2 ;;
    --poster) POSTER_AT="$2"; shift 2 ;;
    --srt)    SRT="$2"; shift 2 ;;
    --preset) PRESET="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

[ -f "$INPUT" ] || { echo "no such file: $INPUT" >&2; exit 1; }

OUT="$ROOT/videos/$SLUG.mp4"
POSTER="$ROOT/images/vlog/$SLUG-poster.jpg"
VTT="$ROOT/videos/$SLUG.vtt"
mkdir -p "$ROOT/videos" "$ROOT/images/vlog"

# ---- probe -----------------------------------------------------------------
DUR=$("$FFPROBE" -v error -show_entries format=duration -of csv=p=0 "$INPUT")
TRC=$("$FFPROBE" -v error -select_streams v:0 -show_entries stream=color_transfer -of csv=p=0 "$INPUT" || echo "")
DUR_INT=$(printf '%.0f' "$DUR")

echo "  source    : $(basename "$INPUT")"
echo "  duration  : $(printf '%d:%02d' $((DUR_INT/60)) $((DUR_INT%60)))"
echo "  transfer  : ${TRC:-unknown}"

# ---- HDR? ------------------------------------------------------------------
# iPhone records HLG (arib-std-b67) or PQ (smpte2084). Straight scaling makes
# those look grey and washed out, so tone-map to bt709 first.
case "$TRC" in
  arib-std-b67|smpte2084)
    echo "  hdr       : yes -> tone-mapping to SDR"
    VF="zscale=t=linear:npl=100,format=gbrpf32le,zscale=p=bt709,tonemap=tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=tv,format=yuv420p,scale=-2:$HEIGHT"
    ;;
  *)
    echo "  hdr       : no"
    VF="scale=-2:$HEIGHT,format=yuv420p"
    ;;
esac

COMMON=(-c:v libx264 -preset "$PRESET" -profile:v high -level 4.0
        -c:a aac -b:a 128k -ac 2 -movflags +faststart -pix_fmt yuv420p)

# ---- pass 1: quality-based -------------------------------------------------
echo ""
echo "  encoding (crf 26, ${HEIGHT}p, preset $PRESET) ..."
"$FFMPEG" -hide_banner -loglevel error -stats -y -i "$INPUT" \
  -vf "$VF" -crf 26 "${COMMON[@]}" "$OUT"

SIZE_MB=$(awk -v b="$(stat -f%z "$OUT")" 'BEGIN{printf "%.1f", b/1048576}')
echo "  result    : ${SIZE_MB} MB"

# ---- pass 2: only if it blew the ceiling -----------------------------------
if awk -v s="$SIZE_MB" -v m="$MAX_MB" 'BEGIN{exit !(s>m)}'; then
  VBIT=$(awk -v m="$MAX_MB" -v d="$DUR" 'BEGIN{printf "%d", ((m*8*1048576)-(128000*d))/d/1000}')
  echo "  over ${MAX_MB} MB -> two-pass re-encode at ${VBIT}k to fit"
  PASSLOG="$(mktemp -t vlogpass)"
  "$FFMPEG" -hide_banner -loglevel error -stats -y -i "$INPUT" -vf "$VF" \
    -c:v libx264 -preset "$PRESET" -b:v "${VBIT}k" -pass 1 -passlogfile "$PASSLOG" -an -f null /dev/null
  "$FFMPEG" -hide_banner -loglevel error -stats -y -i "$INPUT" -vf "$VF" \
    -b:v "${VBIT}k" -pass 2 -passlogfile "$PASSLOG" "${COMMON[@]}" "$OUT"
  rm -f "$PASSLOG"*
  SIZE_MB=$(awk -v b="$(stat -f%z "$OUT")" 'BEGIN{printf "%.1f", b/1048576}')
  echo "  result    : ${SIZE_MB} MB"
fi

# ---- poster ----------------------------------------------------------------
"$FFMPEG" -hide_banner -loglevel error -y -ss "$POSTER_AT" -i "$OUT" \
  -vframes 1 -q:v 4 "$POSTER"
POSTER_KB=$(awk -v b="$(stat -f%z "$POSTER")" 'BEGIN{printf "%.0f", b/1024}')

# ---- captions --------------------------------------------------------------
if [ -n "$SRT" ] && [ -f "$SRT" ]; then
  { printf 'WEBVTT\n\n'; sed -e 's/\r$//' -e 's/,\([0-9][0-9][0-9]\)/.\1/g' "$SRT"; } > "$VTT"
  echo "  captions  : $SLUG.vtt written"
else
  echo "  captions  : none (pass --srt to add them)"
fi

# ---- report ----------------------------------------------------------------
MIN=$((DUR_INT/60)); SEC=$((DUR_INT%60))
PLAYS=$(awk -v s="$SIZE_MB" 'BEGIN{printf "%d", (15*1024)/s}')

cat <<REPORT

  ------------------------------------------------------------------
  DONE — $SLUG
  ------------------------------------------------------------------
  video     videos/$SLUG.mp4          ${SIZE_MB} MB
  poster    images/vlog/$SLUG-poster.jpg   ${POSTER_KB} KB

  Netlify:  ~$PLAYS full plays/month inside the free 15 GB allowance

  Paste these into the episode page (from vlog/_template.html):
    {{SLUG}}          $SLUG
    {{RUNTIME}}       $(printf '%d:%02d' $MIN $SEC)
    {{ISO_DURATION}}  PT${MIN}M${SEC}S
    {{ISO_DATE}}      $(date +%Y-%m-%d)
    {{DATE_HUMAN}}    $(date "+%B %-d, %Y")
  ------------------------------------------------------------------
REPORT
