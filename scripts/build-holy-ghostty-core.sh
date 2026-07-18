#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
LIVE_FRAMEWORK="$ROOT_DIR/macos/GhosttyKit.xcframework"
LIVE_RESOURCE_DIR="$ROOT_DIR/zig-out/share"
LOCK_DIR="$ROOT_DIR/.zig-cache"
LOCK_FILE="$LOCK_DIR/holy-ghostty-core.lock"
EXPECTED_OPTIMIZE="ReleaseFast"
RESOURCE_NAMES="bat ghostty vim nvim locale fish man terminfo zsh bash-completion"
WORK_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/holy-ghostty-core.XXXXXX")
BUILD_STAGE=""
LOCK_HELD=0
PUBLISH_ACTIVE=0
HAD_FRAMEWORK=0
HAD_RESOURCES=0
PUBLISHED_FRAMEWORK=0
PUBLISHED_RESOURCES=0
ROLLBACK_FAILED=0

FRAMEWORK="$LIVE_FRAMEWORK"
RESOURCE_DIR="$LIVE_RESOURCE_DIR"
RECEIPT="$FRAMEWORK/.holy-ghostty-core"
MACOS_LIBRARY="$FRAMEWORK/macos-arm64_x86_64/libghostty.a"

fail() {
  printf 'Holy Ghostty core: %s\n' "$*" >&2
  exit 1
}

use_payload() {
  FRAMEWORK=$1
  RESOURCE_DIR=$2
  RECEIPT="$FRAMEWORK/.holy-ghostty-core"
  MACOS_LIBRARY="$FRAMEWORK/macos-arm64_x86_64/libghostty.a"
}

rollback_publish() {
  [ "$PUBLISH_ACTIVE" -eq 1 ] || return 0
  set +e

  if [ "$PUBLISHED_FRAMEWORK" -eq 1 ] && { [ -e "$LIVE_FRAMEWORK" ] || [ -L "$LIVE_FRAMEWORK" ]; }; then
    if ! /bin/mv "$LIVE_FRAMEWORK" "$BUILD_STAGE/failed-framework"; then
      ROLLBACK_FAILED=1
    fi
  fi
  if [ "$HAD_FRAMEWORK" -eq 1 ] && { [ -e "$BUILD_STAGE/previous-framework" ] || [ -L "$BUILD_STAGE/previous-framework" ]; }; then
    if [ -e "$LIVE_FRAMEWORK" ] || [ -L "$LIVE_FRAMEWORK" ]; then
      ROLLBACK_FAILED=1
    elif ! /bin/mv "$BUILD_STAGE/previous-framework" "$LIVE_FRAMEWORK"; then
      ROLLBACK_FAILED=1
    fi
  fi

  if [ "$PUBLISHED_RESOURCES" -eq 1 ] && { [ -e "$LIVE_RESOURCE_DIR" ] || [ -L "$LIVE_RESOURCE_DIR" ]; }; then
    if ! /bin/mv "$LIVE_RESOURCE_DIR" "$BUILD_STAGE/failed-resources"; then
      ROLLBACK_FAILED=1
    fi
  fi
  if [ "$HAD_RESOURCES" -eq 1 ] && { [ -e "$BUILD_STAGE/previous-resources" ] || [ -L "$BUILD_STAGE/previous-resources" ]; }; then
    if [ -e "$LIVE_RESOURCE_DIR" ] || [ -L "$LIVE_RESOURCE_DIR" ]; then
      ROLLBACK_FAILED=1
    elif ! /bin/mkdir -p "$(dirname "$LIVE_RESOURCE_DIR")" || ! /bin/mv "$BUILD_STAGE/previous-resources" "$LIVE_RESOURCE_DIR"; then
      ROLLBACK_FAILED=1
    fi
  fi

  PUBLISH_ACTIVE=0
  set -e
}

cleanup() {
  status=$?
  trap - 0 1 2 3 15
  rollback_publish
  if [ "$LOCK_HELD" -eq 1 ]; then
    /bin/rm -f "$LOCK_FILE"
  fi
  /bin/rm -rf "$WORK_DIR"
  if [ -n "$BUILD_STAGE" ] && [ "$ROLLBACK_FAILED" -eq 0 ]; then
    /bin/rm -rf "$BUILD_STAGE"
  elif [ -n "$BUILD_STAGE" ]; then
    printf 'Holy Ghostty core: rollback could not complete; recovery payload preserved at %s\n' "$BUILD_STAGE" >&2
  fi
  exit "$status"
}
trap cleanup 0 1 2 3 15

zon_value() {
  key=$1
  value=$(/usr/bin/awk -v key="$key" '
    $0 ~ "\\." key "[[:space:]]*=" {
      line = $0
      sub(".*\\." key "[[:space:]]*=[[:space:]]*\\\"", "", line)
      sub("\\\".*", "", line)
      print line
      exit
    }
  ' "$ROOT_DIR/build.zig.zon")
  [ -n "$value" ] || fail "could not read $key from build.zig.zon"
  printf '%s\n' "$value"
}

required_zig_version() {
  zon_value minimum_zig_version
}

core_base_version() {
  zon_value version
}

sha256_file() {
  /usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{ print $1 }'
}

hash_null_manifest() {
  raw_manifest=$1
  label=$2
  sorted_manifest="$WORK_DIR/$label.sorted"
  digest_manifest="$WORK_DIR/$label.digests"

  [ -s "$raw_manifest" ] || fail "$label manifest is empty"
  LC_ALL=C /usr/bin/sort -z "$raw_manifest" > "$sorted_manifest" || fail "could not sort $label manifest"
  /usr/bin/xargs -0 /usr/bin/shasum -a 256 < "$sorted_manifest" > "$digest_manifest" || fail "could not hash $label files"
  sha256_file "$digest_manifest"
}

input_fingerprint() {
  raw_manifest="$WORK_DIR/inputs.raw"
  if ! (
    cd "$ROOT_DIR"
    /usr/bin/git ls-files -z --cached --others --exclude-standard -- \
      VERSION \
      build.zig \
      build.zig.zon \
      scripts/build-holy-ghostty-core.sh \
      src \
      include \
      pkg \
      vendor \
      po \
      images
  ) > "$raw_manifest"; then
    fail "could not enumerate core inputs with git"
  fi
  (
    cd "$ROOT_DIR"
    hash_null_manifest "$raw_manifest" inputs
  )
}

tree_fingerprint() {
  tree=$1
  label=$2
  excluded_name=${3:-}
  raw_manifest="$WORK_DIR/$label.raw"

  [ -d "$tree" ] || fail "$label tree is missing at $tree"
  if [ -n "$excluded_name" ]; then
    if ! (
      cd "$tree"
      /usr/bin/find . \( -type f -o -type l \) ! -name "$excluded_name" -print0
    ) > "$raw_manifest"; then
      fail "could not enumerate $label payload"
    fi
  elif ! (
    cd "$tree"
    /usr/bin/find . \( -type f -o -type l \) -print0
  ) > "$raw_manifest"; then
    fail "could not enumerate $label payload"
  fi

  (
    cd "$tree"
    hash_null_manifest "$raw_manifest" "$label"
  )
}

framework_fingerprint() {
  tree_fingerprint "$FRAMEWORK" framework .holy-ghostty-core
}

resource_fingerprint() {
  tree_fingerprint "$RESOURCE_DIR" resources
}

receipt_value() {
  key=$1
  /usr/bin/awk -F '=' -v key="$key" '$1 == key { print substr($0, length(key) + 2); exit }' "$RECEIPT"
}

ci_fallback() {
  printf 'Use the newest HolyGhostty-Core-ReleaseFast artifact from the Build Holy macOS core workflow whose core inputs match this checkout. Import its contained zip with `scripts/build-holy-ghostty-core.sh import <archive>`, then rerun the installer.\n' >&2
  printf 'The importer rejects incomplete, Debug, wrong-source, or tampered payloads before publishing them.\n' >&2
  printf 'Maintainers can create it with: gh workflow run build-holy-macos.yml --ref <branch>\n' >&2
}

resolve_zig() {
  required=$(required_zig_version)

  if [ -n "${HOLY_GHOSTTY_ZIG:-}" ]; then
    [ -x "$HOLY_GHOSTTY_ZIG" ] || fail "HOLY_GHOSTTY_ZIG is not executable: $HOLY_GHOSTTY_ZIG"
    actual=$("$HOLY_GHOSTTY_ZIG" version 2>/dev/null || true)
    [ "$actual" = "$required" ] || fail "HOLY_GHOSTTY_ZIG reports $actual; exactly $required is required"
    printf '%s\n' "$HOLY_GHOSTTY_ZIG"
    return
  fi

  path_zig=$(command -v zig 2>/dev/null || true)
  for candidate in \
    "$path_zig" \
    "/opt/homebrew/opt/zig@0.15/bin/zig" \
    "/usr/local/opt/zig@0.15/bin/zig"
  do
    [ -n "$candidate" ] || continue
    [ -x "$candidate" ] || continue
    actual=$("$candidate" version 2>/dev/null || true)
    if [ "$actual" = "$required" ]; then
      printf '%s\n' "$candidate"
      return
    fi
  done

  found=${path_zig:-<none>}
  actual=""
  if [ "$found" != "<none>" ]; then
    actual=$("$found" version 2>/dev/null || true)
  fi
  printf 'Holy Ghostty requires Zig %s; PATH resolves %s%s.\n' \
    "$required" \
    "$found" \
    "${actual:+ (version $actual)}" >&2
  printf 'Install the pinned compiler with `brew install zig@0.15`, then set HOLY_GHOSTTY_ZIG to its absolute path, or enter the repo Nix development shell.\n' >&2
  ci_fallback
  exit 69
}

validate_payload() {
  expected_version=$1
  [ -f "$FRAMEWORK/Info.plist" ] || fail "framework Info.plist is missing"
  [ -f "$MACOS_LIBRARY" ] || fail "macOS libghostty.a is missing"
  [ -d "$RESOURCE_DIR" ] || fail "generated resources are missing at $RESOURCE_DIR"

  for name in $RESOURCE_NAMES; do
    [ -d "$RESOURCE_DIR/$name" ] || fail "generated resource directory is missing: zig-out/share/$name"
  done

  lipo_bin=${HOLY_GHOSTTY_LIPO:-/usr/bin/lipo}
  [ -x "$lipo_bin" ] || fail "lipo is unavailable at $lipo_bin"
  arches=$($lipo_bin -archs "$MACOS_LIBRARY" 2>/dev/null || true)
  case " $arches " in
    *" arm64 "*) ;;
    *) fail "macOS core is missing arm64; found: ${arches:-<none>}" ;;
  esac
  case " $arches " in
    *" x86_64 "*) ;;
    *) fail "macOS core is missing x86_64; found: ${arches:-<none>}" ;;
  esac

  /usr/bin/grep -a -F -q "$expected_version" "$MACOS_LIBRARY" || fail "macOS core archive does not contain the fingerprinted version $expected_version"
}

verify_core_unlocked() {
  [ -f "$RECEIPT" ] || fail "build receipt is missing; run scripts/build-holy-ghostty-core.sh build"

  schema=$(receipt_value schema)
  optimize=$(receipt_value optimize)
  zig_version=$(receipt_value zig_version)
  expected_zig=$(required_zig_version)
  recorded_inputs=$(receipt_value input_sha256)
  recorded_framework=$(receipt_value framework_sha256)
  recorded_resources=$(receipt_value resources_sha256)
  recorded_library=$(receipt_value macos_library_sha256)
  recorded_version=$(receipt_value core_version)
  current_inputs=$(input_fingerprint)
  current_framework=$(framework_fingerprint)
  current_resources=$(resource_fingerprint)
  current_library=$(sha256_file "$MACOS_LIBRARY")
  expected_version="$(core_base_version)+holy.$current_inputs"

  [ "$schema" = "2" ] || fail "unsupported build-receipt schema: ${schema:-<none>}"
  [ "$optimize" = "$EXPECTED_OPTIMIZE" ] || fail "core mode is ${optimize:-<none>}; $EXPECTED_OPTIMIZE is required"
  [ "$zig_version" = "$expected_zig" ] || fail "core used Zig ${zig_version:-<none>}; $expected_zig is required"
  [ "$recorded_inputs" = "$current_inputs" ] || fail "core sources changed after the payload was built"
  [ "$recorded_framework" = "$current_framework" ] || fail "framework payload does not match its build receipt"
  [ "$recorded_resources" = "$current_resources" ] || fail "generated resources do not match their build receipt"
  [ "$recorded_library" = "$current_library" ] || fail "macOS core archive does not match its build receipt"
  [ "$recorded_version" = "$expected_version" ] || fail "recorded core version does not match current source fingerprint"
  validate_payload "$expected_version"

  printf 'Verified Holy core payload: %s, Zig %s, inputs %s\n' \
    "$EXPECTED_OPTIMIZE" \
    "$expected_zig" \
    "$current_inputs"
}

verify_app_unlocked() {
  executable=$1
  [ -x "$executable" ] || fail "app executable is missing or not executable: $executable"
  verify_core_unlocked

  if ! version_output=$("$executable" +version 2>&1); then
    printf 'Holy Ghostty core: unable to inspect the linked app core:\n%s\n' "$version_output" >&2
    exit 1
  fi

  actual_mode=$(printf '%s\n' "$version_output" | /usr/bin/awk -F ':' '/build mode/ { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit }')
  actual_zig=$(printf '%s\n' "$version_output" | /usr/bin/awk -F ':' '/Zig version/ { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit }')
  actual_version=$(printf '%s\n' "$version_output" | /usr/bin/awk -F ':' '/^[[:space:]]*- version:/ { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit }')
  expected_zig=$(receipt_value zig_version)
  expected_version=$(receipt_value core_version)

  [ "$actual_mode" = ".ReleaseFast" ] || fail "linked app core is ${actual_mode:-<unknown>}; .ReleaseFast is required"
  [ "$actual_zig" = "$expected_zig" ] || fail "linked app core reports Zig ${actual_zig:-<unknown>}; $expected_zig is required"
  [ "$actual_version" = "$expected_version" ] || fail "app core version ${actual_version:-<unknown>} does not match verified framework $expected_version"

  printf 'Verified linked app core: %s, Zig %s, %s\n' "$actual_mode" "$actual_zig" "$actual_version"
}

acquire_lock() {
  /bin/mkdir -p "$LOCK_DIR"
  attempts=0
  while ! /usr/bin/shlock -f "$LOCK_FILE" -p "$$"; do
    attempts=$((attempts + 1))
    [ "$attempts" -lt 60 ] || fail "timed out waiting for the Ghostty core build lock at $LOCK_FILE"
    /bin/sleep 1
  done
  LOCK_HELD=1
}

publish_payload() {
  staged_framework="$BUILD_STAGE/macos/GhosttyKit.xcframework"
  staged_resources="$BUILD_STAGE/zig-out/share"
  [ -d "$staged_framework" ] || fail "staged framework is missing"
  [ -d "$staged_resources" ] || fail "staged resources are missing"

  PUBLISH_ACTIVE=1
  if [ -e "$LIVE_FRAMEWORK" ] || [ -L "$LIVE_FRAMEWORK" ]; then
    HAD_FRAMEWORK=1
    /bin/mv "$LIVE_FRAMEWORK" "$BUILD_STAGE/previous-framework"
  fi
  if [ -e "$LIVE_RESOURCE_DIR" ] || [ -L "$LIVE_RESOURCE_DIR" ]; then
    HAD_RESOURCES=1
    /bin/mv "$LIVE_RESOURCE_DIR" "$BUILD_STAGE/previous-resources"
  fi

  /bin/mkdir -p "$(dirname "$LIVE_FRAMEWORK")" "$(dirname "$LIVE_RESOURCE_DIR")"
  PUBLISHED_FRAMEWORK=1
  /bin/mv "$staged_framework" "$LIVE_FRAMEWORK"
  PUBLISHED_RESOURCES=1
  /bin/mv "$staged_resources" "$LIVE_RESOURCE_DIR"
  use_payload "$LIVE_FRAMEWORK" "$LIVE_RESOURCE_DIR"
}

build_core() {
  zig_bin=$(resolve_zig)
  zig_version=$(required_zig_version)
  acquire_lock
  BUILD_STAGE=$(/usr/bin/mktemp -d "$LOCK_DIR/holy-ghostty-core-stage.XXXXXX")
  stage_name=$(/usr/bin/basename "$BUILD_STAGE")
  /bin/mkdir -p "$BUILD_STAGE/macos"

  before=$(input_fingerprint)
  core_version="$(core_base_version)+holy.$before"

  printf 'Building the complete Holy core payload (%s, Zig %s)...\n' "$EXPECTED_OPTIMIZE" "$zig_version"
  if ! (
    cd "$ROOT_DIR"
    "$zig_bin" build \
      --prefix "$BUILD_STAGE/zig-out" \
      -Doptimize=ReleaseFast \
      -Demit-xcframework=true \
      -Demit-macos-app=false \
      -Dxcframework-target=universal \
      -Dholy-xcframework-stage="$stage_name" \
      -Demit-docs=false \
      -Dversion-string="$core_version"
  ); then
    printf 'Holy Ghostty core: the local ReleaseFast build failed. Your Zig may be unable to link against this macOS SDK.\n' >&2
    ci_fallback
    exit 1
  fi

  after=$(input_fingerprint)
  [ "$before" = "$after" ] || fail "core inputs changed during the build; rerun from a stable checkout"

  use_payload "$BUILD_STAGE/macos/GhosttyKit.xcframework" "$BUILD_STAGE/zig-out/share"
  validate_payload "$core_version"
  framework_sha=$(framework_fingerprint)
  resources_sha=$(resource_fingerprint)
  library_sha=$(sha256_file "$MACOS_LIBRARY")
  source_commit=$(/usr/bin/git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || printf 'unknown')
  workflow_run=${GITHUB_RUN_ID:-local}
  temp_receipt="$RECEIPT.tmp.$$"
  umask 022
  {
    printf 'schema=2\n'
    printf 'optimize=%s\n' "$EXPECTED_OPTIMIZE"
    printf 'zig_version=%s\n' "$zig_version"
    printf 'core_version=%s\n' "$core_version"
    printf 'input_sha256=%s\n' "$after"
    printf 'framework_sha256=%s\n' "$framework_sha"
    printf 'resources_sha256=%s\n' "$resources_sha"
    printf 'macos_library_sha256=%s\n' "$library_sha"
    printf 'source_commit=%s\n' "$source_commit"
    printf 'workflow_run=%s\n' "$workflow_run"
  } > "$temp_receipt"
  /bin/mv "$temp_receipt" "$RECEIPT"

  verify_core_unlocked
  publish_payload
  verify_core_unlocked
  PUBLISH_ACTIVE=0
}

import_core() {
  archive=$1
  [ -f "$archive" ] || fail "core payload archive is missing: $archive"
  acquire_lock
  BUILD_STAGE=$(/usr/bin/mktemp -d "$LOCK_DIR/holy-ghostty-core-import.XXXXXX")

  /usr/bin/ditto -x -k "$archive" "$BUILD_STAGE" || fail "could not extract core payload archive"
  use_payload "$BUILD_STAGE/macos/GhosttyKit.xcframework" "$BUILD_STAGE/zig-out/share"
  verify_core_unlocked
  publish_payload
  verify_core_unlocked
  PUBLISH_ACTIVE=0
}

usage() {
  printf 'Usage: %s build|verify|import <archive>|verify-app <executable>\n' "$0" >&2
  exit 64
}

case "${1:-build}" in
  build)
    [ "$#" -eq 1 ] || usage
    build_core
    ;;
  verify)
    [ "$#" -eq 1 ] || usage
    acquire_lock
    verify_core_unlocked
    ;;
  verify-app)
    [ "$#" -eq 2 ] || usage
    acquire_lock
    verify_app_unlocked "$2"
    ;;
  import)
    [ "$#" -eq 2 ] || usage
    import_core "$2"
    ;;
  *) usage ;;
esac
