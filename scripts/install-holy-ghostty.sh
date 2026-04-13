#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
CONFIGURATION=${1:-Debug}
APP_NAME="Holy Ghostty.app"
BUILD_DIR="$ROOT_DIR/macos/build/$CONFIGURATION"
APP_PATH="$BUILD_DIR/$APP_NAME"
DESTINATION="/Applications/$APP_NAME"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

if [ ! -d "$APP_PATH" ]; then
  (
    cd "$ROOT_DIR/macos"
    env -i \
      HOME="$HOME" \
      PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin" \
      xcodebuild \
      -project Ghostty.xcodeproj \
      -scheme Ghostty \
      -configuration "$CONFIGURATION" \
      "SYMROOT=build" \
      build
  )
fi

/usr/bin/pkill -f '/Applications/Holy Ghostty.app/Contents/MacOS/ghostty' >/dev/null 2>&1 || true

if [ -d "$DESTINATION" ]; then
  "$LSREGISTER" -u "$DESTINATION" >/dev/null 2>&1 || true
  rm -rf "$DESTINATION"
fi

/usr/bin/ditto "$APP_PATH" "$DESTINATION"
/usr/bin/xattr -cr "$DESTINATION" >/dev/null 2>&1 || true
/usr/bin/touch "$DESTINATION"
"$LSREGISTER" -f -R -trusted "$DESTINATION"
printf 'Installed %s\n' "$DESTINATION"
