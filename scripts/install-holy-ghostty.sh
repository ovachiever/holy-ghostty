#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
CONFIGURATION=${1:-Debug}
APP_NAME="Holy Ghostty.app"
BUILD_DIR="$ROOT_DIR/macos/build/$CONFIGURATION"
APP_PATH="$BUILD_DIR/$APP_NAME"
DESTINATION="/Applications/$APP_NAME"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
ENTITLEMENTS="$ROOT_DIR/macos/GhosttyReleaseLocal.entitlements"

find_codesign_identity() {
  if [ "${HOLY_GHOSTTY_CODE_SIGN_IDENTITY:-}" ]; then
    printf '%s\n' "$HOLY_GHOSTTY_CODE_SIGN_IDENTITY"
    return 0
  fi

  /usr/bin/security find-identity -v -p codesigning 2>/dev/null \
    | /usr/bin/awk -F '"' '
      /"Developer ID Application:/ { print "1|" $2 }
      /"Apple Development:/ { print "2|" $2 }
    ' \
    | /usr/bin/sort \
    | /usr/bin/awk -F '|' 'NR == 1 { print $2 }'
}

sign_installed_app() {
  if [ "${HOLY_GHOSTTY_SKIP_STABLE_SIGNING:-}" = "1" ]; then
    printf 'Skipped stable code signing because HOLY_GHOSTTY_SKIP_STABLE_SIGNING=1\n'
    return 0
  fi

  identity=$(find_codesign_identity)
  if [ -z "$identity" ]; then
    printf 'Warning: no Developer ID Application or Apple Development signing identity found; installed app keeps its build signature and may need renewed macOS privacy grants after rebuilds.\n' >&2
    return 0
  fi

  /usr/bin/codesign \
    --force \
    --timestamp=none \
    --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign "$identity" \
    "$DESTINATION"
  /usr/bin/codesign --verify --deep --strict "$DESTINATION"
  printf 'Signed %s with %s\n' "$DESTINATION" "$identity"
}

if [ "${HOLY_GHOSTTY_SKIP_BUILD:-}" != "1" ]; then
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
elif [ ! -d "$APP_PATH" ]; then
  printf 'Build output not found at %s\n' "$APP_PATH" >&2
  exit 1
fi

/usr/bin/pkill -f '/Applications/Holy Ghostty.app/Contents/MacOS/holy-ghostty' >/dev/null 2>&1 || true

if [ -d "$DESTINATION" ]; then
  "$LSREGISTER" -u "$DESTINATION" >/dev/null 2>&1 || true
  rm -rf "$DESTINATION"
fi

/usr/bin/ditto "$APP_PATH" "$DESTINATION"
/usr/bin/xattr -cr "$DESTINATION" >/dev/null 2>&1 || true
sign_installed_app
/usr/bin/touch "$DESTINATION"
"$LSREGISTER" -f -R -trusted "$DESTINATION"
printf 'Installed %s\n' "$DESTINATION"
