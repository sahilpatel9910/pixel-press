---
description: Convert, resize or compress images (e.g. /convert ~/Desktop/*.heic jpg)
argument-hint: <files or folder> <format> [max size] [quality]
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/convert-images.sh:*), Bash(ls:*)
---

Convert images for the user with the Desktop Converter script. Their request: $ARGUMENTS

1. Work out the files, the target format and any size or quality wishes from the request.
   - Expand `~` and wildcards. If they named no files, list the image files on `~/Desktop` and ask which ones.
   - "small", "for email" or "compress" means `--to jpg --max 2000 --quality 75` unless they said otherwise.
   - "for web" means `--to jpg --max 1600 --quality 80` (or `webp` if they asked for it).
2. If more than 20 files would be converted, say how many and ask before going on.
3. Run:
   `bash ${CLAUDE_PLUGIN_ROOT}/scripts/convert-images.sh --to FORMAT [--max PIXELS] [--quality N] [--out DIR] FILES...`
4. Tell the user in a line or two what was converted, the size saved and where the files are
   (default `~/Desktop/Converted`). If something failed, say which file and why, and how to fix it.

Never delete, move or overwrite the user's original files.
