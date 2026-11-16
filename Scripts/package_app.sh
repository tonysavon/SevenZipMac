#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR/.."

BUILD_SCRATCH="/tmp/SevenZipMacBuild"
echo "==> Building SevenZipGUI (Release mode)..."
swift build -c release --scratch-path "$BUILD_SCRATCH"

APP_NAME="7-Zip.app"
APP_DIR="$DIR/../$APP_NAME"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "==> Creating $APP_NAME structure..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS"
mkdir -p "$RESOURCES"

# Copy executable
cp "$BUILD_SCRATCH/release/SevenZipGUI" "$MACOS/SevenZipGUI"
chmod +x "$MACOS/SevenZipGUI"

# Build and bundle Universal 7zz from official ip7z/7zip source
BUILT_7ZZ="$BUILD_SCRATCH/7zz"
if [ ! -x "$BUILT_7ZZ" ] || [ "$1" = "--rebuild-7zz" ]; then
    "$DIR/build_7zz.sh" "$BUILT_7ZZ"
fi
echo "==> Bundling source-built Universal 7zz into Resources..."
cp "$BUILT_7ZZ" "$RESOURCES/7zz"
chmod +x "$RESOURCES/7zz"

# Generate Icon
echo "==> Generating AppIcon.icns..."
python3 - << 'EOF'
import os, subprocess, tempfile

iconset_dir = tempfile.mkdtemp(suffix=".iconset")
sizes = [16, 32, 64, 128, 256, 512]

# Generate base 1024x1024 SVG and convert to PNG using CoreGraphics / Python
svg_content = '''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#2c3e50" />
      <stop offset="100%" stop-color="#1a252f" />
    </linearGradient>
    <linearGradient id="accent" x1="0%" y1="0%" x2="100%" y2="0%">
      <stop offset="0%" stop-color="#2ecc71" />
      <stop offset="50%" stop-color="#3498db" />
      <stop offset="100%" stop-color="#9b59b6" />
    </linearGradient>
    <filter id="shadow" x="-10%" y="-10%" width="120%" height="120%">
      <feDropShadow dx="0" dy="16" stdDeviation="24" flood-color="#000000" flood-opacity="0.4" />
    </filter>
  </defs>
  
  <!-- Outer Rounded Squircle -->
  <rect x="64" y="64" width="896" height="896" rx="200" fill="url(#bg)" filter="url(#shadow)" stroke="#455a64" stroke-width="12" />
  
  <!-- Accent top bar (classic 7z style) -->
  <rect x="64" y="64" width="896" height="24" rx="12" fill="url(#accent)" />
  
  <!-- Big 7-Zip Text / Logo -->
  <g fill="#ffffff" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Helvetica Neue', Arial, sans-serif" font-weight="900">
    <text x="210" y="620" font-size="460" letter-spacing="-10">7</text>
    <text x="500" y="620" font-size="340" fill="#3498db" letter-spacing="-5">z</text>
  </g>
  
  <!-- Subtitle badge -->
  <rect x="330" y="720" width="364" height="68" rx="34" fill="#2ecc71" />
  <text x="512" y="768" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif" font-size="38" font-weight="700" fill="#ffffff" text-anchor="middle">FILE MANAGER</text>
</svg>'''

base_svg = os.path.join(iconset_dir, "base.svg")
with open(base_svg, "w") as f:
    f.write(svg_content)

# Use qlmanage or sips to render SVG to PNG
# On macOS, sips or quicklook can render or we can use swift / AppKit directly
script = f'''
import AppKit

let svgURL = URL(fileURLWithPath: "{base_svg}")
if let image = NSImage(contentsOf: svgURL) {{
    let targetSizes: [(Int, String)] = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png")
    ]
    
    for (sz, name) in targetSizes {{
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: sz,
            pixelsHigh: sz,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        rep.size = NSSize(width: sz, height: sz)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: sz, height: sz))
        NSGraphicsContext.restoreGraphicsState()
        
        if let pngData = rep.representation(using: .png, properties: [:]) {{
            let outURL = URL(fileURLWithPath: "{iconset_dir}/" + name)
            try? pngData.write(to: outURL)
        }}
    }}
}}
'''

swift_script = os.path.join(iconset_dir, "render.swift")
with open(swift_script, "w") as f:
    f.write(script)

subprocess.run(["swift", swift_script], check=True)
subprocess.run(["iconutil", "-c", "icns", iconset_dir, "-o", f"{os.getcwd()}/7-Zip.app/Contents/Resources/AppIcon.icns"], check=True)
EOF

# Read 7-Zip version from Vendor/7zip/C/7zVersion.h
VERSION_FILE="$DIR/../Vendor/7zip/C/7zVersion.h"
APP_VERSION="26.06"
if [ -f "$VERSION_FILE" ]; then
    PARSED_VER=$(awk '/^#define MY_VERSION_NUMBERS /{gsub(/"/, "", $3); print $3}' "$VERSION_FILE")
    if [ -n "$PARSED_VER" ]; then
        APP_VERSION="$PARSED_VER"
    fi
fi

# Create Info.plist
echo "==> Creating Info.plist (version $APP_VERSION)..."
cat << EOF > "$CONTENTS/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>SevenZipGUI</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>org.7zip.gui</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>7-Zip</string>
    <key>CFBundleDisplayName</key>
    <string>7-Zip File Manager</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${APP_VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>7-Zip Archive</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>7z</string>
                <string>zip</string>
                <string>rar</string>
                <string>tar</string>
                <string>gz</string>
                <string>bz2</string>
                <string>xz</string>
                <string>iso</string>
                <string>wim</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
EOF

echo "==> Ad-hoc code signing $APP_NAME..."
codesign --force --deep --sign - "$APP_DIR"

echo "==> Successfully created $APP_NAME at $APP_DIR"
