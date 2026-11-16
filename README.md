# 7-Zip File Manager for macOS

A native macOS clone of the Windows **7-Zip File Manager** (`7zFM.exe`), built with **Swift** and **SwiftUI / AppKit**, powered by the official 7-Zip engine (`ip7z/7zip`).

---

## Features

- **Seamless Dual-Mode & 2-Panel Navigation**: Browse standard macOS folders, dive into nested archives (e.g., `.tar.gz` -> `.tar` -> files), toggle **Dual-Pane (`F9` / `⌘2`)**, **Flat View (`⌘⇧F`)**, **Hidden Files (`⌘⇧.`)**, and sort by clicking any column header.
- **Signature "Up" (`..`) Navigation**: Step in and out of nested archive directories, then step straight back out to the parent folder on the local filesystem.
- **Add to Archive (`+`) Dialog**:
  - Format-aware options for `7z`, `zip`, `tar`, `wim`.
  - Compression Levels (`0 - Store` to `9 - Ultra`), Methods (`LZMA2`, `LZMA`, `PPMd`, `BZip2`, `Deflate`, `Deflate64`, `Copy`), Dictionary/Word/Solid Sizes, and live **RAM usage estimates**.
  - Update Modes (`Add and replace`, `Update and add`, `Freshen`, `Synchronize`), Path Modes, *Delete files after compression*, *Compress shared files*, and custom `7zz` flags.
  - Encryption (`AES-256` / `ZipCrypto` for zip, plus *Encrypt file names* for 7z) and multi-volume splitting.
- **Extract (`-`) Dialog**:
  - Target destination picker, Path Mode (`Full`, `No pathnames`, `Absolute`), **Eliminate duplication of root folder**, overwrite modes, and password support.
- **Real-Time Progress Window**: Live percentage bar, elapsed/remaining time, processed/total bytes, speed (`MB/s` / `KB/s`), current file name, plus **Background** (low CPU priority), **Pause / Continue**, and **Cancel** controls.
- **Archive & File Tools**: **CRC & Hash Checksum** (`CRC-32`, `CRC-64`, `SHA-1`, `SHA-256`, `SHA-512`, `MD5`, `BLAKE2sp`, `XXH64`), **Split File / Combine Files** (`.001`..`.NNN`), **Rename** & **New Folder** (inside folders or archives), **Drag & Drop**, and **Finder Quick Actions** (`Tools -> Install Finder Quick Actions...`).
- **Test Archive**: Full integrity verification using `7zz t` with status banner and detailed log.
- **Built-in 7-Zip Benchmark**: CPU & memory benchmark (`7zz b`) with real-time KiB/s and MIPS ratings for Compressing and Decompressing across customizable thread counts.
- **Properties / Info (`⌘I`)**: Complete inspection of archive headers and file metadata.
- **Quick Look (`Space`) & File Preview**: Press `Space` for native macOS Quick Look or double-click files inside an archive to open them directly.
- **Self-Contained macOS App Bundle**: Compiles the official [`ip7z/7zip`](https://github.com/ip7z/7zip) engine directly from GitHub source into a **Universal (`arm64` + `x86_64`)** binary bundled inside `Contents/Resources/7zz` — no Homebrew or separate CLI installation required.

---

## Building from Source

This repository links the official **[ip7z/7zip](https://github.com/ip7z/7zip)** source as a Git submodule at `Vendor/7zip`. Cloning recursively fetches `ip7z/7zip` and compiles it into a self-contained Universal (`arm64` + `x86_64`) engine bundled inside **`7-Zip.app`**.

```bash
# Clone with the ip7z/7zip submodule
git clone --recursive https://github.com/tonysavon/SevenZipMac.git
cd SevenZipMac

# Build Universal 7zz from Vendor/7zip + SwiftUI GUI into 7-Zip.app
./Scripts/package_app.sh --rebuild-7zz
```

*(If you cloned without `--recursive`, `./Scripts/package_app.sh` automatically runs `git submodule update --init --depth 1` before building.)*

---

## Installation & Running

### Direct Launch
```bash
open ./7-Zip.app
```

Open a specific archive directly:
```bash
open -a ./7-Zip.app /path/to/archive.7z
```

### Install to `/Applications`
```bash
ditto ./7-Zip.app /Applications/7-Zip.app
```
Once installed, you can launch **7-Zip** from Spotlight (`Cmd + Space` -> `7-Zip`) and enable Finder context-menu integration via **Tools -> Install Finder Quick Actions...**.

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
