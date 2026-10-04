#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/module-cache"

BUILD_ARGS=(--cache-path "$ROOT_DIR/.build/cache" --disable-sandbox)
case "$MODE" in
  --release-build) BUILD_ARGS+=(-c release --arch arm64 --arch x86_64) ;;
  run|--build|--verify|--debug|--logs|--telemetry) ;;
  *) printf 'Usage: %s [run|--build|--release-build|--verify|--debug|--logs|--telemetry]\n' "$0" >&2; exit 2 ;;
esac
if [[ "$MODE" != "--build" && "$MODE" != "--release-build" ]]; then pkill -x AIMonitor >/dev/null 2>&1 || true; fi
swift build "${BUILD_ARGS[@]}"
BUILD_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
BUNDLE="$ROOT_DIR/dist/AIMonitor.app"
ICON_SOURCE="$ROOT_DIR/Resources/AppIcon.png"
ICON_FILE="$ROOT_DIR/.build/AppIcon.icns"
if [[ ! -f "$ICON_FILE" || "$ICON_SOURCE" -nt "$ICON_FILE" ]]; then
  ICON_SET="$ROOT_DIR/.build/AppIcon.iconset"
  mkdir -p "$ICON_SET"
  for SIZE in 16 32 128 256 512; do
    /usr/bin/sips -z "$SIZE" "$SIZE" "$ICON_SOURCE" --out "$ICON_SET/icon_${SIZE}x${SIZE}.png" >/dev/null
    /usr/bin/sips -z "$((SIZE * 2))" "$((SIZE * 2))" "$ICON_SOURCE" --out "$ICON_SET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
  done
  /usr/bin/iconutil -c icns "$ICON_SET" -o "$ICON_FILE"
fi
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$ICON_FILE" "$BUNDLE/Contents/Resources/AppIcon.icns"
cp "$ROOT_DIR/LICENSE" "$BUNDLE/Contents/Resources/LICENSE"
cp "$BUILD_DIR/AIMonitor" "$BUNDLE/Contents/MacOS/AIMonitor.next"
chmod +x "$BUNDLE/Contents/MacOS/AIMonitor.next"
mv "$BUNDLE/Contents/MacOS/AIMonitor.next" "$BUNDLE/Contents/MacOS/AIMonitor"
cp "$ROOT_DIR/Resources/Info.plist" "$BUNDLE/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$BUNDLE" >/dev/null

case "$MODE" in
  --build|--release-build) printf 'Built %s\n' "$BUNDLE" ;;
  run) /usr/bin/open -n "$BUNDLE" --args --show ;;
  --verify) /usr/bin/open -n "$BUNDLE" --args --show; sleep 2; pgrep -x AIMonitor >/dev/null ;;
  --debug) lldb -- "$BUNDLE/Contents/MacOS/AIMonitor" --show ;;
  --logs) /usr/bin/open -n "$BUNDLE" --args --show; /usr/bin/log stream --info --style compact --predicate 'process == "AIMonitor"' ;;
  --telemetry) /usr/bin/open -n "$BUNDLE" --args --show; /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.aimonitor.app"' ;;
esac
