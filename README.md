# 7-Zip File Manager for macOS 🚀

A native macOS clone of the iconic Windows **7-Zip File Manager** (`7zFM.exe`), built with **Swift** and **SwiftUI / AppKit**, powered by the official 7-Zip engine (`7zz`).

---

## Features

- 📁 **Seamless Dual-Mode & 2-Panel Navigation**: Browse standard macOS folders, dive into nested archives (e.g. `.tar.gz` → `.tar` → files), toggle **Dual-Pane (`F9` / `⌘2`)**, **Flat View (`⌘⇧F`)**, **Hidden Files (`⌘⇧.`)**, and sort by clicking any column header.
- ⬆️ **Signature "Up" (`..`) Navigation**: Step in and out of nested archive directories, then step straight back out to the parent folder on the local filesystem.
- 🟢 **Add to Archive (`+`) Dialog**:
  - Format-aware options for `7z`, `zip`, `tar`, `wim`.
  - Compression Levels (`0 - Store` to `9 - Ultra`), Methods (`LZMA2`, `LZMA`, `PPMd`, `BZip2`, `Deflate`, `Deflate64`, `Copy`), Dictionary/Word/Solid Sizes, and live **RAM usage estimates**.
  - Update Modes (`Add and replace`, `Update and add`, `Freshen`, `Synchronize`), Path Modes, *Delete files after compression*, *Compress shared files*, and custom 7zz flags.
  - Encryption (`AES-256` / `ZipCrypto` for zip, plus *Encrypt file names* for 7z) and multi-volume splitting.
- 🔵 **Extract (`-`) Dialog**:
  - Target destination picker, Path Mode (`Full`, `No pathnames`, `Absolute`), **Eliminate duplication of root folder**, overwrite modes, and password support.
- 📊 **Real-Time Progress Window**: Live percentage bar, elapsed/remaining time, processed/total bytes, speed (`MB/s` / `KB/s`), current file name, plus **Background** (low CPU priority), **Pause / Continue**, and **Cancel** controls.
- ✂️ **Archive & File Tools**: **CRC & Hash Checksum** (`CRC-32`, `CRC-64`, `SHA-1`, `SHA-256`, `SHA-512`, `MD5`, `BLAKE2sp`, `XXH64`), **Split File / Combine Files** (`.001`..`.NNN`), **Rename** & **New Folder** (inside folders or archives), **Drag & Drop**, and **Finder Quick Actions** (`Tools → Install Finder Quick Actions...`).
- ✅ **Test Archive (`✓`)**: Full integrity verification using `7zz t` with status banner and detailed log.
- ⚡ **Built-in 7-Zip Benchmark**: The classic 7-Zip CPU & memory benchmark (`7zz b`) with real-time KiB/s and MIPS ratings for Compressing and Decompressing across customizable thread counts.
- ℹ️ **Properties / Info (`⌘I`)**: Complete inspection of archive headers and file metadata.
- 👁 **Quick Look (`Space`) & File Preview**: Press `Space` for native macOS Quick Look or double-click files inside an archive to open them directly.
- 📦 **Self-Contained macOS App Bundle**: Compiles the official [`ip7z/7zip`](https://github.com/ip7z/7zip) engine directly from GitHub source into a **Universal (`arm64` + `x86_64`)** binary bundled inside `Contents/Resources/7zz`—no Homebrew or separate CLI installation required!

---

## Installation & Running

### Option 1: Direct Launch
You can launch the app directly:
```bash
open "$HOME/Google Drive/My Drive/dev/PC/SevenZipMac/7-Zip.app"
```

Or open a specific archive directly:
```bash
open -a "$HOME/Google Drive/My Drive/dev/PC/SevenZipMac/7-Zip.app" /path/to/archive.7z
```

### Option 2: Copy to `/Applications`
To install it into your system Applications folder:
```bash
cp -R "$HOME/Google Drive/My Drive/dev/PC/SevenZipMac/7-Zip.app" /Applications/
```
Now you can launch **7-Zip** from Spotlight (`Cmd + Space` -> type `7-Zip`) or Launchpad!

---

## Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| `⌘ + C` / `⌘ + V` | Copy / Paste Files (Finder, Folders, and Archives) |
| `⌘ + Backspace` | Delete Selected Items |
| `⌘ + I` | Get Info (Archive or File Properties) |
| `⌘ + ⇧ + N` (or `F7`) | New Folder (in Folders or Archives) |
| `⌘ + ⌥ + R` (or `F2`) | Rename Item (in Folders or Archives) |
| `⌘ + ⇧ + A` | Add to Archive (Compress) |
| `⌘ + E` | Extract Selected Archive / Files |
| `⌘ + T` | Test Archive Integrity |
| `⌘ + ⇧ + H` | CRC & Hash Checksum Calculator |
| `⌘ + B` | 7-Zip Benchmark |
| `F9` or `⌘ + 2` | Toggle 2-Panel Dual Pane View |
| `Tab` | Switch Active Pane (in 2-Panel View) |
| `F5` / `F6` | Copy To... / Move To... |
| `⌘ + Up` or `Backspace` | Navigate Up one directory / Exit Archive |
| `⌘ + [` / `⌘ + ]` | History Back / Forward |
| `⌘ + ⇧ + F` | Toggle Flat View |
| `⌘ + ⇧ + .` | Toggle Hidden Files |
| `⌘ + R` | Refresh Current View |
| `Space` | Quick Look Preview |
| `Return` / Double Click | Open Folder, Archive, or File |

---

## Building from GitHub / Source

This repository links the official **[ip7z/7zip](https://github.com/ip7z/7zip)** source as a Git submodule at `Vendor/7zip`. When someone clones this repository, `ip7z/7zip` is fetched automatically and compiled into a self-contained Universal (`arm64` + `x86_64`) engine bundled inside **`7-Zip.app`**—no separate command-line `7zz` installation required.

```bash
# Clone with the ip7z/7zip submodule
git clone --recursive <your-github-repo-url>
cd SevenZipMac

# Build Universal 7zz from Vendor/7zip + SwiftUI GUI into a single 7-Zip.app
./Scripts/package_app.sh --rebuild-7zz
```

*(If you cloned without `--recursive`, `./Scripts/package_app.sh` automatically runs `git submodule update --init --depth 1` before building.)*
