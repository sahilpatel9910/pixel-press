#!/bin/bash
# Desktop Converter: installs Finder Quick Actions for images.
# Run once with:  bash install-quick-actions.sh
# Then right-click any image in Finder > Quick Actions.
# To remove them later:  bash install-quick-actions.sh --uninstall
set -e

[ "$(uname)" = "Darwin" ] || { echo "This installer is for macOS."; exit 1; }

APP="$HOME/Library/Application Support/Desktop Converter"
SVC="$HOME/Library/Services"
NAMES=("Convert to JPG" "Compress to Size…" "Convert & Resize…")
OLD=("Convert to PNG" "Make PDF" "Compress for Email")

if [ "${1:-}" = "--uninstall" ]; then
  for n in "${NAMES[@]}" "${OLD[@]}"; do rm -rf "$SVC/$n.workflow"; done
  rm -rf "$APP"
  /System/Library/CoreServices/pbs -update 2>/dev/null || true
  echo "Removed the Desktop Converter Quick Actions."
  exit 0
fi

mkdir -p "$APP" "$SVC"
for n in "${OLD[@]}"; do rm -rf "$SVC/$n.workflow"; done
cat > "$APP/convert-images.sh" <<'DC_EOF_C3B6C3EB'
#!/bin/bash
# Desktop Converter: convert, resize and compress images.
# Uses macOS's built-in `sips`. WebP output needs `cwebp` or ImageMagick (`magick`).
# Written for the bash 3.2 that ships with macOS.
#
# Usage:
#   convert-images.sh --to jpg|png|heic|tiff|gif|bmp|pdf|webp [--max PIXELS] [--quality 1-100]
#                     [--out DIR] [--skip-same] [--report FILE] FILE_OR_FOLDER...
#
# --target SIZE  make each image smaller than SIZE (e.g. 500KB, 1.5MB); jpg or heic only.
#                Lowers quality first, then dimensions. Files already under SIZE are skipped.
# --info         print "COUNT TOTAL_BYTES LARGEST_BYTES" for the images and exit
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
TARGET=""
INFO=""
INPUTS=()

die() { echo "Error: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --to)      TO="${2:-}"; shift 2 ;;
    --max)     MAX="${2:-}"; shift 2 ;;
    --quality) QUALITY="${2:-}"; shift 2 ;;
    --out)     OUT="${2:-}"; shift 2 ;;
    --skip-same) SKIP_SAME=1; shift ;;
    --target)  TARGET="${2:-}"; shift 2 ;;
    --info)    INFO=1; shift ;;
    --report)  REPORT="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
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

# "1.5 MB", "300kb", "2M", "500 k" or plain bytes -> bytes
parse_size() {
  printf '%s' "$1" | tr -d ' ' | tr '[:upper:]' '[:lower:]' | awk '{
    if (!match($0, /^[0-9]+(\.[0-9]+)?/)) exit 1
    n = substr($0, 1, RLENGTH); u = substr($0, RLENGTH + 1)
    if (u == "" || u == "b") m = 1; else if (u == "k" || u == "kb") m = 1024
    else if (u == "m" || u == "mb") m = 1048576; else exit 1
    v = int(n * m); if (v < 5120) exit 1; print v }'
}
size_label() {
  awk -v b="$1" 'BEGIN { if (b >= 1048576) printf "%g MB", int(b / 1048576 * 10 + 0.5) / 10; else printf "%d KB", int(b / 1024 + 0.5) }'
}
TARGET_BYTES=""
if [ -n "$TARGET" ]; then
  TARGET_BYTES=$(parse_size "$TARGET") || die "'$TARGET' isn't a size I understand. Try something like 500 KB or 1.5 MB (at least 5 KB)"
  [ "$TO" = jpg ] || [ "$TO" = heic ] || die "a target size works with jpg or heic only"
  TARGET_LABEL=$(size_label "$TARGET_BYTES")
fi

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

size_of() { wc -c < "$1" | tr -d ' '; }

if [ -n "$INFO" ]; then
  count=0; total=0; largest=0
  for f in "${FILES[@]}"; do
    is_image "$f" || continue
    b=$(size_of "$f"); count=$((count + 1)); total=$((total + b)); [ "$b" -gt "$largest" ] && largest=$b
  done
  [ $count -gt 0 ] || die "no image files found"
  echo "$count $total $largest"
  exit 0
fi

mkdir -p "$OUT" || die "can't create output folder $OUT"

unique_path() {
  local base="$1" ext="$2" n=1 path="$OUT/$1.$2"
  while [ -e "$path" ]; do path="$OUT/$base-$n.$ext"; n=$((n + 1)); done
  printf '%s' "$path"
}

human() {
  awk -v b="$1" 'BEGIN { if (b >= 1048576) printf "%.1f MB", b/1048576; else printf "%.0f KB", b/1024 }'
}

# Write $1 to $2 under TARGET_BYTES: try a few qualities, then shrink and try again.
# Sets FIT=1 if it got under the target, FIT=0 if it saved the smallest it could.
compress_to_target() {
  local src="$1" dest="$2" w h dim q s="" tmp="$TMPDIR_CONV/try.$TO" round=0
  FIT=0
  w=$(sips -g pixelWidth "$src" 2>/dev/null | awk '/pixelWidth/ {print $2}')
  h=$(sips -g pixelHeight "$src" 2>/dev/null | awk '/pixelHeight/ {print $2}')
  [ -n "$w" ] && [ -n "$h" ] || return 1
  dim=$w; [ "$h" -gt "$dim" ] && dim=$h
  [ -n "$MAX" ] && [ "$MAX" -lt "$dim" ] && dim=$MAX
  while [ $round -lt 12 ]; do
    for q in 82 65 50; do
      sips -s format "$SIPS_FMT" -s formatOptions "$q" -Z "$dim" "$src" --out "$tmp" >/dev/null 2>&1 || return 1
      s=$(size_of "$tmp")
      if [ "$s" -le "$TARGET_BYTES" ]; then mv "$tmp" "$dest"; FIT=1; return 0; fi
    done
    dim=$(awk -v d="$dim" -v t="$TARGET_BYTES" -v s="$s" 'BEGIN {
      n = int(d * sqrt(t / s) * 0.95); if (n > d * 0.9) n = int(d * 0.9); print n }')
    [ "$dim" -ge 32 ] || break
    round=$((round + 1))
  done
  mv "$tmp" "$dest"
}

ok=0; failed=0; skipped=0; over=0; before_total=0; after_total=0
[ -n "$REPORT" ] && : > "$REPORT"
TMPDIR_CONV=$(mktemp -d) || die "can't create a temporary folder"
trap 'rm -rf "$TMPDIR_CONV"' EXIT

for f in "${FILES[@]}"; do
  name=$(basename "$f")
  stem="${name%.*}"
  if ! is_image "$f"; then
    echo "✗ $name: not an image" >&2
    failed=$((failed + 1)); continue
  fi
  if [ -n "$SKIP_SAME" ] && [ -z "$MAX" ]; then
    ext=$(printf '%s' "${name##*.}" | tr '[:upper:]' '[:lower:]')
    case "$ext" in jpeg) ext=jpg ;; tif) ext=tiff ;; esac
    if [ "$ext" = "$TO" ]; then
      echo "– $name: already $(printf '%s' "$TO" | tr '[:lower:]' '[:upper:]'), skipped"
      skipped=$((skipped + 1)); continue
    fi
  fi
  if [ -n "$TARGET_BYTES" ] && [ "$(size_of "$f")" -le "$TARGET_BYTES" ]; then
    echo "– $name: already under $TARGET_LABEL, skipped"
    skipped=$((skipped + 1)); continue
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

  FIT=1
  if [ -n "$TARGET_BYTES" ]; then
    compress_to_target "$f" "$dest"
  elif [ "$TO" = webp ]; then
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
    note=""; [ "$FIT" = 1 ] || { note="  (couldn't get under $TARGET_LABEL)"; over=$((over + 1)); }
    echo "✓ $name → $(basename "$dest")  ($(human "$b") → $(human "$a"))$note"
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
[ $over -gt 0 ] && echo "Over target: $over"
[ $ok -gt 0 ] || [ $skipped -gt 0 ] || exit 1
exit 0
DC_EOF_C3B6C3EB
chmod +x "$APP/convert-images.sh"

rm -rf "$SVC/Convert to JPG.workflow"
mkdir -p "$SVC/Convert to JPG.workflow/Contents"
cat > "$SVC/Convert to JPG.workflow/Contents"/Info.plist <<'DC_EOF_22300A40'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSServices</key>
	<array>
		<dict>
			<key>NSBackgroundColorName</key>
			<string>background</string>
			<key>NSIconName</key>
			<string>NSActionTemplate</string>
			<key>NSMenuItem</key>
			<dict>
				<key>default</key>
				<string>Convert to JPG</string>
			</dict>
			<key>NSMessage</key>
			<string>runWorkflowAsService</string>
			<key>NSRequiredContext</key>
			<dict>
				<key>NSApplicationIdentifier</key>
				<string>com.apple.finder</string>
			</dict>
			<key>NSSendFileTypes</key>
			<array>
				<string>public.image</string>
				<string>public.folder</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
DC_EOF_22300A40
cat > "$SVC/Convert to JPG.workflow/Contents"/document.wflow <<'DC_EOF_47CD667E'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AMApplicationBuild</key>
	<string>523</string>
	<key>AMApplicationVersion</key>
	<string>2.10</string>
	<key>AMDocumentVersion</key>
	<string>2</string>
	<key>actions</key>
	<array>
		<dict>
			<key>action</key>
			<dict>
				<key>AMAccepts</key>
				<dict>
					<key>Container</key>
					<string>List</string>
					<key>Optional</key>
					<true/>
					<key>Types</key>
					<array>
						<string>com.apple.cocoa.string</string>
					</array>
				</dict>
				<key>AMActionVersion</key>
				<string>2.0.3</string>
				<key>AMApplication</key>
				<array>
					<string>Automator</string>
				</array>
				<key>AMParameterProperties</key>
				<dict>
					<key>COMMAND_STRING</key>
					<dict/>
					<key>CheckedForUserDefaultShell</key>
					<dict/>
					<key>inputMethod</key>
					<dict/>
					<key>shell</key>
					<dict/>
					<key>source</key>
					<dict/>
				</dict>
				<key>AMProvides</key>
				<dict>
					<key>Container</key>
					<string>List</string>
					<key>Types</key>
					<array>
						<string>com.apple.cocoa.string</string>
					</array>
				</dict>
				<key>ActionBundlePath</key>
				<string>/System/Library/Automator/Run Shell Script.action</string>
				<key>ActionName</key>
				<string>Run Shell Script</string>
				<key>ActionParameters</key>
				<dict>
					<key>COMMAND_STRING</key>
					<string># Desktop Converter Quick Action
DC="$HOME/Library/Application Support/Desktop Converter"
SCRIPT="$DC/convert-images.sh"
[ $# -gt 0 ] || exit 0

notify() { /usr/bin/osascript -e 'on run argv' -e 'display notification (item 2 of argv) with title "Desktop Converter" subtitle (item 1 of argv)' -e 'end run' "$1" "$2" &gt;/dev/null 2&gt;&amp;1; }
alert() { /usr/bin/osascript -e 'on run argv' -e 'display alert "Desktop Converter" message (item 1 of argv) as warning' -e 'end run' "$1" &gt;/dev/null 2&gt;&amp;1; }

if [ -d "$1" ]; then OUT="$1/Converted"; else OUT="$(dirname "$1")/Converted"; fi
OPTS=(--to jpg --quality 90 --skip-same); LABEL=JPG; DONE_VERB="converted to JPG"

if [ $# -gt 5 ] || [ -d "$1" ]; then notify "Converting…" "This can take a moment."; fi

REPORT=$(/usr/bin/mktemp -t dconv)
RESULT=$(/bin/bash "$SCRIPT" "${OPTS[@]}" --out "$OUT" --report "$REPORT" "$@" 2&gt;&amp;1)
N=$(grep -c . "$REPORT")
SKIP=$(printf '%s\n' "$RESULT" | sed -n 's/^Done: .*converted, \([0-9]*\) skipped.*/\1/p')
FAIL=$(printf '%s\n' "$RESULT" | sed -n 's/^Done: .*skipped, \([0-9]*\) failed.*/\1/p')
SIZES=$(printf '%s\n' "$RESULT" | sed -n 's/^Total size: //p')
FIRST=$(head -1 "$REPORT")
rm -f "$REPORT"
[ "$N" = 1 ] &amp;&amp; WORD=image || WORD=images

if [ "$N" -gt 0 ]; then
  BODY="$SIZES"
  [ "${SKIP:-0}" -gt 0 ] &amp;&amp; BODY="$BODY · $SKIP already $LABEL"
  [ "${FAIL:-0}" -gt 0 ] &amp;&amp; BODY="$BODY · $FAIL couldn't be converted"
  OVER=$(printf '%s\n' "$RESULT" | sed -n 's/^Over target: //p')
  [ -n "$OVER" ] &amp;&amp; BODY="$BODY · $OVER couldn't get $LABEL"
  notify "$N $WORD $DONE_VERB" "$BODY"
  /usr/bin/open -R "$FIRST"
elif [ "${SKIP:-0}" -gt 0 ]; then
  rmdir "$OUT" 2&gt;/dev/null
  notify "Nothing to do" "Already $LABEL."
else
  rmdir "$OUT" 2&gt;/dev/null
  WHY=$(printf '%s\n' "$RESULT" | grep -E '^(Error:|✗)' | head -1 | sed -e 's/^Error: //' -e 's/^✗ //')
  alert "Couldn't convert: ${WHY:-unknown problem}"
fi
exit 0
</string>
					<key>CheckedForUserDefaultShell</key>
					<true/>
					<key>inputMethod</key>
					<integer>1</integer>
					<key>shell</key>
					<string>/bin/bash</string>
					<key>source</key>
					<string></string>
				</dict>
				<key>BundleIdentifier</key>
				<string>com.apple.RunShellScript</string>
				<key>CFBundleVersion</key>
				<string>2.0.3</string>
				<key>CanShowSelectedItemsWhenRun</key>
				<false/>
				<key>CanShowWhenRun</key>
				<true/>
				<key>Category</key>
				<array>
					<string>AMCategoryUtilities</string>
				</array>
				<key>Class Name</key>
				<string>RunShellScriptAction</string>
				<key>InputUUID</key>
				<string>68679204-546D-4867-AEB2-D14CE2289D19</string>
				<key>Keywords</key>
				<array>
					<string>Shell</string>
					<string>Script</string>
					<string>Command</string>
					<string>Run</string>
					<string>Unix</string>
				</array>
				<key>OutputUUID</key>
				<string>9A91AD4A-5602-4ED0-AFB8-1D25199BBBEB</string>
				<key>UUID</key>
				<string>95ADABE1-8CBF-4F8F-8105-0A07D91C03C7</string>
				<key>UnlocalizedApplications</key>
				<array>
					<string>Automator</string>
				</array>
				<key>arguments</key>
				<dict>
					<key>0</key>
					<dict>
						<key>default value</key>
						<integer>0</integer>
						<key>name</key>
						<string>inputMethod</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>0</string>
					</dict>
					<key>1</key>
					<dict>
						<key>default value</key>
						<false/>
						<key>name</key>
						<string>CheckedForUserDefaultShell</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>1</string>
					</dict>
					<key>2</key>
					<dict>
						<key>default value</key>
						<string></string>
						<key>name</key>
						<string>source</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>2</string>
					</dict>
					<key>3</key>
					<dict>
						<key>default value</key>
						<string></string>
						<key>name</key>
						<string>COMMAND_STRING</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>3</string>
					</dict>
					<key>4</key>
					<dict>
						<key>default value</key>
						<string>/bin/sh</string>
						<key>name</key>
						<string>shell</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>4</string>
					</dict>
				</dict>
				<key>isViewVisible</key>
				<integer>1</integer>
				<key>location</key>
				<string>309.000000:253.000000</string>
				<key>nibPath</key>
				<string>/System/Library/Automator/Run Shell Script.action/Contents/Resources/Base.lproj/main.nib</string>
			</dict>
			<key>isViewVisible</key>
			<integer>1</integer>
		</dict>
	</array>
	<key>connectors</key>
	<dict/>
	<key>workflowMetaData</key>
	<dict>
		<key>applicationBundleID</key>
		<string>com.apple.finder</string>
		<key>applicationBundleIDsByPath</key>
		<dict>
			<key>/System/Library/CoreServices/Finder.app</key>
			<string>com.apple.finder</string>
		</dict>
		<key>applicationPath</key>
		<string>/System/Library/CoreServices/Finder.app</string>
		<key>applicationPaths</key>
		<array>
			<string>/System/Library/CoreServices/Finder.app</string>
		</array>
		<key>inputTypeIdentifier</key>
		<string>com.apple.Automator.fileSystemObject</string>
		<key>outputTypeIdentifier</key>
		<string>com.apple.Automator.nothing</string>
		<key>presentationMode</key>
		<integer>15</integer>
		<key>processesInput</key>
		<integer>0</integer>
		<key>serviceApplicationBundleID</key>
		<string>com.apple.finder</string>
		<key>serviceApplicationPath</key>
		<string>/System/Library/CoreServices/Finder.app</string>
		<key>serviceInputTypeIdentifier</key>
		<string>com.apple.Automator.fileSystemObject</string>
		<key>serviceOutputTypeIdentifier</key>
		<string>com.apple.Automator.nothing</string>
		<key>serviceProcessesInput</key>
		<integer>0</integer>
		<key>systemImageName</key>
		<string>NSActionTemplate</string>
		<key>useAutomaticInputType</key>
		<integer>0</integer>
		<key>workflowTypeIdentifier</key>
		<string>com.apple.Automator.servicesMenu</string>
	</dict>
</dict>
</plist>
DC_EOF_47CD667E

rm -rf "$SVC/Compress to Size….workflow"
mkdir -p "$SVC/Compress to Size….workflow/Contents"
cat > "$SVC/Compress to Size….workflow/Contents"/Info.plist <<'DC_EOF_0CB67A3F'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSServices</key>
	<array>
		<dict>
			<key>NSBackgroundColorName</key>
			<string>background</string>
			<key>NSIconName</key>
			<string>NSActionTemplate</string>
			<key>NSMenuItem</key>
			<dict>
				<key>default</key>
				<string>Compress to Size…</string>
			</dict>
			<key>NSMessage</key>
			<string>runWorkflowAsService</string>
			<key>NSRequiredContext</key>
			<dict>
				<key>NSApplicationIdentifier</key>
				<string>com.apple.finder</string>
			</dict>
			<key>NSSendFileTypes</key>
			<array>
				<string>public.image</string>
				<string>public.folder</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
DC_EOF_0CB67A3F
cat > "$SVC/Compress to Size….workflow/Contents"/document.wflow <<'DC_EOF_B297AF3E'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AMApplicationBuild</key>
	<string>523</string>
	<key>AMApplicationVersion</key>
	<string>2.10</string>
	<key>AMDocumentVersion</key>
	<string>2</string>
	<key>actions</key>
	<array>
		<dict>
			<key>action</key>
			<dict>
				<key>AMAccepts</key>
				<dict>
					<key>Container</key>
					<string>List</string>
					<key>Optional</key>
					<true/>
					<key>Types</key>
					<array>
						<string>com.apple.cocoa.string</string>
					</array>
				</dict>
				<key>AMActionVersion</key>
				<string>2.0.3</string>
				<key>AMApplication</key>
				<array>
					<string>Automator</string>
				</array>
				<key>AMParameterProperties</key>
				<dict>
					<key>COMMAND_STRING</key>
					<dict/>
					<key>CheckedForUserDefaultShell</key>
					<dict/>
					<key>inputMethod</key>
					<dict/>
					<key>shell</key>
					<dict/>
					<key>source</key>
					<dict/>
				</dict>
				<key>AMProvides</key>
				<dict>
					<key>Container</key>
					<string>List</string>
					<key>Types</key>
					<array>
						<string>com.apple.cocoa.string</string>
					</array>
				</dict>
				<key>ActionBundlePath</key>
				<string>/System/Library/Automator/Run Shell Script.action</string>
				<key>ActionName</key>
				<string>Run Shell Script</string>
				<key>ActionParameters</key>
				<dict>
					<key>COMMAND_STRING</key>
					<string># Desktop Converter Quick Action
DC="$HOME/Library/Application Support/Desktop Converter"
SCRIPT="$DC/convert-images.sh"
[ $# -gt 0 ] || exit 0

notify() { /usr/bin/osascript -e 'on run argv' -e 'display notification (item 2 of argv) with title "Desktop Converter" subtitle (item 1 of argv)' -e 'end run' "$1" "$2" &gt;/dev/null 2&gt;&amp;1; }
alert() { /usr/bin/osascript -e 'on run argv' -e 'display alert "Desktop Converter" message (item 1 of argv) as warning' -e 'end run' "$1" &gt;/dev/null 2&gt;&amp;1; }

if [ -d "$1" ]; then OUT="$1/Converted"; else OUT="$(dirname "$1")/Converted"; fi
INFO=$(/bin/bash "$SCRIPT" --to jpg --info "$@" 2&gt;/dev/null)
if [ -z "$INFO" ]; then alert "There are no images in what you selected."; exit 0; fi
read COUNT TOTAL LARGEST &lt;&lt;INFOEOF
$INFO
INFOEOF
hs() { awk -v b="$1" 'BEGIN { if (b &gt;= 1048576) printf "%.1f MB", b / 1048576; else printf "%d KB", int(b / 1024 + 0.5) }'; }
if [ "$COUNT" = 1 ]; then SUMMARY="Selected: 1 image, $(hs "$TOTAL")"
else SUMMARY="Selected: $COUNT images, $(hs "$TOTAL") in total (largest $(hs "$LARGEST"))"; fi

PREFS="$DC/last-target"
LAST=$(cat "$PREFS" 2&gt;/dev/null)
case "$LAST" in "2 MB - good for email"|"1 MB"|"500 KB"|"200 KB - good for web forms"|"100 KB"|"Custom size...") ;; *) LAST="2 MB - good for email" ;; esac

PICK=$(/usr/bin/osascript - "$LAST" "$SUMMARY" 2&gt;/dev/null &lt;&lt;'APPLESCRIPT'
on run argv
  activate
  set picked to choose from list {"2 MB - good for email", "1 MB", "500 KB", "200 KB - good for web forms", "100 KB", "Custom size..."} with title "Compress to Size" with prompt (item 2 of argv) &amp; return &amp; return &amp; "Make each image smaller than:" default items {item 1 of argv} OK button name "Compress" cancel button name "Cancel"
  if picked is false then return ""
  set choice to item 1 of picked
  if choice is "Custom size..." then
    set r to display dialog "Make each image smaller than:" &amp; return &amp; "(for example 300 KB or 1.5 MB)" default answer "300 KB" with title "Compress to Size" buttons {"Cancel", "Compress"} default button "Compress" cancel button "Cancel"
    return "custom:" &amp; (text returned of r)
  end if
  return choice
end run
APPLESCRIPT
)
[ -n "$PICK" ] || exit 0

case "$PICK" in
  custom:*) TARGET="${PICK#custom:}"; mkdir -p "$DC" &amp;&amp; echo "Custom size..." &gt; "$PREFS" ;;
  *)        TARGET="${PICK%% - *}"; mkdir -p "$DC" &amp;&amp; echo "$PICK" &gt; "$PREFS" ;;
esac
OPTS=(--to jpg --target "$TARGET")
LABEL="under $TARGET"; DONE_VERB="compressed"

if [ $# -gt 5 ] || [ -d "$1" ]; then notify "Converting…" "This can take a moment."; fi

REPORT=$(/usr/bin/mktemp -t dconv)
RESULT=$(/bin/bash "$SCRIPT" "${OPTS[@]}" --out "$OUT" --report "$REPORT" "$@" 2&gt;&amp;1)
N=$(grep -c . "$REPORT")
SKIP=$(printf '%s\n' "$RESULT" | sed -n 's/^Done: .*converted, \([0-9]*\) skipped.*/\1/p')
FAIL=$(printf '%s\n' "$RESULT" | sed -n 's/^Done: .*skipped, \([0-9]*\) failed.*/\1/p')
SIZES=$(printf '%s\n' "$RESULT" | sed -n 's/^Total size: //p')
FIRST=$(head -1 "$REPORT")
rm -f "$REPORT"
[ "$N" = 1 ] &amp;&amp; WORD=image || WORD=images

if [ "$N" -gt 0 ]; then
  BODY="$SIZES"
  [ "${SKIP:-0}" -gt 0 ] &amp;&amp; BODY="$BODY · $SKIP already $LABEL"
  [ "${FAIL:-0}" -gt 0 ] &amp;&amp; BODY="$BODY · $FAIL couldn't be converted"
  OVER=$(printf '%s\n' "$RESULT" | sed -n 's/^Over target: //p')
  [ -n "$OVER" ] &amp;&amp; BODY="$BODY · $OVER couldn't get $LABEL"
  notify "$N $WORD $DONE_VERB" "$BODY"
  /usr/bin/open -R "$FIRST"
elif [ "${SKIP:-0}" -gt 0 ]; then
  rmdir "$OUT" 2&gt;/dev/null
  notify "Nothing to do" "Already $LABEL."
else
  rmdir "$OUT" 2&gt;/dev/null
  WHY=$(printf '%s\n' "$RESULT" | grep -E '^(Error:|✗)' | head -1 | sed -e 's/^Error: //' -e 's/^✗ //')
  alert "Couldn't convert: ${WHY:-unknown problem}"
fi
exit 0
</string>
					<key>CheckedForUserDefaultShell</key>
					<true/>
					<key>inputMethod</key>
					<integer>1</integer>
					<key>shell</key>
					<string>/bin/bash</string>
					<key>source</key>
					<string></string>
				</dict>
				<key>BundleIdentifier</key>
				<string>com.apple.RunShellScript</string>
				<key>CFBundleVersion</key>
				<string>2.0.3</string>
				<key>CanShowSelectedItemsWhenRun</key>
				<false/>
				<key>CanShowWhenRun</key>
				<true/>
				<key>Category</key>
				<array>
					<string>AMCategoryUtilities</string>
				</array>
				<key>Class Name</key>
				<string>RunShellScriptAction</string>
				<key>InputUUID</key>
				<string>AAD92698-029B-4E8D-8E69-6734ABE231DE</string>
				<key>Keywords</key>
				<array>
					<string>Shell</string>
					<string>Script</string>
					<string>Command</string>
					<string>Run</string>
					<string>Unix</string>
				</array>
				<key>OutputUUID</key>
				<string>B65F9ABB-C800-457B-B6FB-BF5F48A7FEBC</string>
				<key>UUID</key>
				<string>42242ADB-7E82-4E86-9CB0-5A2D5DE784A8</string>
				<key>UnlocalizedApplications</key>
				<array>
					<string>Automator</string>
				</array>
				<key>arguments</key>
				<dict>
					<key>0</key>
					<dict>
						<key>default value</key>
						<integer>0</integer>
						<key>name</key>
						<string>inputMethod</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>0</string>
					</dict>
					<key>1</key>
					<dict>
						<key>default value</key>
						<false/>
						<key>name</key>
						<string>CheckedForUserDefaultShell</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>1</string>
					</dict>
					<key>2</key>
					<dict>
						<key>default value</key>
						<string></string>
						<key>name</key>
						<string>source</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>2</string>
					</dict>
					<key>3</key>
					<dict>
						<key>default value</key>
						<string></string>
						<key>name</key>
						<string>COMMAND_STRING</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>3</string>
					</dict>
					<key>4</key>
					<dict>
						<key>default value</key>
						<string>/bin/sh</string>
						<key>name</key>
						<string>shell</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>4</string>
					</dict>
				</dict>
				<key>isViewVisible</key>
				<integer>1</integer>
				<key>location</key>
				<string>309.000000:253.000000</string>
				<key>nibPath</key>
				<string>/System/Library/Automator/Run Shell Script.action/Contents/Resources/Base.lproj/main.nib</string>
			</dict>
			<key>isViewVisible</key>
			<integer>1</integer>
		</dict>
	</array>
	<key>connectors</key>
	<dict/>
	<key>workflowMetaData</key>
	<dict>
		<key>applicationBundleID</key>
		<string>com.apple.finder</string>
		<key>applicationBundleIDsByPath</key>
		<dict>
			<key>/System/Library/CoreServices/Finder.app</key>
			<string>com.apple.finder</string>
		</dict>
		<key>applicationPath</key>
		<string>/System/Library/CoreServices/Finder.app</string>
		<key>applicationPaths</key>
		<array>
			<string>/System/Library/CoreServices/Finder.app</string>
		</array>
		<key>inputTypeIdentifier</key>
		<string>com.apple.Automator.fileSystemObject</string>
		<key>outputTypeIdentifier</key>
		<string>com.apple.Automator.nothing</string>
		<key>presentationMode</key>
		<integer>15</integer>
		<key>processesInput</key>
		<integer>0</integer>
		<key>serviceApplicationBundleID</key>
		<string>com.apple.finder</string>
		<key>serviceApplicationPath</key>
		<string>/System/Library/CoreServices/Finder.app</string>
		<key>serviceInputTypeIdentifier</key>
		<string>com.apple.Automator.fileSystemObject</string>
		<key>serviceOutputTypeIdentifier</key>
		<string>com.apple.Automator.nothing</string>
		<key>serviceProcessesInput</key>
		<integer>0</integer>
		<key>systemImageName</key>
		<string>NSActionTemplate</string>
		<key>useAutomaticInputType</key>
		<integer>0</integer>
		<key>workflowTypeIdentifier</key>
		<string>com.apple.Automator.servicesMenu</string>
	</dict>
</dict>
</plist>
DC_EOF_B297AF3E

rm -rf "$SVC/Convert & Resize….workflow"
mkdir -p "$SVC/Convert & Resize….workflow/Contents"
cat > "$SVC/Convert & Resize….workflow/Contents"/Info.plist <<'DC_EOF_4245D69B'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSServices</key>
	<array>
		<dict>
			<key>NSBackgroundColorName</key>
			<string>background</string>
			<key>NSIconName</key>
			<string>NSActionTemplate</string>
			<key>NSMenuItem</key>
			<dict>
				<key>default</key>
				<string>Convert &amp; Resize…</string>
			</dict>
			<key>NSMessage</key>
			<string>runWorkflowAsService</string>
			<key>NSRequiredContext</key>
			<dict>
				<key>NSApplicationIdentifier</key>
				<string>com.apple.finder</string>
			</dict>
			<key>NSSendFileTypes</key>
			<array>
				<string>public.image</string>
				<string>public.folder</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
DC_EOF_4245D69B
cat > "$SVC/Convert & Resize….workflow/Contents"/document.wflow <<'DC_EOF_115E114A'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AMApplicationBuild</key>
	<string>523</string>
	<key>AMApplicationVersion</key>
	<string>2.10</string>
	<key>AMDocumentVersion</key>
	<string>2</string>
	<key>actions</key>
	<array>
		<dict>
			<key>action</key>
			<dict>
				<key>AMAccepts</key>
				<dict>
					<key>Container</key>
					<string>List</string>
					<key>Optional</key>
					<true/>
					<key>Types</key>
					<array>
						<string>com.apple.cocoa.string</string>
					</array>
				</dict>
				<key>AMActionVersion</key>
				<string>2.0.3</string>
				<key>AMApplication</key>
				<array>
					<string>Automator</string>
				</array>
				<key>AMParameterProperties</key>
				<dict>
					<key>COMMAND_STRING</key>
					<dict/>
					<key>CheckedForUserDefaultShell</key>
					<dict/>
					<key>inputMethod</key>
					<dict/>
					<key>shell</key>
					<dict/>
					<key>source</key>
					<dict/>
				</dict>
				<key>AMProvides</key>
				<dict>
					<key>Container</key>
					<string>List</string>
					<key>Types</key>
					<array>
						<string>com.apple.cocoa.string</string>
					</array>
				</dict>
				<key>ActionBundlePath</key>
				<string>/System/Library/Automator/Run Shell Script.action</string>
				<key>ActionName</key>
				<string>Run Shell Script</string>
				<key>ActionParameters</key>
				<dict>
					<key>COMMAND_STRING</key>
					<string># Desktop Converter Quick Action
DC="$HOME/Library/Application Support/Desktop Converter"
SCRIPT="$DC/convert-images.sh"
[ $# -gt 0 ] || exit 0

notify() { /usr/bin/osascript -e 'on run argv' -e 'display notification (item 2 of argv) with title "Desktop Converter" subtitle (item 1 of argv)' -e 'end run' "$1" "$2" &gt;/dev/null 2&gt;&amp;1; }
alert() { /usr/bin/osascript -e 'on run argv' -e 'display alert "Desktop Converter" message (item 1 of argv) as warning' -e 'end run' "$1" &gt;/dev/null 2&gt;&amp;1; }

if [ -d "$1" ]; then OUT="$1/Converted"; else OUT="$(dirname "$1")/Converted"; fi
INFO=$(/bin/bash "$SCRIPT" --to jpg --info "$@" 2&gt;/dev/null)
if [ -z "$INFO" ]; then alert "There are no images in what you selected."; exit 0; fi
read COUNT TOTAL LARGEST &lt;&lt;INFOEOF
$INFO
INFOEOF
hs() { awk -v b="$1" 'BEGIN { if (b &gt;= 1048576) printf "%.1f MB", b / 1048576; else printf "%d KB", int(b / 1024 + 0.5) }'; }
if [ "$COUNT" = 1 ]; then SUMMARY="Selected: 1 image, $(hs "$TOTAL")"
else SUMMARY="Selected: $COUNT images, $(hs "$TOTAL") in total (largest $(hs "$LARGEST"))"; fi

PREFS="$DC/last-choice"
LAST_FMT=JPG; LAST_SIZE="Keep original size"
if [ -f "$PREFS" ]; then LAST_FMT=$(sed -n 1p "$PREFS"); LAST_SIZE=$(sed -n 2p "$PREFS"); fi
case "$LAST_FMT" in JPG|PNG|HEIC|PDF|TIFF) ;; *) LAST_FMT=JPG ;; esac
case "$LAST_SIZE" in "Keep original size"|"Large - 2560 px"|"Medium - 1600 px"|"Small - 1024 px"|"Thumbnail - 400 px") ;; *) LAST_SIZE="Keep original size" ;; esac

FMT=$(/usr/bin/osascript - "$LAST_FMT" "$SUMMARY" &lt;&lt;'APPLESCRIPT'
on run argv
  activate
  set picked to choose from list {"JPG", "PNG", "HEIC", "PDF", "TIFF"} with title "Desktop Converter" with prompt (item 2 of argv) &amp; return &amp; return &amp; "Convert to:" default items {item 1 of argv} OK button name "Next" cancel button name "Cancel"
  if picked is false then return ""
  return item 1 of picked
end run
APPLESCRIPT
)
[ -n "$FMT" ] || exit 0

SIZE=$(/usr/bin/osascript - "$LAST_SIZE" "$SUMMARY" &lt;&lt;'APPLESCRIPT'
on run argv
  activate
  set picked to choose from list {"Keep original size", "Large - 2560 px", "Medium - 1600 px", "Small - 1024 px", "Thumbnail - 400 px"} with title "Desktop Converter" with prompt (item 2 of argv) &amp; return &amp; return &amp; "Size (longest side):" default items {item 1 of argv} OK button name "Convert" cancel button name "Cancel"
  if picked is false then return ""
  return item 1 of picked
end run
APPLESCRIPT
)
[ -n "$SIZE" ] || exit 0

mkdir -p "$DC" &amp;&amp; printf '%s\n%s\n' "$FMT" "$SIZE" &gt; "$PREFS"
case "$SIZE" in Large*) MAX=2560 ;; Medium*) MAX=1600 ;; Small*) MAX=1024 ;; Thumbnail*) MAX=400 ;; *) MAX="" ;; esac
LOWER=$(printf '%s' "$FMT" | tr '[:upper:]' '[:lower:]')
OPTS=(--to "$LOWER")
[ -n "$MAX" ] &amp;&amp; OPTS+=(--max "$MAX") || OPTS+=(--skip-same)
case "$LOWER" in jpg|heic) OPTS+=(--quality 85) ;; esac
LABEL="$FMT"; DONE_VERB="converted to $FMT"

if [ $# -gt 5 ] || [ -d "$1" ]; then notify "Converting…" "This can take a moment."; fi

REPORT=$(/usr/bin/mktemp -t dconv)
RESULT=$(/bin/bash "$SCRIPT" "${OPTS[@]}" --out "$OUT" --report "$REPORT" "$@" 2&gt;&amp;1)
N=$(grep -c . "$REPORT")
SKIP=$(printf '%s\n' "$RESULT" | sed -n 's/^Done: .*converted, \([0-9]*\) skipped.*/\1/p')
FAIL=$(printf '%s\n' "$RESULT" | sed -n 's/^Done: .*skipped, \([0-9]*\) failed.*/\1/p')
SIZES=$(printf '%s\n' "$RESULT" | sed -n 's/^Total size: //p')
FIRST=$(head -1 "$REPORT")
rm -f "$REPORT"
[ "$N" = 1 ] &amp;&amp; WORD=image || WORD=images

if [ "$N" -gt 0 ]; then
  BODY="$SIZES"
  [ "${SKIP:-0}" -gt 0 ] &amp;&amp; BODY="$BODY · $SKIP already $LABEL"
  [ "${FAIL:-0}" -gt 0 ] &amp;&amp; BODY="$BODY · $FAIL couldn't be converted"
  OVER=$(printf '%s\n' "$RESULT" | sed -n 's/^Over target: //p')
  [ -n "$OVER" ] &amp;&amp; BODY="$BODY · $OVER couldn't get $LABEL"
  notify "$N $WORD $DONE_VERB" "$BODY"
  /usr/bin/open -R "$FIRST"
elif [ "${SKIP:-0}" -gt 0 ]; then
  rmdir "$OUT" 2&gt;/dev/null
  notify "Nothing to do" "Already $LABEL."
else
  rmdir "$OUT" 2&gt;/dev/null
  WHY=$(printf '%s\n' "$RESULT" | grep -E '^(Error:|✗)' | head -1 | sed -e 's/^Error: //' -e 's/^✗ //')
  alert "Couldn't convert: ${WHY:-unknown problem}"
fi
exit 0
</string>
					<key>CheckedForUserDefaultShell</key>
					<true/>
					<key>inputMethod</key>
					<integer>1</integer>
					<key>shell</key>
					<string>/bin/bash</string>
					<key>source</key>
					<string></string>
				</dict>
				<key>BundleIdentifier</key>
				<string>com.apple.RunShellScript</string>
				<key>CFBundleVersion</key>
				<string>2.0.3</string>
				<key>CanShowSelectedItemsWhenRun</key>
				<false/>
				<key>CanShowWhenRun</key>
				<true/>
				<key>Category</key>
				<array>
					<string>AMCategoryUtilities</string>
				</array>
				<key>Class Name</key>
				<string>RunShellScriptAction</string>
				<key>InputUUID</key>
				<string>88F45E7E-B44E-4B98-AB82-7CFFC286B76C</string>
				<key>Keywords</key>
				<array>
					<string>Shell</string>
					<string>Script</string>
					<string>Command</string>
					<string>Run</string>
					<string>Unix</string>
				</array>
				<key>OutputUUID</key>
				<string>3668F380-2D40-4E30-8362-85BC527A11FC</string>
				<key>UUID</key>
				<string>3622C5D4-7CB1-4A9D-80C7-7D1E6900D778</string>
				<key>UnlocalizedApplications</key>
				<array>
					<string>Automator</string>
				</array>
				<key>arguments</key>
				<dict>
					<key>0</key>
					<dict>
						<key>default value</key>
						<integer>0</integer>
						<key>name</key>
						<string>inputMethod</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>0</string>
					</dict>
					<key>1</key>
					<dict>
						<key>default value</key>
						<false/>
						<key>name</key>
						<string>CheckedForUserDefaultShell</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>1</string>
					</dict>
					<key>2</key>
					<dict>
						<key>default value</key>
						<string></string>
						<key>name</key>
						<string>source</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>2</string>
					</dict>
					<key>3</key>
					<dict>
						<key>default value</key>
						<string></string>
						<key>name</key>
						<string>COMMAND_STRING</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>3</string>
					</dict>
					<key>4</key>
					<dict>
						<key>default value</key>
						<string>/bin/sh</string>
						<key>name</key>
						<string>shell</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>4</string>
					</dict>
				</dict>
				<key>isViewVisible</key>
				<integer>1</integer>
				<key>location</key>
				<string>309.000000:253.000000</string>
				<key>nibPath</key>
				<string>/System/Library/Automator/Run Shell Script.action/Contents/Resources/Base.lproj/main.nib</string>
			</dict>
			<key>isViewVisible</key>
			<integer>1</integer>
		</dict>
	</array>
	<key>connectors</key>
	<dict/>
	<key>workflowMetaData</key>
	<dict>
		<key>applicationBundleID</key>
		<string>com.apple.finder</string>
		<key>applicationBundleIDsByPath</key>
		<dict>
			<key>/System/Library/CoreServices/Finder.app</key>
			<string>com.apple.finder</string>
		</dict>
		<key>applicationPath</key>
		<string>/System/Library/CoreServices/Finder.app</string>
		<key>applicationPaths</key>
		<array>
			<string>/System/Library/CoreServices/Finder.app</string>
		</array>
		<key>inputTypeIdentifier</key>
		<string>com.apple.Automator.fileSystemObject</string>
		<key>outputTypeIdentifier</key>
		<string>com.apple.Automator.nothing</string>
		<key>presentationMode</key>
		<integer>15</integer>
		<key>processesInput</key>
		<integer>0</integer>
		<key>serviceApplicationBundleID</key>
		<string>com.apple.finder</string>
		<key>serviceApplicationPath</key>
		<string>/System/Library/CoreServices/Finder.app</string>
		<key>serviceInputTypeIdentifier</key>
		<string>com.apple.Automator.fileSystemObject</string>
		<key>serviceOutputTypeIdentifier</key>
		<string>com.apple.Automator.nothing</string>
		<key>serviceProcessesInput</key>
		<integer>0</integer>
		<key>systemImageName</key>
		<string>NSActionTemplate</string>
		<key>useAutomaticInputType</key>
		<integer>0</integer>
		<key>workflowTypeIdentifier</key>
		<string>com.apple.Automator.servicesMenu</string>
	</dict>
</dict>
</plist>
DC_EOF_115E114A

xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
for n in "${NAMES[@]}"; do xattr -dr com.apple.quarantine "$SVC/$n.workflow" 2>/dev/null || true; done
/System/Library/CoreServices/pbs -update 2>/dev/null || true

echo "✔ Installed 3 Quick Actions: Convert to JPG, Compress to Size…, Convert & Resize…"
echo
echo "  Turn them on once: System Settings > General > Login Items & Extensions >"
echo "  Extensions > Finder, or right-click an image > Quick Actions > Customise…"
echo
echo "  Then right-click any image or folder in Finder > Quick Actions."
echo "  Results go into a 'Converted' folder next to your images. Originals are never changed."
