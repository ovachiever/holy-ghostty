#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
CONFIGURATION=${1:-ReleaseLocal}
APP_NAME="Holy Ghostty.app"
BUILD_DIR="$ROOT_DIR/macos/build/$CONFIGURATION"
APP_PATH="$BUILD_DIR/$APP_NAME"
ENTITLEMENTS="$ROOT_DIR/macos/GhosttyReleaseLocal.entitlements"
EXPECTED_BUNDLE_ID="org.holyghostty.app"
CORE_TOOL="$ROOT_DIR/scripts/build-holy-ghostty-core.sh"
DEFAULT_LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
TESTING=${HOLY_GHOSTTY_TESTING:-0}

if [ "$TESTING" = "1" ]; then
  APPLICATIONS_DIR=${HOLY_GHOSTTY_APPLICATIONS_DIR:?HOLY_GHOSTTY_APPLICATIONS_DIR is required in test mode}
  XCODEBUILD=${HOLY_GHOSTTY_XCODEBUILD:?HOLY_GHOSTTY_XCODEBUILD is required in test mode}
  LSREGISTER=${HOLY_GHOSTTY_LSREGISTER:?HOLY_GHOSTTY_LSREGISTER is required in test mode}
  PKILL=${HOLY_GHOSTTY_PKILL:?HOLY_GHOSTTY_PKILL is required in test mode}
  TEST_TMP_ROOT=${TMPDIR:-/tmp}
  TEST_TMP_ROOT=${TEST_TMP_ROOT%/}
  case "$TEST_TMP_ROOT" in
    ""|/) printf 'Test mode refuses an unsafe temporary root.\n' >&2; exit 64 ;;
  esac
  CANONICAL_APPLICATIONS_DIR=$(/bin/realpath "$APPLICATIONS_DIR" 2>/dev/null || true)
  [ "$CANONICAL_APPLICATIONS_DIR" != "/Applications" ] || { printf 'Test mode refuses /Applications.\n' >&2; exit 64; }
  case "$APPLICATIONS_DIR" in
    "$TEST_TMP_ROOT"/*|/tmp/*|/private/tmp/*) ;;
    *) printf 'Test mode requires a temporary Applications directory.\n' >&2; exit 64 ;;
  esac
else
  APPLICATIONS_DIR="/Applications"
  XCODEBUILD="/usr/bin/xcodebuild"
  LSREGISTER="$DEFAULT_LSREGISTER"
  PKILL="/usr/bin/pkill"
  PGREP="/usr/bin/pgrep"
fi

if [ "$TESTING" = "1" ]; then
  PGREP=${HOLY_GHOSTTY_PGREP:?HOLY_GHOSTTY_PGREP is required in test mode}
fi

DESTINATION="$APPLICATIONS_DIR/$APP_NAME"
LOCK_FILE="$APPLICATIONS_DIR/.holy-ghostty-install.lock"
INSTALL_STAGE="$APPLICATIONS_DIR/.holy-ghostty-install.$$"
STAGED_APP="$INSTALL_STAGE/$APP_NAME"
BACKUP_APP="$INSTALL_STAGE/previous.app"
FAILED_APP="$INSTALL_STAGE/failed.app"
SWAP_ACTIVE=0
HAD_DESTINATION=0
PUBLISHED_DESTINATION=0
ROLLBACK_FAILED=0
LOCK_HELD=0

rollback_install() {
  [ "$SWAP_ACTIVE" -eq 1 ] || return 0
  set +e
  if [ "$PUBLISHED_DESTINATION" -eq 1 ] && { [ -e "$DESTINATION" ] || [ -L "$DESTINATION" ]; }; then
    if ! /bin/mv "$DESTINATION" "$FAILED_APP"; then
      ROLLBACK_FAILED=1
    fi
  fi
  if [ "$HAD_DESTINATION" -eq 1 ] && { [ -e "$BACKUP_APP" ] || [ -L "$BACKUP_APP" ]; }; then
    if [ -e "$DESTINATION" ] || [ -L "$DESTINATION" ]; then
      ROLLBACK_FAILED=1
    elif /bin/mv "$BACKUP_APP" "$DESTINATION"; then
      "$LSREGISTER" -f -R -trusted "$DESTINATION" >/dev/null 2>&1
    else
      ROLLBACK_FAILED=1
    fi
  fi
  SWAP_ACTIVE=0
  set -e
}

cleanup() {
  status=$?
  trap - 0 1 2 3 15
  rollback_install
  if [ "$ROLLBACK_FAILED" -eq 0 ]; then
    /bin/rm -rf "$INSTALL_STAGE"
  else
    printf 'Holy Ghostty install: rollback could not complete; recovery bundle preserved at %s\n' "$INSTALL_STAGE" >&2
  fi
  if [ "$LOCK_HELD" -eq 1 ]; then
    /bin/rm -f "$LOCK_FILE"
  fi
  exit "$status"
}
trap cleanup 0 1 2 3 15

fail() {
  printf 'Holy Ghostty install: %s\n' "$*" >&2
  exit 1
}

acquire_install_lock() {
  /bin/mkdir -p "$APPLICATIONS_DIR"
  attempts=0
  while ! /usr/bin/shlock -f "$LOCK_FILE" -p "$$"; do
    attempts=$((attempts + 1))
    [ "$attempts" -lt 60 ] || fail "timed out waiting for another Holy Ghostty install"
    /bin/sleep 1
  done
  LOCK_HELD=1
}

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

if [ -n "${HOLY_GHOSTTY_SKIP_BUILD:-}" ]; then
  printf 'HOLY_GHOSTTY_SKIP_BUILD is no longer supported: the canonical installer always proves the Swift and Zig build together.\n' >&2
  exit 64
fi

acquire_install_lock

find_codesign_identity() {
  if [ -n "${HOLY_GHOSTTY_CODE_SIGN_IDENTITY:-}" ]; then
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

sign_staged_app() {
  app=$1
  if [ "${HOLY_GHOSTTY_SKIP_STABLE_SIGNING:-}" = "1" ]; then
    printf 'Skipped stable code signing because HOLY_GHOSTTY_SKIP_STABLE_SIGNING=1\n'
  else
    identity=$(find_codesign_identity)
    if [ -n "$identity" ]; then
      /usr/bin/codesign \
        --force \
        --timestamp=none \
        --options runtime \
        --entitlements "$ENTITLEMENTS" \
        --sign "$identity" \
        "$app"
      printf 'Signed staged app with %s\n' "$identity"
    else
      printf 'Warning: no Developer ID Application or Apple Development signing identity found; the app keeps its build signature and may need renewed macOS privacy grants after rebuilds.\n' >&2
    fi
  fi

  /usr/bin/codesign --verify --deep --strict "$app"
}

verify_app_bundle() {
  app=$1
  info_plist="$app/Contents/Info.plist"
  executable="$app/Contents/MacOS/holy-ghostty"
  [ -f "$info_plist" ] || fail "Info.plist is missing from $app"
  actual_bundle_id=$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$info_plist" 2>/dev/null || true)
  [ "$actual_bundle_id" = "$EXPECTED_BUNDLE_ID" ] || fail "expected bundle id $EXPECTED_BUNDLE_ID, got ${actual_bundle_id:-<none>}"
  "$CORE_TOOL" verify-app "$executable"
  /usr/bin/codesign --verify --deep --strict "$app"
}

verify_release_settings() {
  if ! settings=$(
    cd "$ROOT_DIR/macos"
    env -i \
      HOME="$HOME" \
      PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin" \
      "$XCODEBUILD" \
      -project Ghostty.xcodeproj \
      -target Ghostty \
      -configuration "$CONFIGURATION" \
      -showBuildSettings
  ); then
    fail "could not inspect ReleaseLocal build settings"
  fi

  setting_value() {
    key=$1
    printf '%s\n' "$settings" | /usr/bin/awk -F ' = ' -v key="$key" '$1 ~ "^[[:space:]]*" key "$" { print $2; exit }'
  }

  [ "$(setting_value CONFIGURATION)" = "ReleaseLocal" ] || fail "Xcode did not resolve the ReleaseLocal configuration"
  [ "$(setting_value SWIFT_OPTIMIZATION_LEVEL)" = "-O" ] || fail "ReleaseLocal Swift optimization is not -O"
  [ "$(setting_value SWIFT_COMPILATION_MODE)" = "wholemodule" ] || fail "ReleaseLocal Swift compilation mode is not wholemodule"
  [ "$(setting_value ENABLE_NS_ASSERTIONS)" = "NO" ] || fail "ReleaseLocal assertions are enabled"
  [ "$(setting_value GCC_OPTIMIZATION_LEVEL)" = "fast" ] || fail "ReleaseLocal native optimization is not fast"
  [ "$(setting_value ENABLE_TESTABILITY)" = "NO" ] || fail "ReleaseLocal testability is enabled"

  active_conditions=" $(setting_value SWIFT_ACTIVE_COMPILATION_CONDITIONS) "
  case "$active_conditions" in
    *" DEBUG "*) fail "ReleaseLocal has the DEBUG Swift compilation condition" ;;
  esac
  swift_flags=$(setting_value OTHER_SWIFT_FLAGS)
  case "$swift_flags" in
    *-Onone*|*"-DDEBUG"*|*"-D DEBUG"*) fail "ReleaseLocal has Debug or unoptimized Swift flags" ;;
  esac
  for flags_key in OTHER_CFLAGS OTHER_CPLUSPLUSFLAGS; do
    case "$(setting_value "$flags_key")" in
      *-O0*) fail "ReleaseLocal has -O0 in $flags_key" ;;
    esac
  done
  case " $(setting_value GCC_PREPROCESSOR_DEFINITIONS) " in
    *" DEBUG=1 "*|*" DEBUG "*) fail "ReleaseLocal has a DEBUG native compilation condition" ;;
  esac
  printf 'Verified ReleaseLocal compiler settings (-O, wholemodule, assertions off).\n'
}

old_app_running() {
  set +e
  "$PGREP" -x holy-ghostty >/dev/null 2>&1
  inspect_status=$?
  set -e
  case "$inspect_status" in
    0) return 0 ;;
    1) return 1 ;;
    *) fail "could not inspect the running Holy Ghostty process" ;;
  esac
}

stop_old_app() {
  old_app_running || return 0
  "$PKILL" -x holy-ghostty >/dev/null 2>&1 || true
  attempts=0
  while old_app_running; do
    attempts=$((attempts + 1))
    [ "$attempts" -lt 5 ] || break
    /bin/sleep 1
  done
  old_app_running || return 0

  "$PKILL" -9 -x holy-ghostty >/dev/null 2>&1 || true
  attempts=0
  while old_app_running; do
    attempts=$((attempts + 1))
    [ "$attempts" -lt 2 ] || break
    /bin/sleep 1
  done
  if old_app_running; then
    fail "verified app was not installed because the old Holy Ghostty process could not be stopped"
  fi
  return 0
}

verify_release_settings

if "$CORE_TOOL" verify >/dev/null 2>&1; then
  printf 'Reusing the verified ReleaseFast core payload for the current inputs.\n'
else
  "$CORE_TOOL" build
fi

(
  cd "$ROOT_DIR/macos"
  env -i \
    HOME="$HOME" \
    PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin" \
    "$XCODEBUILD" \
    -project Ghostty.xcodeproj \
    -scheme Ghostty \
    -configuration "$CONFIGURATION" \
    "SYMROOT=build" \
    build
)

verify_app_bundle "$APP_PATH"

/bin/mkdir -p "$APPLICATIONS_DIR"
/bin/rm -rf "$INSTALL_STAGE"
/bin/mkdir -p "$INSTALL_STAGE"
/usr/bin/ditto "$APP_PATH" "$STAGED_APP"
/usr/bin/xattr -cr "$STAGED_APP" >/dev/null 2>&1 || true
sign_staged_app "$STAGED_APP"
verify_app_bundle "$STAGED_APP"

SWAP_ACTIVE=1
if [ -e "$DESTINATION" ] || [ -L "$DESTINATION" ]; then
  HAD_DESTINATION=1
  /bin/mv "$DESTINATION" "$BACKUP_APP"
fi
PUBLISHED_DESTINATION=1
/bin/mv "$STAGED_APP" "$DESTINATION"

# Registration and final validation happen before the old process is stopped.
# Any failure here restores the prior bundle while that process is still alive.
/usr/bin/touch "$DESTINATION"
"$LSREGISTER" -f -R -trusted "$DESTINATION"
verify_app_bundle "$DESTINATION"
stop_old_app
SWAP_ACTIVE=0
printf 'Installed %s\n' "$DESTINATION"
