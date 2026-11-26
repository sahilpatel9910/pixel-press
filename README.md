# Desktop Converter

A Claude Code plugin that converts, resizes and compresses images on your Mac. You just ask:

> convert the HEIC photos on my Desktop to JPG
>
> make these screenshots small enough to email
>
> `/convert ~/Desktop/vacation 1600px jpg`

New files are saved next to the originals. **Your originals are never changed, moved or deleted**, and an
existing file is never overwritten (`photo.jpg` becomes `photo 2.jpg`).

## Install

```bash
claude plugin marketplace add sahilpatel9910/desktop-converter
claude plugin install desktop-converter@desktop-converter
```

Then start `claude` and ask away.

## What it can do

- **Convert** between HEIC, JPG, PNG, TIFF, GIF, BMP and PDF, and from WebP, RAW and more
- **Resize** to a maximum size in pixels (it only shrinks, never enlarges)
- **Compress** photos to a size you choose, like "under 500 KB"
- **Whole folders** at once (Claude asks first if it's more than 20 files)

It uses `sips`, the image tool built into every Mac, so nothing needs installing.
Only **WebP output** needs an extra tool: `brew install webp`.

## Requirements

macOS and Claude Code 2.1 or later.

## License

MIT

## Right-click Quick Actions (no Claude needed)

**For people you share it with:** build the double-click version and send them the zip.
It needs no Terminal: they unzip it, double-click each `.workflow` file, click Install,
and follow `How to Install.html`.

```bash
python3 quick-actions/build-installer.py   # → dist/Desktop-Converter.zip
```

**Or from Terminal**, run once on your Mac:

```bash
bash quick-actions/install-quick-actions.sh
```

Turn them on once in **System Settings → General → Login Items & Extensions → Extensions → Finder**.
Then right-click any image, several images or a folder → **Quick Actions**:

- **Convert to JPG**: one click. Images that are already JPG are skipped.
- **Compress to Size…**: shows how big your images are, then makes each one smaller than the size you
  pick: 2 MB (email), 1 MB, 500 KB, 200 KB (web forms), 100 KB or any size you type. It keeps as much
  quality as it can: quality is lowered first, then dimensions only if needed.
- **Convert & Resize…**: pick a format (JPG, PNG, HEIC, PDF, TIFF) and a size. It remembers your last choice.

A notification says what happened and how much space was saved, and Finder shows the new file.
New files are saved next to the originals, e.g. `beach (compressed).jpg`; originals are never changed.
Remove them with `bash quick-actions/install-quick-actions.sh --uninstall`.
