#!/usr/bin/env bash
# Extract screenshots from a Loom video using yt-dlp + ffmpeg.
set -euo pipefail

URL=""
TIMES=""
INTERVAL=""
SCENES=""
SCENE_THRESHOLD="0.3"
OUT_DIR="./loom-frames"
KEEP_VIDEO=0
QUALITY="high"

usage() {
  cat <<'EOF' >&2
Usage: loom_screenshots.sh <loom-url> <mode> [options]

Modes (pick one):
  --at "00:01:23,2:34,150"   Frames at specific timecodes (HH:MM:SS, MM:SS, or seconds)
  --every N                   One frame every N seconds
  --scenes [THRESHOLD]        Frames at scene changes (default threshold 0.3, range 0.1-0.6)

Options:
  --out DIR                   Output directory (default: ./loom-frames)
  --keep-video                Keep the downloaded mp4 (saved as <out>/video.mp4)
  --quality high|low          Video quality (default: high)
  -h, --help                  Show this help
EOF
  exit 1
}

[[ $# -lt 1 ]] && usage
case "$1" in -h|--help) usage ;; esac

URL="$1"; shift

# Allow bare video ID
if [[ ! "$URL" =~ ^https?:// ]]; then
  URL="https://www.loom.com/share/$URL"
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --at)         TIMES="$2"; shift 2 ;;
    --every)      INTERVAL="$2"; shift 2 ;;
    --scenes)
      SCENES=1
      if [[ "${2:-}" =~ ^0?\.[0-9]+$ ]]; then
        SCENE_THRESHOLD="$2"; shift 2
      else
        shift
      fi
      ;;
    --out)        OUT_DIR="$2"; shift 2 ;;
    --keep-video) KEEP_VIDEO=1; shift ;;
    --quality)    QUALITY="$2"; shift 2 ;;
    -h|--help)    usage ;;
    *) echo "Unknown arg: $1" >&2; usage ;;
  esac
done

modes=0
[[ -n "$TIMES" ]]    && ((modes++)) || true
[[ -n "$INTERVAL" ]] && ((modes++)) || true
[[ -n "$SCENES" ]]   && ((modes++)) || true
if [[ $modes -ne 1 ]]; then
  echo "Error: choose exactly one of --at, --every, --scenes" >&2
  usage
fi

for cmd in yt-dlp ffmpeg; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: $cmd not found. Install: brew install $cmd" >&2
    exit 2
  fi
done

mkdir -p "$OUT_DIR"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

VIDEO="$TMPDIR/video.mp4"
echo "→ Downloading Loom video from $URL" >&2

case "$QUALITY" in
  high) FORMAT="http-transcoded/bv*+ba/best" ;;
  low)  FORMAT="worst" ;;
  *)    FORMAT="http-transcoded/bv*+ba/best" ;;
esac

yt-dlp -q --no-warnings -f "$FORMAT" -o "$VIDEO" "$URL"

if [[ $KEEP_VIDEO -eq 1 ]]; then
  cp "$VIDEO" "$OUT_DIR/video.mp4"
  echo "→ Video saved to $OUT_DIR/video.mp4" >&2
fi

# Convert "S", "MM:SS" or "HH:MM:SS" to a normalized HH:MM:SS.fff
normalize_time() {
  local t="$1"
  if [[ "$t" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    awk -v s="$t" 'BEGIN { h=int(s/3600); m=int((s-h*3600)/60); ss=s-h*3600-m*60; printf "%02d:%02d:%06.3f\n", h, m, ss }'
  elif [[ "$t" =~ ^[0-9]+:[0-9]+$ ]]; then
    echo "00:$t"
  else
    echo "$t"
  fi
}

echo "→ Extracting frames..." >&2

if [[ -n "$TIMES" ]]; then
  IFS=',' read -ra TIME_ARRAY <<< "$TIMES"
  for raw in "${TIME_ARRAY[@]}"; do
    t=$(echo "$raw" | xargs)
    [[ -z "$t" ]] && continue
    norm=$(normalize_time "$t")
    label=$(echo "$norm" | tr ':' '-' | sed 's/\.[0-9]*$//')
    out="$OUT_DIR/frame_${label}.png"
    # -ss before -i is fast (input seek) and accurate enough for screenshots
    ffmpeg -hide_banner -loglevel error -ss "$norm" -i "$VIDEO" -frames:v 1 -y "$out"
    echo "  $out"
  done

elif [[ -n "$INTERVAL" ]]; then
  ffmpeg -hide_banner -loglevel error -i "$VIDEO" -vf "fps=1/$INTERVAL" -y "$OUT_DIR/frame_%03d.png"
  ls "$OUT_DIR"/frame_*.png

elif [[ -n "$SCENES" ]]; then
  ffmpeg -hide_banner -loglevel error -i "$VIDEO" \
    -vf "select=gt(scene\\,$SCENE_THRESHOLD)" \
    -vsync vfr -y "$OUT_DIR/scene_%03d.png"
  ls "$OUT_DIR"/scene_*.png 2>/dev/null || echo "  (no scene changes detected — try a lower threshold)" >&2
fi

echo "✓ Done. Output: $OUT_DIR" >&2
