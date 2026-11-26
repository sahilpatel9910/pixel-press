#!/bin/bash
# Desktop Converter: convert, resize and compress images.
# Uses macOS's built-in `sips`. WebP output needs `cwebp` or ImageMagick (`magick`).
# Written for the bash 3.2 that ships with macOS.
#
# Usage:
#   convert-images.sh --to jpg|png|heic|tiff|gif|bmp|pdf|webp [--max PIXELS] [--quality 1-100]
#                     [--out DIR] [--skip-same] [--report FILE] FILE_OR_FOLDER...
#
# --skip-same  skip files already in the target format (when not resizing)
# --report     write the paths of the new files to FILE, one per line
#
# Originals are never modified. Results go to --out (default ~/Desktop/Converted).
# An existing file is never overwritten: "photo.jpg" becomes "photo-1.jpg", and so on.

set -u

TO=""
MAX=""
QUALITY=""
OUT="$HOME/Desktop/Converted"
SKIP_SAME=""
REPORT=""
INPUTS=()

die() { echo "Error: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --to)      TO="${2:-}"; shift 2 ;;
    --max)     MAX="${2:-}"; shift 2 ;;
    --quality) QUALITY="${2:-}"; shift 2 ;;
    --out)     OUT="${2:-}"; shift 2 ;;
    --skip-same) SKIP_SAME=1; shift ;;
    --report)  REPORT="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    --)        shift; while [ $# -gt 0 ]; do INPUTS+=("$1"); shift; done ;;
    -*)        die "unknown option $1" ;;
    *)         INPUTS+=("$1"); shift ;;
  esac
done

TO=$(printf '%s' "$TO" | tr '[:upper:]' '[:lower:]')
case "$TO" in
  jpg|jpeg) TO=jpg;  SIPS_FMT=jpeg ;;
  png)      SIPS_FMT=png ;;
  heic)     SIPS_FMT=heic ;;
  tif|tiff) TO=tiff; SIPS_FMT=tiff ;;
  gif)      SIPS_FMT=gif ;;
  bmp)      SIPS_FMT=bmp ;;
  pdf)      SIPS_FMT=pdf ;;
  webp)     SIPS_FMT="" ;;
  "")       die "say which format to convert to with --to (jpg, png, heic, tiff, gif, bmp, pdf, webp)" ;;
  *)        die "can't convert to '$TO'. Choose jpg, png, heic, tiff, gif, bmp, pdf or webp" ;;
esac

if [ -n "$MAX" ]; then
  case "$MAX" in ''|*[!0-9]*) die "--max must be a number of pixels, like 2000" ;; esac
fi
if [ -n "$QUALITY" ]; then
  case "$QUALITY" in ''|*[!0-9]*) die "--quality must be a number from 1 to 100" ;; esac
  [ "$QUALITY" -ge 1 ] && [ "$QUALITY" -le 100 ] || die "--quality must be from 1 to 100"
fi
[ ${#INPUTS[@]} -gt 0 ] || die "give at least one image file or folder"

have() { command -v "$1" >/dev/null 2>&1; }
if [ "$TO" = webp ]; then
  have cwebp || have magick || die "WebP needs an extra tool. Install it with: brew install webp"
  have sips || have magick || die "this needs macOS (sips) or ImageMagick"
else
  have sips || die "this needs macOS's built-in 'sips' tool"
fi

is_image() {
  local ext
  ext=$(printf '%s' "${1##*.}" | tr '[:upper:]' '[:lower:]')
  case "$ext" in
    jpg|jpeg|png|heic|heif|tif|tiff|gif|bmp|webp|avif|psd|jp2|ico|icns|tga|dng|cr2|cr3|nef|arw|raf) return 0 ;;
    *) return 1 ;;
  esac
}

# Expand folders (top level only) into their image files.
FILES=()
for p in "${INPUTS[@]}"; do
  if [ -d "$p" ]; then
    for f in "$p"/*; do
      [ -f "$f" ] && is_image "$f" && FILES+=("$f")
    done
  elif [ -f "$p" ]; then
    FILES+=("$p")
  else
    echo "Skipped (not found): $p" >&2
  fi
done
[ ${#FILES[@]} -gt 0 ] || die "no image files found"

mkdir -p "$OUT" || die "can't create output folder $OUT"

unique_path() {
  local base="$1" ext="$2" n=1 path="$OUT/$1.$2"
  while [ -e "$path" ]; do path="$OUT/$base-$n.$ext"; n=$((n + 1)); done
  printf '%s' "$path"
}

human() {
  awk -v b="$1" 'BEGIN { if (b >= 1048576) printf "%.1f MB", b/1048576; else printf "%.0f KB", b/1024 }'
}

ok=0; failed=0; skipped=0; before_total=0; after_total=0
[ -n "$REPORT" ] && : > "$REPORT"
TMPDIR_CONV=$(mktemp -d) || die "can't create a temporary folder"
trap 'rm -rf "$TMPDIR_CONV"' EXIT

for f in "${FILES[@]}"; do
  name=$(basename "$f")
  stem="${name%.*}"
  if [ -n "$SKIP_SAME" ] && [ -z "$MAX" ]; then
    ext=$(printf '%s' "${name##*.}" | tr '[:upper:]' '[:lower:]')
    case "$ext" in jpeg) ext=jpg ;; tif) ext=tiff ;; esac
    if [ "$ext" = "$TO" ]; then
      echo "– $name: already $(printf '%s' "$TO" | tr '[:lower:]' '[:upper:]'), skipped"
      skipped=$((skipped + 1)); continue
    fi
  fi
  dest=$(unique_path "$stem" "$TO")

  # Only shrink, never enlarge.
  resize=""
  if [ -n "$MAX" ] && have sips; then
    w=$(sips -g pixelWidth "$f" 2>/dev/null | awk '/pixelWidth/ {print $2}')
    h=$(sips -g pixelHeight "$f" 2>/dev/null | awk '/pixelHeight/ {print $2}')
    if [ -n "$w" ] && [ -n "$h" ] && { [ "$w" -gt "$MAX" ] || [ "$h" -gt "$MAX" ]; }; then
      resize="$MAX"
    fi
  elif [ -n "$MAX" ]; then
    resize="$MAX"
  fi

  if [ "$TO" = webp ]; then
    if have magick; then
      args=("$f")
      [ -n "$resize" ] && args+=(-resize "${resize}x${resize}>")
      [ -n "$QUALITY" ] && args+=(-quality "$QUALITY")
      magick "${args[@]}" "$dest" >/dev/null 2>&1
    else
      # cwebp reads PNG/JPEG/TIFF; go through PNG with sips first.
      tmp="$TMPDIR_CONV/$stem.png"
      sargs=(-s format png)
      [ -n "$resize" ] && sargs+=(-Z "$resize")
      sips "${sargs[@]}" "$f" --out "$tmp" >/dev/null 2>&1 &&
        cwebp -quiet -q "${QUALITY:-80}" "$tmp" -o "$dest" >/dev/null 2>&1
    fi
  else
    sargs=(-s format "$SIPS_FMT")
    if [ -n "$QUALITY" ] && { [ "$TO" = jpg ] || [ "$TO" = heic ]; }; then
      sargs+=(-s formatOptions "$QUALITY")
    fi
    [ -n "$resize" ] && sargs+=(-Z "$resize")
    sips "${sargs[@]}" "$f" --out "$dest" >/dev/null 2>&1
  fi

  if [ $? -eq 0 ] && [ -s "$dest" ]; then
    b=$(wc -c < "$f" | tr -d ' '); a=$(wc -c < "$dest" | tr -d ' ')
    before_total=$((before_total + b)); after_total=$((after_total + a))
    echo "✓ $name → $(basename "$dest")  ($(human "$b") → $(human "$a"))"
    [ -n "$REPORT" ] && printf '%s\n' "$dest" >> "$REPORT"
    ok=$((ok + 1))
  else
    rm -f "$dest"
    echo "✗ $name: could not convert (not an image, or format not supported)" >&2
    failed=$((failed + 1))
  fi
done

echo
echo "Done: $ok converted, $skipped skipped, $failed failed. Saved to: $OUT"
if [ $ok -gt 0 ]; then
  change=$(awk -v b="$before_total" -v a="$after_total" 'BEGIN {
    if (b <= 0) exit; p = (a - b) * 100 / b
    if (p <= -1) printf " (%d%% smaller)", -p; else if (p >= 1) printf " (%d%% larger)", p }')
  echo "Total size: $(human "$before_total") → $(human "$after_total")$change"
fi
[ $ok -gt 0 ] || [ $skipped -gt 0 ] || exit 1
exit 0
