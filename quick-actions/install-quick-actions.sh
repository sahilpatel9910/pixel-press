#!/bin/bash
# Desktop Converter: installs Finder Quick Actions for images.
# Run once with:  bash install-quick-actions.sh
# Then right-click any image in Finder > Quick Actions.
# To remove them later:  bash install-quick-actions.sh --uninstall
set -e

[ "$(uname)" = "Darwin" ] || { echo "This installer is for macOS."; exit 1; }

APP="$HOME/Library/Application Support/Desktop Converter"
SVC="$HOME/Library/Services"
NAMES=("Convert to JPG" "Convert to PNG" "Compress for Email" "Make PDF")

if [ "${1:-}" = "--uninstall" ]; then
  for n in "${NAMES[@]}"; do rm -rf "$SVC/$n.workflow"; done
  rm -rf "$APP"
  /System/Library/CoreServices/pbs -update 2>/dev/null || true
  echo "Removed the Desktop Converter Quick Actions."
  exit 0
fi

mkdir -p "$APP" "$SVC"
cat > "$APP/convert-images.sh" <<'DC_EOF_5EFEBF49'
#!/bin/bash
# Desktop Converter: convert, resize and compress images.
# Uses macOS's built-in `sips`. WebP output needs `cwebp` or ImageMagick (`magick`).
# Written for the bash 3.2 that ships with macOS.
#
# Usage:
#   convert-images.sh --to jpg|png|heic|tiff|gif|bmp|pdf|webp [--max PIXELS] [--quality 1-100]
#                     [--out DIR] FILE_OR_FOLDER...
#
# Originals are never modified. Results go to --out (default ~/Desktop/Converted).
# An existing file is never overwritten: "photo.jpg" becomes "photo-1.jpg", and so on.

set -u

TO=""
MAX=""
QUALITY=""
OUT="$HOME/Desktop/Converted"
INPUTS=()

die() { echo "Error: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --to)      TO="${2:-}"; shift 2 ;;
    --max)     MAX="${2:-}"; shift 2 ;;
    --quality) QUALITY="${2:-}"; shift 2 ;;
    --out)     OUT="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
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

ok=0; failed=0; before_total=0; after_total=0
TMPDIR_CONV=$(mktemp -d) || die "can't create a temporary folder"
trap 'rm -rf "$TMPDIR_CONV"' EXIT

for f in "${FILES[@]}"; do
  name=$(basename "$f")
  stem="${name%.*}"
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
    ok=$((ok + 1))
  else
    rm -f "$dest"
    echo "✗ $name: could not convert (not an image, or format not supported)" >&2
    failed=$((failed + 1))
  fi
done

echo
echo "Done: $ok converted, $failed failed. Saved to: $OUT"
[ $ok -gt 0 ] && echo "Total size: $(human "$before_total") → $(human "$after_total")"
[ $ok -gt 0 ] || exit 1
exit 0
DC_EOF_5EFEBF49
chmod +x "$APP/convert-images.sh"

rm -rf "$SVC/Convert to JPG.workflow"
mkdir -p "$SVC/Convert to JPG.workflow/Contents"
cat > "$SVC/Convert to JPG.workflow/Contents"/Info.plist <<'DC_EOF_996E810A'
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
			</array>
		</dict>
	</array>
</dict>
</plist>
DC_EOF_996E810A
cat > "$SVC/Convert to JPG.workflow/Contents"/document.wflow <<'DC_EOF_A5E16B6F'
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
SCRIPT="$HOME/Library/Application Support/Desktop Converter/convert-images.sh"
[ $# -gt 0 ] || exit 0
OUT="$(dirname "$1")/Converted"
RESULT=$(/bin/bash "$SCRIPT" --to jpg --quality 90 --out "$OUT" "$@" 2&gt;&amp;1)
STATUS=$?
MSG=$(printf '%s\n' "$RESULT" | grep -E '^(Done:|Error:)' | head -1 | sed 's/ Saved to:.*//')
[ -n "$MSG" ] || MSG="Something went wrong."
/usr/bin/osascript -e 'on run argv' -e 'display notification (item 1 of argv) with title "Desktop Converter"' -e 'end run' "$MSG"
[ $STATUS -eq 0 ] &amp;&amp; /usr/bin/open "$OUT"
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
				<string>4392864D-D3BB-4322-B87D-664371D15113</string>
				<key>Keywords</key>
				<array>
					<string>Shell</string>
					<string>Script</string>
					<string>Command</string>
					<string>Run</string>
					<string>Unix</string>
				</array>
				<key>OutputUUID</key>
				<string>8CAFD4D2-DF3B-470F-9414-1436A7BD4BF3</string>
				<key>UUID</key>
				<string>88D184A7-3CDF-499C-BDE3-BD991CCE54DA</string>
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
		<string>com.apple.Automator.fileSystemObject.image</string>
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
		<string>com.apple.Automator.fileSystemObject.image</string>
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
DC_EOF_A5E16B6F

rm -rf "$SVC/Convert to PNG.workflow"
mkdir -p "$SVC/Convert to PNG.workflow/Contents"
cat > "$SVC/Convert to PNG.workflow/Contents"/Info.plist <<'DC_EOF_50514100'
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
				<string>Convert to PNG</string>
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
			</array>
		</dict>
	</array>
</dict>
</plist>
DC_EOF_50514100
cat > "$SVC/Convert to PNG.workflow/Contents"/document.wflow <<'DC_EOF_DFB3DB4B'
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
SCRIPT="$HOME/Library/Application Support/Desktop Converter/convert-images.sh"
[ $# -gt 0 ] || exit 0
OUT="$(dirname "$1")/Converted"
RESULT=$(/bin/bash "$SCRIPT" --to png --out "$OUT" "$@" 2&gt;&amp;1)
STATUS=$?
MSG=$(printf '%s\n' "$RESULT" | grep -E '^(Done:|Error:)' | head -1 | sed 's/ Saved to:.*//')
[ -n "$MSG" ] || MSG="Something went wrong."
/usr/bin/osascript -e 'on run argv' -e 'display notification (item 1 of argv) with title "Desktop Converter"' -e 'end run' "$MSG"
[ $STATUS -eq 0 ] &amp;&amp; /usr/bin/open "$OUT"
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
				<string>C8299217-6F04-4AA5-800A-FCD13186B3B8</string>
				<key>Keywords</key>
				<array>
					<string>Shell</string>
					<string>Script</string>
					<string>Command</string>
					<string>Run</string>
					<string>Unix</string>
				</array>
				<key>OutputUUID</key>
				<string>13B6C0E7-9B59-492D-AC8C-7B40AC55727A</string>
				<key>UUID</key>
				<string>D3EFA464-5E42-4605-8526-64A3CD0DC36D</string>
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
		<string>com.apple.Automator.fileSystemObject.image</string>
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
		<string>com.apple.Automator.fileSystemObject.image</string>
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
DC_EOF_DFB3DB4B

rm -rf "$SVC/Compress for Email.workflow"
mkdir -p "$SVC/Compress for Email.workflow/Contents"
cat > "$SVC/Compress for Email.workflow/Contents"/Info.plist <<'DC_EOF_06A73D5E'
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
				<string>Compress for Email</string>
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
			</array>
		</dict>
	</array>
</dict>
</plist>
DC_EOF_06A73D5E
cat > "$SVC/Compress for Email.workflow/Contents"/document.wflow <<'DC_EOF_C75E3325'
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
SCRIPT="$HOME/Library/Application Support/Desktop Converter/convert-images.sh"
[ $# -gt 0 ] || exit 0
OUT="$(dirname "$1")/Converted"
RESULT=$(/bin/bash "$SCRIPT" --to jpg --max 2000 --quality 75 --out "$OUT" "$@" 2&gt;&amp;1)
STATUS=$?
MSG=$(printf '%s\n' "$RESULT" | grep -E '^(Done:|Error:)' | head -1 | sed 's/ Saved to:.*//')
[ -n "$MSG" ] || MSG="Something went wrong."
/usr/bin/osascript -e 'on run argv' -e 'display notification (item 1 of argv) with title "Desktop Converter"' -e 'end run' "$MSG"
[ $STATUS -eq 0 ] &amp;&amp; /usr/bin/open "$OUT"
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
				<string>92CF7C8A-5A73-4243-A442-AE416BF54F7B</string>
				<key>Keywords</key>
				<array>
					<string>Shell</string>
					<string>Script</string>
					<string>Command</string>
					<string>Run</string>
					<string>Unix</string>
				</array>
				<key>OutputUUID</key>
				<string>D7B8027E-F7AC-4458-857D-60D2CD43BD34</string>
				<key>UUID</key>
				<string>0BDA3522-165D-4BED-9F1E-25C4FECF6D01</string>
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
		<string>com.apple.Automator.fileSystemObject.image</string>
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
		<string>com.apple.Automator.fileSystemObject.image</string>
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
DC_EOF_C75E3325

rm -rf "$SVC/Make PDF.workflow"
mkdir -p "$SVC/Make PDF.workflow/Contents"
cat > "$SVC/Make PDF.workflow/Contents"/Info.plist <<'DC_EOF_B432AAAF'
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
				<string>Make PDF</string>
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
			</array>
		</dict>
	</array>
</dict>
</plist>
DC_EOF_B432AAAF
cat > "$SVC/Make PDF.workflow/Contents"/document.wflow <<'DC_EOF_9272000C'
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
SCRIPT="$HOME/Library/Application Support/Desktop Converter/convert-images.sh"
[ $# -gt 0 ] || exit 0
OUT="$(dirname "$1")/Converted"
RESULT=$(/bin/bash "$SCRIPT" --to pdf --out "$OUT" "$@" 2&gt;&amp;1)
STATUS=$?
MSG=$(printf '%s\n' "$RESULT" | grep -E '^(Done:|Error:)' | head -1 | sed 's/ Saved to:.*//')
[ -n "$MSG" ] || MSG="Something went wrong."
/usr/bin/osascript -e 'on run argv' -e 'display notification (item 1 of argv) with title "Desktop Converter"' -e 'end run' "$MSG"
[ $STATUS -eq 0 ] &amp;&amp; /usr/bin/open "$OUT"
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
				<string>119BF86C-06EA-4684-91A3-0AB2FB4D5709</string>
				<key>Keywords</key>
				<array>
					<string>Shell</string>
					<string>Script</string>
					<string>Command</string>
					<string>Run</string>
					<string>Unix</string>
				</array>
				<key>OutputUUID</key>
				<string>21FAE4DA-F229-43B6-B2B7-5F13E47CC8F7</string>
				<key>UUID</key>
				<string>4CCC5CE8-7059-447B-9860-0C047B0E7B59</string>
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
		<string>com.apple.Automator.fileSystemObject.image</string>
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
		<string>com.apple.Automator.fileSystemObject.image</string>
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
DC_EOF_9272000C

xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
for n in "${NAMES[@]}"; do xattr -dr com.apple.quarantine "$SVC/$n.workflow" 2>/dev/null || true; done
/System/Library/CoreServices/pbs -update 2>/dev/null || true

echo "✔ Installed 4 Quick Actions: Convert to JPG, Convert to PNG, Compress for Email, Make PDF"
echo "  Right-click any image in Finder > Quick Actions."
echo "  Results go into a 'Converted' folder next to your images. Originals are never changed."
