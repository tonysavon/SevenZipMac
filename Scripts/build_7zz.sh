#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT_DIR="$(cd "$DIR/.." && pwd)"
SUBMODULE_DIR="$ROOT_DIR/Vendor/7zip"
WORK_SRC="/tmp/SevenZipUpstream"
OUT_BIN="${1:-/tmp/SevenZipMacBuild/7zz}"
mkdir -p "$(dirname "$OUT_BIN")"

# Ensure the ip7z/7zip GitHub submodule is fetched if someone cloned without --recursive
if [ ! -f "$SUBMODULE_DIR/CPP/7zip/Bundles/Alone2/makefile.gcc" ]; then
    if [ -d "$ROOT_DIR/.git" ]; then
        echo "==> Initializing Vendor/7zip submodule from https://github.com/ip7z/7zip.git..."
        cd "$ROOT_DIR"
        git submodule update --init --depth 1 Vendor/7zip
    else
        echo "==> Cloning official 7-Zip source from https://github.com/ip7z/7zip.git..."
        rm -rf "$WORK_SRC"
        git clone --depth 1 https://github.com/ip7z/7zip.git "$WORK_SRC"
    fi
fi

# Mirror Vendor/7zip source to /tmp so .o build artifacts stay on fast local APFS
if [ -f "$SUBMODULE_DIR/CPP/7zip/Bundles/Alone2/makefile.gcc" ]; then
    mkdir -p "$WORK_SRC"
    rsync -a --delete --exclude='.git' --exclude='b/' "$SUBMODULE_DIR/" "$WORK_SRC/"
fi

echo "==> Compiling 7zz (arm64 & x86_64 Universal) from Vendor/7zip (ip7z/7zip)..."
cd "$WORK_SRC/CPP/7zip/Bundles/Alone2"

NCPU=$(sysctl -n hw.ncpu)
make -j"$NCPU" -f ../../cmpl_mac_arm64.mak
make -j"$NCPU" -f ../../cmpl_mac_x64.mak MY_ARCH="-arch x86_64 -mmacosx-version-min=13.0"

lipo -create b/m_arm64/7zz b/m_x64/7zz -output "$OUT_BIN"
chmod +x "$OUT_BIN"
echo "==> Built Universal 7zz at $OUT_BIN"
