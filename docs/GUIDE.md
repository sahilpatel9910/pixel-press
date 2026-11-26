# Pixel Press: User Guide

Everything you need to install and use Pixel Press, the right-click image tool for Mac.

- [Install](#install)
- [Compress to Size…](#compress-to-size)
- [Convert & Resize…](#convert--resize)
- [Convert to JPG](#convert-to-jpg)
- [Where do my new files go?](#where-do-my-new-files-go)
- [Tips](#tips)
- [Troubleshooting](#troubleshooting)
- [Update or remove](#update-or-remove)
- [FAQ](#faq)

---

## Install

1. **Download** [Pixel-Press.zip](https://github.com/sahilpatel9910/pixel-press/releases/latest/download/Pixel-Press.zip).
2. **Unzip it** by double-clicking it in your Downloads folder. You get a folder called **Pixel Press**.
3. **Double-click each `.workflow` file** in that folder:
   - Compress to Size….workflow
   - Convert & Resize….workflow
   - Convert to JPG.workflow

   Each time, macOS asks *"Do you want to install the … quick action?"*. Click **Install**.
   If it says one already exists, click **Replace**.

   > System Settings may open on the **Login Items** page after installing. That's normal: macOS is
   > offering to let you check the action is switched on. Nothing was added to your login items.

4. **Switch them on.** Open **System Settings → General → Login Items & Extensions**, scroll down to
   **Extensions**, click **Finder** (or the ⓘ next to it), and turn on all three.

   Shortcut: right-click any image → **Quick Actions → Customise…**

   On macOS 13 or 14 it's **System Settings → Privacy & Security → Extensions → Finder**; on macOS 12,
   **System Preferences → Extensions → Finder**.

That's it. You only do this once.

---

## Compress to Size…

Make images smaller than a size you choose. Use it for email attachments, upload forms with a size
limit, or freeing up space.

1. Select one or more images (or a folder), right-click → **Quick Actions → Compress to Size…**
2. The window shows what you selected, for example:
   *"Selected: 3 images, 12.4 MB in total (largest 6.2 MB)"*
3. Pick how small each image should be:

   | Option | Good for |
   |---|---|
   | **2 MB** | Email attachments |
   | **1 MB** | Messaging apps, most websites |
   | **500 KB** | Online forms, job portals |
   | **200 KB** | Strict web forms, government sites |
   | **100 KB** | Profile pictures, very strict limits |
   | **Custom size…** | Type any size, like `300 KB` or `1.5 MB` |

4. Click **Compress**.

**How it keeps quality:** it first lowers the JPG quality a little at a time. Only if that isn't enough
does it make the picture's dimensions smaller. Images that are already under your size are left alone.

**The result is always a JPG**, because that's the format that can be squeezed to an exact size.
For logos or screenshots that need a transparent background, use *Convert & Resize…* with PNG instead.

---

## Convert & Resize…

Change the format, the size, or both.

1. Right-click your images → **Quick Actions → Convert & Resize…**
2. **Choose a format:**

   | Format | Use it for |
   |---|---|
   | **JPG** | Photos. Opens everywhere. |
   | **PNG** | Screenshots, logos, anything with transparency |
   | **HEIC** | Smallest files, but older Windows PCs can't open it |
   | **PDF** | Documents, receipts, sending a picture as a "document" |
   | **TIFF** | Printing and professional editing |

3. **Choose a size** (the longest side of the picture):

   | Size | Pixels | Good for |
   |---|---|---|
   | Keep original size | | Just changing the format |
   | Large | 2560 px | Full-screen viewing |
   | Medium | 1600 px | Websites, presentations |
   | Small | 1024 px | Email, chat |
   | Thumbnail | 400 px | Previews, icons |

   Pictures are only ever made **smaller**, never stretched bigger.

4. Click **Convert**.

It **remembers your last choice**, so next time you can just press **Return** twice.

---

## Convert to JPG

One click, no questions. The most common job: iPhone photos (HEIC) to JPG so they open on Windows
and on any website. Images that are already JPG are skipped.

---

## Where do my new files go?

**Right next to the originals**, in the same folder. Your originals are never changed.

```
beach.png                 ← original
beach.jpg                 ← Convert to JPG
beach (compressed).jpg    ← Compress to Size…
beach (1600px).jpg        ← Convert & Resize… at Medium
beach 2.jpg               ← a second conversion: names are never overwritten
```

If you right-click a **folder**, the new files are saved inside that folder, next to each image.
(Only the images directly inside the folder are converted, not ones in folders within it.)

When it's done, a **notification** tells you how many images were converted and how much space you
saved, and **Finder highlights** the new file.

---

## Tips

- **Many photos at once:** select them all (⌘A or ⌘-click), then right-click. Or right-click the folder.
- **Keyboard shortcut:** System Settings → Keyboard → Keyboard Shortcuts → Services → Files and Folders lets you
  give any action a shortcut, like ⌃⌥C.
- **Preview pane:** the actions also appear at the bottom of Finder's Preview pane (View → Show Preview).

---

## Troubleshooting

**The actions don't appear when I right-click.**
Make sure they're switched on (Install step 4). If they still don't appear, log out and back in.
They show up for images and folders, not for other kinds of files.

**macOS shows a security warning.**
These actions aren't from the App Store, so macOS may ask you to confirm them once. Open
**System Settings → Privacy & Security**, scroll down, click **Open Anyway**, then try again.

**macOS asks for access to Desktop, Documents or Downloads.**
Click **Allow**. The action needs to read the images you picked and save the new ones next to them.

**"Couldn't convert: … not an image".**
Pixel Press only works on image files. Other files in your selection are skipped.

**An image "couldn't get under" the size I picked.**
The size was too small for that picture. Try a bigger size, or use *Convert & Resize…* to make it
smaller in pixels first.

**I'm not seeing notifications.**
Check **System Settings → Notifications** and make sure notifications are allowed for
**Script Editor** or **Automator**.

**Still not working?**
[Open an issue](https://github.com/sahilpatel9910/pixel-press/issues) and describe what
you clicked and what happened.

---

## Update or remove

**To update:** download the new zip and install the three `.workflow` files again, choosing
**Replace**.

**To remove:**
1. In Finder, press **⇧⌘G** and go to `~/Library/Services`
2. Move these three to the Bin: *Compress to Size….workflow*, *Convert & Resize….workflow*,
   *Convert to JPG.workflow*

---

## FAQ

**Are my photos uploaded anywhere?**
No. Everything happens on your Mac. Pixel Press doesn't use the internet at all.

**Does it work on Windows or iPhone?**
No. It uses tools built into macOS.

**Which Mac do I need?**
macOS 12 Monterey or later, on Apple silicon or Intel.

**Does it keep photo details like date and location?**
JPG and HEIC conversions keep most of the photo's details (EXIF). If you're sharing photos publicly
and want to remove the location, check the photo's info in Photos or Preview first.

**Is it free?**
Yes. It's open source under the MIT license.
