#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
CONFIGURATION=${1:-ReleaseLocal}
APP_NAME="Holy Ghostty.app"
BUILD_DIR="$ROOT_DIR/macos/build/$CONFIGURATION"
APP_PATH="$BUILD_DIR/$APP_NAME"
DESTINATION="/Applications/$APP_NAME"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
ENTITLEMENTS="$ROOT_DIR/macos/GhosttyReleaseLocal.entitlements"
EXPECTED_BUNDLE_ID="org.holyghostty.app"

if [ "$#" -gt 1 ]; then
  printf 'Usage: %s [ReleaseLocal]\n' "$0" >&2
  exit 64
fi

case "$CONFIGURATION" in
  ReleaseLocal) ;;
  *)
    printf 'Refusing to install %s. /Applications Holy Ghostty installs must use ReleaseLocal.\n' "$CONFIGURATION" >&2
    exit 64
    ;;
esac

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

INFO_PLIST="$APP_PATH/Contents/Info.plist"
ACTUAL_BUNDLE_ID=$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$INFO_PLIST" 2>/dev/null || true)
if [ "$ACTUAL_BUNDLE_ID" != "$EXPECTED_BUNDLE_ID" ]; then
  printf 'Refusing to install %s: expected bundle id %s, got %s\n' "$APP_PATH" "$EXPECTED_BUNDLE_ID" "${ACTUAL_BUNDLE_ID:-<none>}" >&2
  exit 65
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
