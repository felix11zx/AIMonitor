#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
./script/build_and_run.sh --release-build
BUNDLE="$ROOT_DIR/dist/AIMonitor.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$BUNDLE/Contents/Info.plist")"
ARCHIVE="AIMonitor-${VERSION}-macOS-universal.zip"
/usr/bin/codesign --verify --deep --strict "$BUNDLE"
ARCHITECTURES="$(/usr/bin/lipo -archs "$BUNDLE/Contents/MacOS/AIMonitor")"
if [[ " $ARCHITECTURES " != *" arm64 "* || " $ARCHITECTURES " != *" x86_64 "* ]]; then
  printf 'Expected arm64 and x86_64; found %s\n' "$ARCHITECTURES" >&2
  exit 1
fi
/usr/bin/plutil -lint "$BUNDLE/Contents/Info.plist"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$BUNDLE" "$ROOT_DIR/dist/$ARCHIVE"
cp "$ROOT_DIR/docs/INSTALLATION.md" "$ROOT_DIR/dist/INSTALLATION.md"
cd "$ROOT_DIR/dist"
/usr/bin/shasum -a 256 "$ARCHIVE" > SHA256SUMS.txt
printf 'Release package: %s/dist/%s\n' "$ROOT_DIR" "$ARCHIVE"
