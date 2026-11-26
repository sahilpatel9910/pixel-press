# Desktop Converter

A Claude Code plugin that converts, resizes and compresses images on your Mac. You just ask:

> convert the HEIC photos on my Desktop to JPG
>
> make these screenshots small enough to email
>
> `/convert ~/Desktop/vacation 1600px jpg`

Results go to `~/Desktop/Converted`. **Your originals are never changed, moved or deleted**, and an
existing file is never overwritten (`photo.jpg` becomes `photo-1.jpg`).

## Install

```bash
claude plugin marketplace add sahilpatel9910/desktop-converter
claude plugin install desktop-converter@desktop-converter
```

Then start `claude` and ask away.

## What it can do

- **Convert** between HEIC, JPG, PNG, TIFF, GIF, BMP and PDF, and from WebP, RAW and more
- **Resize** to a maximum size in pixels (it only shrinks, never enlarges)
- **Compress** photos for email or the web
- **Whole folders** at once (Claude asks first if it's more than 20 files)

It uses `sips`, the image tool built into every Mac, so nothing needs installing.
Only **WebP output** needs an extra tool: `brew install webp`.

## Requirements

macOS and Claude Code 2.1 or later.

## License

MIT
