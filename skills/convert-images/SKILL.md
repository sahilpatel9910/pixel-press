---
name: convert-images
description: Convert, resize or compress image files on the user's Mac. Use when the user asks to change an image's format (HEIC, PNG, WebP, TIFF, GIF, BMP to JPG, PNG, HEIC, PDF, WebP and so on), make photos smaller or lighter for email, a website or an upload, resize pictures to a pixel size, or convert iPhone photos so they open on Windows.
---

# Converting images

Use the bundled script. It runs on macOS's built-in `sips`, so nothing needs installing,
except WebP output, which needs `brew install webp`.

```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/convert-images.sh --to FORMAT [--max PIXELS] [--quality 1-100] [--out DIR] FILE_OR_FOLDER...
```

- `--to`: jpg, png, heic, tiff, gif, bmp, pdf or webp.
- `--max`: longest side in pixels. Images are only ever shrunk, never enlarged.
- `--quality`: for jpg, heic and webp. 75–85 is a good balance; lower is smaller.
- `--out`: output folder. Default `~/Desktop/Converted`.
- A folder converts the images directly inside it (not subfolders).

## Picking settings from plain requests

| The user says | Use |
|---|---|
| "convert to JPG", "make it open on Windows" | `--to jpg --quality 90` |
| "smaller", "compress", "for email", "under a few MB" | `--to jpg --max 2000 --quality 75` |
| "for my website", "for web" | `--to jpg --max 1600 --quality 80`, or `--to webp` if asked |
| "transparent background", "screenshot", "logo" | `--to png` (JPG loses transparency) |
| "make a PDF of this picture" | `--to pdf` |
| "thumbnail" | `--to jpg --max 400 --quality 80` |

If a target size like "under 1 MB" isn't met, run again with a lower `--quality` or `--max`,
into a fresh output folder, and tell the user what you changed.

## Rules

- Never delete, move or overwrite the originals. The script already writes to a separate folder
  and never overwrites; don't work around that.
- If no files were named, list the images on `~/Desktop` (or the folder they mentioned) and ask which.
- Ask before converting more than 20 files at once.
- Afterwards, tell the user in a line or two: how many converted, size before and after, and where they are.
- If `sips` is missing, the user isn't on a Mac: say this plugin is for macOS.
