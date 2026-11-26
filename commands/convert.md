---
description: Convert, resize or compress images (e.g. /convert ~/Desktop/*.heic jpg)
argument-hint: <files or folder> <format> [max pixels | under SIZE]
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/convert-images.sh:*), Bash(ls:*)
---

Convert images for the user with the Desktop Converter script. Their request: $ARGUMENTS

1. Work out the files, the target format and any size or quality wishes from the request.
   - Expand `~` and wildcards. If they named no files, list the image files on `~/Desktop` and ask which ones.
   - "small", "for email" or "compress" means `--to jpg --target 2MB` unless they said otherwise.
   - A size like "under 500 KB" means `--to jpg --target 500KB`.
   - "for web" means `--to jpg --max 1600 --quality 80` (or `webp` if they asked for it).
2. If more than 20 files would be converted, say how many and ask before going on.
3. Run:
   `bash ${CLAUDE_PLUGIN_ROOT}/scripts/convert-images.sh --to FORMAT [--max PIXELS] [--quality N] [--target SIZE] [--out DIR] FILES...`
4. Tell the user in a line or two what was converted, the size saved and where the files are
   (next to the originals: pass `--out` with their folder). If something failed, say which file and why, and how to fix it.

Never delete, move or overwrite the user's original files.
