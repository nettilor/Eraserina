<div align="center">

<img src="icon.png" width="140" alt="Eraserina icon">

# Eraserina

**A tiny, fast macOS app for erasing image backgrounds.**
Capture a region of your screen, wipe the background to transparency, and copy straight into your slides — all without leaving the keyboard.

</div>

---

## What it does

Eraserina is a single-window macOS app for turning screenshots and images into clean, transparent-background PNGs. It's built for a tight capture → erase → paste loop:

**⇧⌘4 → drag a box → tidy up → ⌘C → paste into PowerPoint.**

When you load an image it automatically removes the background, then gives you simple tools to fix whatever the algorithm missed.

## Features

- **Screen capture built in** — grab a region with the native macOS crosshair, no separate screenshot app needed. Optional system-wide hotkey captures even when Eraserina is in the background.
- **Automatic background removal** on every image you load, drop, or paste.
- **Four touch-up tools:**
  - **Wand** — click a region to erase everything connected to it.
  - **Color** — click a color to erase it everywhere in the image.
  - **Box** — drag a rectangle to erase everything inside it (great for the stray elements that cling to screenshot edges).
  - **Restore** — click to bring back an area you removed.
- **Zoom & pan** — scroll or pinch to zoom (anchored at the cursor), drag to pan. Pixels render crisp when you're zoomed in close, so precise clicks are easy.
- **Tolerance slider** to control how aggressively colors are matched.
- **Edges-only auto removal** — a toggle (on by default) that limits automatic removal to the background color connected to the image edges; turn it off to erase the detected background color everywhere in the image. **Re-run Auto** re-applies automatic removal after you change the tolerance or the toggle.
- **Clip export to bounding box** — Copy and Save can crop tightly around the remaining pixels.
- **Copy gets out of your way** — ⌘C copies the result and instantly hides Eraserina so you're ready to paste.
- **Undo / redo**, drag-and-drop, and clipboard paste.

## Install

There are two ways to get Eraserina. **Comfortable with Terminal?** Building it yourself (Option A) is the smoothest — a locally-compiled app isn't quarantined, so it launches with no Gatekeeper warning at all. **Never opened Terminal?** Skip to Option B — download the app and drag it to Applications (you'll click through a one-time Gatekeeper step on first launch).

### Option A — Build it yourself (recommended)

You don't need Xcode or any developer account — just Apple's free Command Line Tools. The app is a single Swift file (plus a small icon-generator script), so a build takes a few seconds.

1. **Install the Command Line Tools** (skip if you already have them):

   ```bash
   xcode-select --install
   ```

   A dialog will pop up — click **Install** and wait for it to finish (this can take several minutes and downloads a large package, often around a gigabyte). If instead you see a message that the tools are already installed, you're all set — move on to step 2.

2. **Get the code** — either clone the repo (replace `YOUR-USERNAME` with the GitHub account it's published under):

   ```bash
   git clone https://github.com/YOUR-USERNAME/eraserina.git
   cd eraserina
   ```

   …or download the ZIP from the green **Code** button on GitHub, unzip it, and `cd` into the folder.

3. **Build and run:**

   ```bash
   ./build.sh                        # compiles Eraserina.app in the current folder
   cp -R Eraserina.app /Applications # (optional) copy it to Applications
   open ./Eraserina.app              # launch it
   ```

`build.sh` compiles the app, generates the icon, and ad-hoc signs the bundle. Because you built it locally, macOS opens it straight away — **no "unverified developer" prompt**. To update later, `git pull` (or re-download) and run `./build.sh` again.

### Option B — Download the prebuilt app

1. Download **`Eraserina-1.0.dmg`** from the [Releases](../../releases) page.
2. Open it and drag **Eraserina** into the **Applications** folder.
3. Eject the disk image.

Because the release build is **ad-hoc signed but not notarized** by Apple, Gatekeeper blocks the *first* launch of a downloaded copy with a warning that it can't be verified as free of malware. This is expected for a freely distributed app. Here's how to open it — no Terminal required (you only need to do this once):

1. Double-click **Eraserina**. macOS refuses the first time — that's expected; just dismiss the dialog.
2. Open **System Settings → Privacy & Security** and scroll down to the **Security** section. You'll see a message like *"Eraserina was blocked to protect your Mac."*
3. Click **Open Anyway**, then confirm. Eraserina launches and is trusted from then on.

> On macOS 14 (Sonoma) and earlier you can instead just **right-click (or Control-click) Eraserina → Open → Open** in the dialog. Apple removed that right-click shortcut for un-notarized apps in macOS 15 (Sequoia), so on macOS 15 and later use the **Open Anyway** steps above.

If macOS still refuses, you can clear the quarantine flag yourself. Open **Terminal** (press **⌘Space**, type `Terminal`, press **Return**), paste the command below, and press **Return** — it prints nothing on success:

```bash
xattr -dr com.apple.quarantine /Applications/Eraserina.app
```

Then launch Eraserina normally.

> Prefer to skip this dance entirely? Use **Option A** — a self-built app is never quarantined.

### Screen Recording permission

The **Capture** feature needs Screen Recording permission (this is macOS's rule for any app that reads the screen). The first time you capture, macOS will prompt you — or grant it manually under:

**System Settings → Privacy & Security → Screen Recording → enable Eraserina**, then relaunch the app.

> If captures come back showing only your wallpaper (no windows), the permission hasn't been granted yet.

## Usage

Load an image by dragging a file in, pressing **⌘V** to paste, or **⌘N** to capture a screen region. Eraserina removes the background automatically; use the tools below the image to clean up. When it looks right, press **⌘C** — the result is copied and the window hides so you can paste immediately.

### Replacing the system ⇧⌘4 shortcut (optional)

Open **Settings (⌘,)** and set **"Capture from anywhere"** to a global hotkey. To reuse **⇧⌘4**, first free it from the system:

**System Settings → Keyboard → Keyboard Shortcuts → Screenshots** → uncheck *"Save picture of selected area as a file."*

Prefer to leave the system shortcut alone? Choose **⌃⌘4** or **⇧⌘6** instead — both are free by default.

### Settings

- **Play sound when capturing the screen** — toggle the shutter sound off for silent captures.
- **Capture from anywhere** — pick the global capture hotkey (or leave it off).

## Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘N` | New capture (drag a screen region) |
| `⌘V` | Paste image from clipboard |
| `⌘C` | Copy result & hide window |
| `⌘S` | Save as PNG |
| `⌘Z` / `⇧⌘Z` | Undo / redo |
| `⌘=` / `⌘-` / `⌘0` | Zoom in / out / fit |
| `Esc` | Hide window (keeps your work) |
| `⌘,` | Settings |

`Esc` and `⌘C` hide the window instantly without discarding anything — bring Eraserina back by clicking its Dock icon, ⌘-Tab, or starting a new capture.

## Developing & packaging

The basic build is covered under [Option A](#option-a--build-it-yourself-recommended) above. Two scripts drive everything:

```bash
./build.sh      # compiles Eraserina.app (regenerates the icon if needed)
./make-dmg.sh   # rebuilds the app, then packages Eraserina-<version>.dmg for release
```

To cut a new release: bump `CFBundleShortVersionString` in [`build.sh`](build.sh), run `./make-dmg.sh`, and upload the resulting `.dmg` as a GitHub Release asset.

The repo is deliberately tiny:

- [`BGDrop.swift`](BGDrop.swift) — the entire app (SwiftUI + a Core Graphics pixel engine).
- [`MakeIcon.swift`](MakeIcon.swift) — draws the app icon programmatically; edit it and rebuild to tweak the icon.
- [`build.sh`](build.sh) — compiles and ad-hoc signs the app bundle.
- [`make-dmg.sh`](make-dmg.sh) — packages the distributable disk image.

Build artifacts (`Eraserina.app`, `*.dmg`, the generated icon files) are git-ignored — they're all reproducible from the sources above.

## Requirements

- macOS 13 (Ventura) or later.
- To build: Apple's Command Line Tools (`xcode-select --install`) — no full Xcode or developer account needed.

## License

Add a license of your choice (e.g. MIT) before distributing.
