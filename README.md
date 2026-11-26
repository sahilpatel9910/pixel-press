# Desktop Converter

**Convert, resize and compress images on your Mac, just by right-clicking them.**

Right-click any photo in Finder → **Quick Actions** → done. No apps to open, no websites to upload to.
Everything happens on your Mac, and your originals are never changed.

| | |
|---|---|
| 🗜️ **Compress to Size…** | Make each image smaller than 2 MB, 500 KB, 100 KB or any size you type |
| 🔄 **Convert & Resize…** | JPG, PNG, HEIC, PDF or TIFF, at the size you pick |
| ⚡ **Convert to JPG** | One click. Ideal for iPhone photos (HEIC) that won't open on Windows |

```
beach.png                 ← your original, untouched
beach.jpg                 ← Convert to JPG
beach (compressed).jpg    ← Compress to Size…
beach (1600px).jpg        ← Convert & Resize… at Medium size
```

---

## Download

**[⬇ Download Desktop-Converter.zip](https://github.com/sahilpatel9910/desktop-converter/releases/latest/download/Desktop-Converter.zip)**
from the [latest release](https://github.com/sahilpatel9910/desktop-converter/releases/latest).

### Install in 1 minute (no Terminal)

1. **Unzip** the download: double-click `Desktop-Converter.zip`.
2. **Double-click** each of the three `.workflow` files and click **Install**.
   (System Settings may open afterwards. That's normal; just close it.)
3. **Switch them on**: System Settings → General → Login Items & Extensions → Extensions → **Finder**,
   and turn on *Compress to Size…*, *Convert & Resize…* and *Convert to JPG*.

Then right-click any image, several images or a folder → **Quick Actions**.

📖 **[Read the full user guide](docs/GUIDE.md)** for step-by-step use, tips and troubleshooting.

### Good to know

- **Private:** your images never leave your Mac. It uses the image engine built into macOS (the same one as Preview).
- **Safe:** originals are never changed, moved or deleted. A taken name becomes `photo 2.jpg`, never an overwrite.
- **Smart compression:** it lowers quality first and only shrinks dimensions if it has to, so photos stay as sharp as possible.
- **Helpful:** a notification tells you how much space you saved, and Finder highlights the new file.
- **Requirements:** macOS 12 Monterey or later. Nothing else to install.

---

## Use it with Claude Code (optional)

Desktop Converter is also a [Claude Code](https://claude.com/claude-code) plugin, so you can just ask:

> convert the HEIC photos on my Desktop to JPG
>
> get the pictures in ~/Desktop/Trip under 500 KB each
>
> `/convert ~/Desktop/photo.png pdf`

Install it:

```bash
claude plugin marketplace add sahilpatel9910/desktop-converter
```

```bash
claude plugin install desktop-converter@desktop-converter
```

It needs Claude Code 2.1 or later. WebP output also needs `brew install webp`.

---

## For developers

### How it works

Everything is built on tools that ship with macOS:

| Piece | What it does |
|---|---|
| [`scripts/convert-images.sh`](scripts/convert-images.sh) | The converter. Uses `sips` (built into macOS). Works in the bash 3.2 that ships with macOS. |
| Quick Actions (`.workflow`) | Automator "Run Shell Script" actions. Each one **embeds its own copy of the converter**, so it works on its own. |
| Dialogs and notifications | AppleScript via `osascript` |
| [`skills/`](skills/convert-images/SKILL.md), [`commands/`](commands/convert.md) | The Claude Code plugin: how Claude picks settings from plain requests |

**Compress to Size** fits each image under the target by trial: it tries qualities 82 → 65 → 50, and if the file
is still too big, it scales the dimensions by about √(target ÷ size) and tries again (up to 12 rounds).

### The converter on its own

```bash
scripts/convert-images.sh --to jpg|png|heic|tiff|gif|bmp|pdf|webp \
    [--max PIXELS] [--quality 1-100] [--target SIZE] [--suffix TEXT] \
    [--out DIR] [--skip-same] [--report FILE] [--info] FILE_OR_FOLDER...
```

```bash
# every image in a folder under 500 KB, saved next to the originals
scripts/convert-images.sh --to jpg --target 500KB --suffix " (compressed)" --out ~/Pictures/Trip ~/Pictures/Trip
```

Run `scripts/convert-images.sh --help` for every option.

### Build the Quick Actions

The workflows are generated, not edited by hand:

```bash
python3 quick-actions/build-installer.py
```

That writes:

- `dist/Desktop-Converter.zip`: the double-click download, with the three workflows and *How to Install.html*
- `quick-actions/install-quick-actions.sh`: a Terminal installer (`--uninstall` removes everything)

To publish a release, attach `dist/Desktop-Converter.zip` to a GitHub release with that exact file name,
so the download link above keeps working.

### Project layout

```
.claude-plugin/        Claude Code plugin manifest and marketplace entry
commands/convert.md    /convert slash command
skills/convert-images/ Skill: turns plain requests into converter options
scripts/               The converter
quick-actions/         Quick Actions builder, Terminal installer, install guide page
docs/GUIDE.md          User guide
```

## License

[MIT](LICENSE)
