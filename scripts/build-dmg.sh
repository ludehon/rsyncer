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
trap 'rm -rf "$WORK_DIR"' EXIT
mkdir "$WORK_DIR/contents"
ditto "$APP_PATH" "$WORK_DIR/contents/Rsyncer.app"
if (( $# == 0 )); then
  # Local builds need an ad hoc signature to run on Apple Silicon.
  codesign --force --sign - "$WORK_DIR/contents/Rsyncer.app"
fi
codesign --verify --deep --strict "$WORK_DIR/contents/Rsyncer.app"
ln -s /Applications "$WORK_DIR/contents/Applications"

hdiutil create -volname 'Rsyncer' -srcfolder "$WORK_DIR/contents" \
  -format UDZO -fs HFS+ "$WORK_DIR/Rsyncer.dmg"
hdiutil verify "$WORK_DIR/Rsyncer.dmg"
DMG_PATH="$OUTPUT_DIR/Rsyncer-$APP_VERSION.dmg"
mv -f "$WORK_DIR/Rsyncer.dmg" "$DMG_PATH"
print "Created: $DMG_PATH"
if (( $# == 0 )); then
  print "Local build: ad hoc signed, not notarized. See README.md for public distribution."
fi
