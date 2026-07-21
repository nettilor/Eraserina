#!/bin/bash
# Builds Eraserina.app — a tiny drag-and-drop background remover.
# Requires Xcode Command Line Tools:  xcode-select --install
set -e
cd "$(dirname "$0")"

APP=Eraserina.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Regenerate the app icon when the generator script changes
if [ ! -f AppIcon.icns ] || [ MakeIcon.swift -nt AppIcon.icns ]; then
    echo "Generating icon…"
    swift MakeIcon.swift
    iconutil -c icns AppIcon.iconset
    rm -rf AppIcon.iconset
fi
cp AppIcon.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Eraserina</string>
    <key>CFBundleIdentifier</key><string>local.eraserina</string>
    <key>CFBundleExecutable</key><string>Eraserina</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

echo "Compiling…"
swiftc -O -parse-as-library Eraserina.swift -o "$APP/Contents/MacOS/Eraserina"

codesign --force --deep --sign - "$APP"

echo "Done. Launch with:  open $APP"
