import plistlib, uuid, sys
root = "/home/user/desktop-converter"
conv = open(f"{root}/scripts/convert-images.sh").read()

COMMON_HEAD = r'''# Desktop Converter Quick Action
DC="$HOME/Library/Application Support/Desktop Converter"
[ $# -gt 0 ] || exit 0

notify() { /usr/bin/osascript -e 'on run argv' -e 'display notification (item 2 of argv) with title "Desktop Converter" subtitle (item 1 of argv)' -e 'end run' "$1" "$2" >/dev/null 2>&1; }
alert() { /usr/bin/osascript -e 'on run argv' -e 'display alert "Desktop Converter" message (item 1 of argv) as warning' -e 'end run' "$1" >/dev/null 2>&1; }

# New files go right next to the originals (inside the folder, if a folder was picked).
if [ -d "$1" ]; then OUT="$1"; else OUT="$(dirname "$1")"; fi
'''

COMMON_RUN = r'''
if [ $# -gt 5 ] || [ -d "$1" ]; then notify "Converting…" "This can take a moment."; fi

REPORT=$(/usr/bin/mktemp -t dconv)
RESULT=$(/bin/bash "$SCRIPT" "${OPTS[@]}" --out "$OUT" --report "$REPORT" "$@" 2>&1)
N=$(grep -c . "$REPORT")
SKIP=$(printf '%s\n' "$RESULT" | sed -n 's/^Done: .*converted, \([0-9]*\) skipped.*/\1/p')
FAIL=$(printf '%s\n' "$RESULT" | sed -n 's/^Done: .*skipped, \([0-9]*\) failed.*/\1/p')
SIZES=$(printf '%s\n' "$RESULT" | sed -n 's/^Total size: //p')
FIRST=$(head -1 "$REPORT")
rm -f "$REPORT"
[ "$N" = 1 ] && WORD=image || WORD=images

if [ "$N" -gt 0 ]; then
  BODY="$SIZES"
  [ "${SKIP:-0}" -gt 0 ] && BODY="$BODY · $SKIP already $LABEL"
  [ "${FAIL:-0}" -gt 0 ] && BODY="$BODY · $FAIL couldn't be converted"
  OVER=$(printf '%s\n' "$RESULT" | sed -n 's/^Over target: //p')
  [ -n "$OVER" ] && BODY="$BODY · $OVER couldn't get $LABEL"
  notify "$N $WORD $DONE_VERB" "$BODY"
  /usr/bin/open -R "$FIRST"
elif [ "${SKIP:-0}" -gt 0 ]; then
  notify "Nothing to do" "Already $LABEL."
else
  WHY=$(printf '%s\n' "$RESULT" | grep -E '^(Error:|✗)' | head -1 | sed -e 's/^Error: //' -e 's/^✗ //')
  alert "Couldn't convert: ${WHY:-unknown problem}"
fi
exit 0
'''

SUMMARY = r'''INFO=$(/bin/bash "$SCRIPT" --to jpg --info "$@" 2>/dev/null)
if [ -z "$INFO" ]; then alert "There are no images in what you selected."; exit 0; fi
read COUNT TOTAL LARGEST <<INFOEOF
$INFO
INFOEOF
hs() { awk -v b="$1" 'BEGIN { if (b >= 1048576) printf "%.1f MB", b / 1048576; else printf "%d KB", int(b / 1024 + 0.5) }'; }
if [ "$COUNT" = 1 ]; then SUMMARY="Selected: 1 image, $(hs "$TOTAL")"
else SUMMARY="Selected: $COUNT images, $(hs "$TOTAL") in total (largest $(hs "$LARGEST"))"; fi

'''

DIALOG = SUMMARY + r'''PREFS="$DC/last-choice"
LAST_FMT=JPG; LAST_SIZE="Keep original size"
if [ -f "$PREFS" ]; then LAST_FMT=$(sed -n 1p "$PREFS"); LAST_SIZE=$(sed -n 2p "$PREFS"); fi
case "$LAST_FMT" in JPG|PNG|HEIC|PDF|TIFF) ;; *) LAST_FMT=JPG ;; esac
case "$LAST_SIZE" in "Keep original size"|"Large - 2560 px"|"Medium - 1600 px"|"Small - 1024 px"|"Thumbnail - 400 px") ;; *) LAST_SIZE="Keep original size" ;; esac

FMT=$(/usr/bin/osascript - "$LAST_FMT" "$SUMMARY" <<'APPLESCRIPT'
on run argv
  activate
  set picked to choose from list {"JPG", "PNG", "HEIC", "PDF", "TIFF"} with title "Desktop Converter" with prompt (item 2 of argv) & return & return & "Convert to:" default items {item 1 of argv} OK button name "Next" cancel button name "Cancel"
  if picked is false then return ""
  return item 1 of picked
end run
APPLESCRIPT
)
[ -n "$FMT" ] || exit 0

SIZE=$(/usr/bin/osascript - "$LAST_SIZE" "$SUMMARY" <<'APPLESCRIPT'
on run argv
  activate
  set picked to choose from list {"Keep original size", "Large - 2560 px", "Medium - 1600 px", "Small - 1024 px", "Thumbnail - 400 px"} with title "Desktop Converter" with prompt (item 2 of argv) & return & return & "Size (longest side):" default items {item 1 of argv} OK button name "Convert" cancel button name "Cancel"
  if picked is false then return ""
  return item 1 of picked
end run
APPLESCRIPT
)
[ -n "$SIZE" ] || exit 0

mkdir -p "$DC" && printf '%s\n%s\n' "$FMT" "$SIZE" > "$PREFS"
case "$SIZE" in Large*) MAX=2560 ;; Medium*) MAX=1600 ;; Small*) MAX=1024 ;; Thumbnail*) MAX=400 ;; *) MAX="" ;; esac
LOWER=$(printf '%s' "$FMT" | tr '[:upper:]' '[:lower:]')
OPTS=(--to "$LOWER")
[ -n "$MAX" ] && OPTS+=(--max "$MAX" --suffix " (${MAX}px)") || OPTS+=(--skip-same)
case "$LOWER" in jpg|heic) OPTS+=(--quality 85) ;; esac
LABEL="$FMT"; DONE_VERB="converted to $FMT"
'''

COMPRESS = SUMMARY + r'''PREFS="$DC/last-target"
LAST=$(cat "$PREFS" 2>/dev/null)
case "$LAST" in "2 MB - good for email"|"1 MB"|"500 KB"|"200 KB - good for web forms"|"100 KB"|"Custom size...") ;; *) LAST="2 MB - good for email" ;; esac

PICK=$(/usr/bin/osascript - "$LAST" "$SUMMARY" 2>/dev/null <<'APPLESCRIPT'
on run argv
  activate
  set picked to choose from list {"2 MB - good for email", "1 MB", "500 KB", "200 KB - good for web forms", "100 KB", "Custom size..."} with title "Compress to Size" with prompt (item 2 of argv) & return & return & "Make each image smaller than:" default items {item 1 of argv} OK button name "Compress" cancel button name "Cancel"
  if picked is false then return ""
  set choice to item 1 of picked
  if choice is "Custom size..." then
    set r to display dialog "Make each image smaller than:" & return & "(for example 300 KB or 1.5 MB)" default answer "300 KB" with title "Compress to Size" buttons {"Cancel", "Compress"} default button "Compress" cancel button "Cancel"
    return "custom:" & (text returned of r)
  end if
  return choice
end run
APPLESCRIPT
)
[ -n "$PICK" ] || exit 0

case "$PICK" in
  custom:*) TARGET="${PICK#custom:}"; mkdir -p "$DC" && echo "Custom size..." > "$PREFS" ;;
  *)        TARGET="${PICK%% - *}"; mkdir -p "$DC" && echo "$PICK" > "$PREFS" ;;
esac
OPTS=(--to jpg --target "$TARGET" --suffix " (compressed)")
LABEL="under $TARGET"; DONE_VERB="compressed"
'''

ACTIONS = [
  ("Convert to JPG",       'OPTS=(--to jpg --quality 90 --skip-same); LABEL=JPG; DONE_VERB="converted to JPG"\n'),
  ("Compress to Size…",    COMPRESS),
  ("Convert & Resize…",    DIALOG),
]
OLD_NAMES = ["Convert to PNG", "Make PDF"]

EMBED_EOF = "DC_CONVERTER_EOF"
assert EMBED_EOF not in conv

def action_script(setup):
    # Each Quick Action carries its own copy of the converter, so a .workflow file
    # works on its own: double-click to install, nothing else needed.
    embed = ('SCRIPT=$(/usr/bin/mktemp -t dconv-script)\n'
             'trap \'rm -f "$SCRIPT"\' EXIT\n'
             f"cat > \"$SCRIPT\" <<'{EMBED_EOF}'\n{conv}{EMBED_EOF}\n\n")
    return COMMON_HEAD + embed + setup + COMMON_RUN

def info_plist(name):
    return plistlib.dumps({"NSServices": [{
        "NSBackgroundColorName": "background",
        "NSIconName": "NSActionTemplate",
        "NSMenuItem": {"default": name},
        "NSMessage": "runWorkflowAsService",
        "NSRequiredContext": {"NSApplicationIdentifier": "com.apple.finder"},
        "NSSendFileTypes": ["public.image", "public.folder"],
    }]}).decode()

def wflow(opts):
    u = lambda: str(uuid.uuid4()).upper()
    return plistlib.dumps({
      "AMApplicationBuild": "523", "AMApplicationVersion": "2.10", "AMDocumentVersion": "2",
      "actions": [{"action": {
        "AMAccepts": {"Container": "List", "Optional": True, "Types": ["com.apple.cocoa.string"]},
        "AMActionVersion": "2.0.3", "AMApplication": ["Automator"],
        "AMParameterProperties": {"COMMAND_STRING": {}, "CheckedForUserDefaultShell": {},
                                  "inputMethod": {}, "shell": {}, "source": {}},
        "AMProvides": {"Container": "List", "Types": ["com.apple.cocoa.string"]},
        "ActionBundlePath": "/System/Library/Automator/Run Shell Script.action",
        "ActionName": "Run Shell Script",
        "ActionParameters": {"COMMAND_STRING": action_script(opts), "CheckedForUserDefaultShell": True,
                             "inputMethod": 1, "shell": "/bin/bash", "source": ""},
        "BundleIdentifier": "com.apple.RunShellScript", "CFBundleVersion": "2.0.3",
        "CanShowSelectedItemsWhenRun": False, "CanShowWhenRun": True,
        "Category": ["AMCategoryUtilities"], "Class Name": "RunShellScriptAction",
        "InputUUID": u(), "Keywords": ["Shell", "Script", "Command", "Run", "Unix"],
        "OutputUUID": u(), "UUID": u(), "UnlocalizedApplications": ["Automator"],
        "arguments": {
          "0": {"default value": 0, "name": "inputMethod", "required": "0", "type": "0", "uuid": "0"},
          "1": {"default value": False, "name": "CheckedForUserDefaultShell", "required": "0", "type": "0", "uuid": "1"},
          "2": {"default value": "", "name": "source", "required": "0", "type": "0", "uuid": "2"},
          "3": {"default value": "", "name": "COMMAND_STRING", "required": "0", "type": "0", "uuid": "3"},
          "4": {"default value": "/bin/sh", "name": "shell", "required": "0", "type": "0", "uuid": "4"}},
        "isViewVisible": 1, "location": "309.000000:253.000000",
        "nibPath": "/System/Library/Automator/Run Shell Script.action/Contents/Resources/Base.lproj/main.nib"},
        "isViewVisible": 1}],
      "connectors": {},
      "workflowMetaData": {
        "applicationBundleID": "com.apple.finder",
        "applicationBundleIDsByPath": {"/System/Library/CoreServices/Finder.app": "com.apple.finder"},
        "applicationPath": "/System/Library/CoreServices/Finder.app",
        "applicationPaths": ["/System/Library/CoreServices/Finder.app"],
        "inputTypeIdentifier": "com.apple.Automator.fileSystemObject",
        "outputTypeIdentifier": "com.apple.Automator.nothing",
        "presentationMode": 15, "processesInput": 0,
        "serviceApplicationBundleID": "com.apple.finder",
        "serviceApplicationPath": "/System/Library/CoreServices/Finder.app",
        "serviceInputTypeIdentifier": "com.apple.Automator.fileSystemObject",
        "serviceOutputTypeIdentifier": "com.apple.Automator.nothing",
        "serviceProcessesInput": 0, "systemImageName": "NSActionTemplate",
        "useAutomaticInputType": 0,
        "workflowTypeIdentifier": "com.apple.Automator.servicesMenu"},
    }).decode()

def heredoc(path, text):
    d = "DC_EOF_" + uuid.uuid4().hex[:8].upper()
    assert d not in text
    return f"cat > {path} <<'{d}'\n{text}{'' if text.endswith(chr(10)) else chr(10)}{d}\n"

out = ['''#!/bin/bash
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
''']
for name, opts in ACTIONS:
    w = f'"$SVC/{name}.workflow/Contents"'
    out.append(f'rm -rf "$SVC/{name}.workflow"\nmkdir -p {w}\n')
    out.append(heredoc(f'{w}/Info.plist', info_plist(name)))
    out.append(heredoc(f'{w}/document.wflow', wflow(opts)))
    out.append('\n')
out.append('''xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
for n in "${NAMES[@]}"; do xattr -dr com.apple.quarantine "$SVC/$n.workflow" 2>/dev/null || true; done
/System/Library/CoreServices/pbs -update 2>/dev/null || true

echo "✔ Installed 3 Quick Actions: Convert to JPG, Compress to Size…, Convert & Resize…"
echo
echo "  Turn them on once: System Settings > General > Login Items & Extensions >"
echo "  Extensions > Finder, or right-click an image > Quick Actions > Customise…"
echo
echo "  Then right-click any image or folder in Finder > Quick Actions."
echo "  New files are saved next to your images. Originals are never changed."
''')
open(f"{root}/quick-actions/install-quick-actions.sh", "w").write("".join(out))


# ---------------------------------------------------------------------------
# Shareable zip: double-click installers, no Terminal needed.
import os, zipfile, shutil
dist = f"{root}/dist"
pkg = f"{dist}/Desktop Converter"
shutil.rmtree(dist, ignore_errors=True)
for name, opts in ACTIONS:
    c = f"{pkg}/{name}.workflow/Contents"
    os.makedirs(c)
    open(f"{c}/Info.plist", "w").write(info_plist(name))
    open(f"{c}/document.wflow", "w").write(wflow(opts))
open(f"{pkg}/How to Install.html", "w").write(open(f"{root}/quick-actions/how-to-install.html").read())
zpath = f"{dist}/Desktop-Converter.zip"
with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
    for dirpath, dirs, files in os.walk(pkg):
        dirs.sort()
        rel = os.path.relpath(dirpath, dist)
        z.write(dirpath, rel + "/")
        for f in sorted(files):
            z.write(f"{dirpath}/{f}", f"{rel}/{f}")
print("built", zpath)
