#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/module-cache"

if [[ "$MODE" != "--build" ]]; then pkill -x AIMonitor >/dev/null 2>&1 || true; fi
swift build --cache-path "$ROOT_DIR/.build/cache" --disable-sandbox
BUILD_DIR="$(swift build --cache-path "$ROOT_DIR/.build/cache" --disable-sandbox --show-bin-path)"
BUNDLE="$ROOT_DIR/dist/AIMonitor.app"
mkdir -p "$BUNDLE/Contents/MacOS"
cp "$BUILD_DIR/AIMonitor" "$BUNDLE/Contents/MacOS/AIMonitor.next"
chmod +x "$BUNDLE/Contents/MacOS/AIMonitor.next"
mv "$BUNDLE/Contents/MacOS/AIMonitor.next" "$BUNDLE/Contents/MacOS/AIMonitor"
cp "$ROOT_DIR/Resources/Info.plist" "$BUNDLE/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$BUNDLE" >/dev/null

case "$MODE" in
  --build) printf 'Built %s\n' "$BUNDLE" ;;
  run) /usr/bin/open -n "$BUNDLE" --args --show ;;
  --verify) /usr/bin/open -n "$BUNDLE" --args --show; sleep 2; pgrep -x AIMonitor >/dev/null ;;
  --debug) lldb -- "$BUNDLE/Contents/MacOS/AIMonitor" --show ;;
  --logs) /usr/bin/open -n "$BUNDLE" --args --show; /usr/bin/log stream --info --style compact --predicate 'process == "AIMonitor"' ;;
  --telemetry) /usr/bin/open -n "$BUNDLE" --args --show; /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.aimonitor.app"' ;;
  *) printf 'Usage: %s [run|--build|--verify|--debug|--logs|--telemetry]\n' "$0" >&2; exit 2 ;;
esac
