#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
OUTPUT_DIR="$ROOT_DIR/build"

if (( $# > 1 )) || [[ "${1:-}" == --help ]]; then
  print "Usage: $0 [path/to/Rsyncer.app]"
  print "Builds a universal Release app, or packages an existing signed/exported app."
  print "Output: build/Rsyncer-<version>.dmg"
  if (( $# > 1 )); then exit 1; fi
  exit 0
fi

mkdir -p "$OUTPUT_DIR"
if (( $# == 1 )); then
  APP_PATH="${1:A}"
else
  xcodebuild -project "$ROOT_DIR/rsyncer.xcodeproj" -scheme rsyncer \
    -configuration Release -destination 'generic/platform=macOS' \
    -derivedDataPath "$OUTPUT_DIR/DerivedData" \
    ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build
  APP_PATH="$OUTPUT_DIR/DerivedData/Build/Products/Release/Rsyncer.app"
fi

if [[ ! -d "$APP_PATH" || ! -f "$APP_PATH/Contents/Info.plist" ]]; then
  print -u2 "App bundle not found: $APP_PATH"
  exit 1
fi
APP_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")
if [[ -z "$APP_VERSION" || "$APP_VERSION" == *[^0-9A-Za-z.-]* ]]; then
  print -u2 "Invalid app version for DMG filename: $APP_VERSION"
  exit 1
fi

WORK_DIR=$(mktemp -d "$OUTPUT_DIR/dmg.XXXXXX")
MOUNT_PATH="$WORK_DIR/mount"
IMAGE_MOUNTED=false
cleanup() {
  if [[ "$IMAGE_MOUNTED" == true ]]; then
    hdiutil detach "$MOUNT_PATH" || return
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT
mkdir "$WORK_DIR/contents"
ditto "$APP_PATH" "$WORK_DIR/contents/Rsyncer.app"
if (( $# == 0 )); then
  # Local builds need an ad hoc signature to run on Apple Silicon.
  codesign --force --sign - "$WORK_DIR/contents/Rsyncer.app"
fi
codesign --verify --deep --strict "$WORK_DIR/contents/Rsyncer.app"
ln -s /Applications "$WORK_DIR/contents/Applications"
mkdir "$WORK_DIR/contents/.background"
chflags hidden "$WORK_DIR/contents/.background"
swift -module-cache-path "$OUTPUT_DIR/SwiftModuleCache" \
  "$ROOT_DIR/scripts/generate-dmg-background.swift" \
  "$WORK_DIR/contents/.background/installer.tiff"

# Finder saves icon positions, window geometry, and the background in .DS_Store.
# Configure a writable image, then compress it for distribution.
hdiutil create -volname 'Rsyncer' -srcfolder "$WORK_DIR/contents" \
  -format UDRW -fs HFS+ "$WORK_DIR/writable.dmg"
mkdir "$MOUNT_PATH"
hdiutil attach "$WORK_DIR/writable.dmg" -nobrowse -mountpoint "$MOUNT_PATH"
IMAGE_MOUNTED=true
osascript "$ROOT_DIR/scripts/layout-dmg.applescript" "$MOUNT_PATH"
if [[ ! -f "$MOUNT_PATH/.DS_Store" ]]; then
  print -u2 'Finder did not save the installer layout.'
  exit 1
fi
hdiutil detach "$MOUNT_PATH"
IMAGE_MOUNTED=false
# Flush Finder's cache before finalizing the positions actually stored on disk.
hdiutil attach "$WORK_DIR/writable.dmg" -nobrowse -mountpoint "$MOUNT_PATH"
IMAGE_MOUNTED=true
python3 "$ROOT_DIR/scripts/finalize-dmg-layout.py" "$MOUNT_PATH/.DS_Store"
chflags hidden "$MOUNT_PATH/.background"
if [[ -d "$MOUNT_PATH/.fseventsd" ]]; then
  chflags hidden "$MOUNT_PATH/.fseventsd"
fi
hdiutil detach "$MOUNT_PATH"
IMAGE_MOUNTED=false
hdiutil convert "$WORK_DIR/writable.dmg" -format UDZO -o "$WORK_DIR/Rsyncer.dmg"
hdiutil verify "$WORK_DIR/Rsyncer.dmg"
hdiutil attach "$WORK_DIR/Rsyncer.dmg" -readonly -nobrowse -mountpoint "$MOUNT_PATH"
IMAGE_MOUNTED=true
python3 "$ROOT_DIR/scripts/finalize-dmg-layout.py" --verify "$MOUNT_PATH/.DS_Store"
hdiutil detach "$MOUNT_PATH"
IMAGE_MOUNTED=false
DMG_PATH="$OUTPUT_DIR/Rsyncer-$APP_VERSION.dmg"
mv -f "$WORK_DIR/Rsyncer.dmg" "$DMG_PATH"
print "Created: $DMG_PATH"
if (( $# == 0 )); then
  print "Local build: ad hoc signed, not notarized. See README.md for public distribution."
fi
