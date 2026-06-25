#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Turbo"
BUNDLE_ID="TannerFaust.Turbotask"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/.deriveddata-release"
BUILD_APP="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
INSTALL_APP="/Applications/$APP_NAME.app"
APP_BINARY="$INSTALL_APP/Contents/MacOS/$APP_NAME"

build_release() {
  xcodebuild \
    -project "$ROOT_DIR/Turbotask.xcodeproj" \
    -scheme Turbotask \
    -configuration Release \
    -destination "platform=macOS,arch=arm64" \
    -derivedDataPath "$DERIVED_DATA" \
    build
}

install_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  rm -rf "$INSTALL_APP"
  ditto "$BUILD_APP" "$INSTALL_APP"
  /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R -trusted "$INSTALL_APP"
}

open_app() {
  /usr/bin/open "$INSTALL_APP"
}

build_release
install_app

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
