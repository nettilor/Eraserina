#!/bin/bash
# Packages Eraserina.app into a distributable .dmg with an Applications
# drag-target. Run after (or it will run) build.sh.
#   ./make-dmg.sh
set -e
cd "$(dirname "$0")"

APP="Eraserina.app"
VOLNAME="Eraserina"

# Always build fresh so the DMG matches the current source.
./build.sh

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null || echo "1.0")
DMG="Eraserina-${VERSION}.dmg"
TMPDMG="$(mktemp -u).dmg"

echo "Packaging $DMG…"

# Stage the app + a symlink to /Applications so users can drag to install.
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# Build a read-write image (auto-sized to contents), then decorate it.
rm -f "$DMG" "$TMPDMG"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -fs HFS+ \
    -format UDRW -ov "$TMPDMG" >/dev/null

DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen "$TMPDMG" | grep '^/dev/' | head -1 | awk '{print $1}')
MOUNT="/Volumes/$VOLNAME"

# Give the mounted volume the app's own icon (needs Xcode's SetFile; skipped if absent).
if command -v SetFile >/dev/null 2>&1; then
    cp AppIcon.icns "$MOUNT/.VolumeIcon.icns"
    SetFile -c icnC "$MOUNT/.VolumeIcon.icns"
    SetFile -a C "$MOUNT"
fi

sync
hdiutil detach "$DEVICE" >/dev/null

# Convert to a compressed, read-only image for distribution.
hdiutil convert "$TMPDMG" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null

rm -f "$TMPDMG"
rm -rf "$STAGE"

SIZE=$(du -h "$DMG" | awk '{print $1}')
echo "Done → $DMG ($SIZE)"
