#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
TEMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/holy-build-contract.XXXXXX")
trap '/bin/rm -rf "$TEMP_DIR"' 0 1 2 3 15

fail() {
  printf 'Holy build contract test: %s\n' "$*" >&2
  exit 1
}

TEST_REPO="$TEMP_DIR/repo"
/bin/mkdir -p \
  "$TEST_REPO/scripts" \
  "$TEST_REPO/macos" \
  "$TEST_REPO/src" \
  "$TEST_REPO/include" \
  "$TEST_REPO/pkg" \
  "$TEST_REPO/vendor" \
  "$TEST_REPO/po" \
  "$TEST_REPO/images"
/bin/cp "$ROOT_DIR/scripts/build-holy-ghostty-core.sh" "$TEST_REPO/scripts/"
/bin/cp "$ROOT_DIR/scripts/install-holy-ghostty.sh" "$TEST_REPO/scripts/"

printf 'pub fn build() void {}\n' > "$TEST_REPO/build.zig"
printf '.{ .name = .ghostty, .version = "1.3.2-dev", .minimum_zig_version = "0.15.2" }\n' > "$TEST_REPO/build.zig.zon"
printf 'const answer = 42;\n' > "$TEST_REPO/src/core.zig"
printf '#define GHOSTTY 1\n' > "$TEST_REPO/include/ghostty.h"
printf 'fixture\n' > "$TEST_REPO/pkg/fixture.txt"
printf 'fixture\n' > "$TEST_REPO/vendor/fixture.txt"
printf 'fixture\n' > "$TEST_REPO/po/fixture.po"
printf 'fixture\n' > "$TEST_REPO/images/fixture.txt"
printf '*.ignored\nmacos/GhosttyKit.xcframework/\nzig-out/\n.zig-cache/\n' > "$TEST_REPO/.gitignore"
printf '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict/></plist>\n' > "$TEST_REPO/macos/GhosttyReleaseLocal.entitlements"

(
  cd "$TEST_REPO"
  /usr/bin/git init -q
  /usr/bin/git add .gitignore build.zig build.zig.zon scripts src include pkg vendor po images macos/GhosttyReleaseLocal.entitlements
)

FAKE_ZIG="$TEMP_DIR/zig"
FAKE_LIPO="$TEMP_DIR/lipo"
FAKE_ZIG_LOG="$TEMP_DIR/zig-args"
export FAKE_ZIG_LOG

cat > "$FAKE_ZIG" <<'EOF'
#!/bin/sh
set -eu
if [ "${1:-}" = "version" ]; then
  printf '%s\n' "${FAKE_ZIG_VERSION:-0.15.2}"
  exit 0
fi
printf '%s\n' "$@" > "$FAKE_ZIG_LOG"
prefix="zig-out"
framework="macos/GhosttyKit.xcframework"
core_version=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --prefix)
      shift
      prefix=$1
      ;;
    -Dholy-xcframework-stage=*) framework=".zig-cache/${1#*=}/macos/GhosttyKit.xcframework" ;;
    -Dversion-string=*) core_version=${1#*=} ;;
  esac
  shift
done
[ -n "$core_version" ] || exit 70
mkdir -p "$framework/macos-arm64_x86_64"
printf '<plist version="1.0"></plist>\n' > "$framework/Info.plist"
printf 'release-fast-fixture %s\n' "$core_version" > "$framework/macos-arm64_x86_64/libghostty.a"
for name in bat ghostty vim nvim locale fish man terminfo zsh bash-completion; do
  mkdir -p "$prefix/share/$name"
  printf '%s resource\n' "$name" > "$prefix/share/$name/fixture.txt"
done
EOF

cat > "$FAKE_LIPO" <<'EOF'
#!/bin/sh
printf 'x86_64 arm64\n'
EOF

/bin/chmod +x "$FAKE_ZIG" "$FAKE_LIPO"

run_core_tool() {
  HOLY_GHOSTTY_ZIG="$FAKE_ZIG" \
  HOLY_GHOSTTY_LIPO="$FAKE_LIPO" \
    "$TEST_REPO/scripts/build-holy-ghostty-core.sh" "$@"
}

run_core_tool build >/dev/null
run_core_tool verify >/dev/null

RECEIPT="$TEST_REPO/macos/GhosttyKit.xcframework/.holy-ghostty-core"
[ -f "$RECEIPT" ] || fail "build did not write its receipt"
/usr/bin/grep -q '^schema=2$' "$RECEIPT" || fail "build did not write the complete-payload schema"
/usr/bin/grep -q '^optimize=ReleaseFast$' "$RECEIPT" || fail "receipt did not record ReleaseFast"
/usr/bin/grep -q '^zig_version=0.15.2$' "$RECEIPT" || fail "receipt did not record the pinned Zig version"
/usr/bin/grep -q '^resources_sha256=[0-9a-f][0-9a-f]*$' "$RECEIPT" || fail "receipt omitted generated resources"
/usr/bin/grep -q '^core_version=1.3.2-dev+holy\.[0-9a-f][0-9a-f]*$' "$RECEIPT" || fail "core version did not embed the source fingerprint"
/usr/bin/grep -q '^-Doptimize=ReleaseFast$' "$FAKE_ZIG_LOG" || fail "Zig build omitted ReleaseFast"
/usr/bin/grep -q '^-Demit-macos-app=false$' "$FAKE_ZIG_LOG" || fail "Zig build did not disable the app-copy path"
/usr/bin/grep -q '^-Dxcframework-target=universal$' "$FAKE_ZIG_LOG" || fail "Zig build did not require a universal framework"
/usr/bin/grep -q '^-Dholy-xcframework-stage=holy-ghostty-core-stage\.' "$FAKE_ZIG_LOG" || fail "Zig build did not use its confined framework staging path"
/usr/bin/grep -q '^--prefix$' "$FAKE_ZIG_LOG" || fail "Zig build did not stage generated resources"

CORE_VERSION=$(/usr/bin/awk -F '=' '$1 == "core_version" { print $2; exit }' "$RECEIPT")
/usr/bin/grep -a -F -q "$CORE_VERSION" "$TEST_REPO/macos/GhosttyKit.xcframework/macos-arm64_x86_64/libghostty.a" || fail "archive omitted the fingerprinted version"

FAKE_APP="$TEMP_DIR/holy-ghostty"
cat > "$FAKE_APP" <<EOF
#!/bin/sh
cat <<'VERSION'
Ghostty $CORE_VERSION

Version
  - version: $CORE_VERSION
Build Config
  - Zig version   : 0.15.2
  - build mode    : .ReleaseFast
VERSION
EOF
/bin/chmod +x "$FAKE_APP"
run_core_tool verify-app "$FAKE_APP" >/dev/null

/usr/bin/sed 's/\.ReleaseFast/.Debug/' "$FAKE_APP" > "$TEMP_DIR/debug-app"
/bin/chmod +x "$TEMP_DIR/debug-app"
if run_core_tool verify-app "$TEMP_DIR/debug-app" >"$TEMP_DIR/debug.out" 2>&1; then
  fail "app verification accepted a Debug core"
fi
/usr/bin/grep -q '.ReleaseFast is required' "$TEMP_DIR/debug.out" || fail "Debug-core failure was not actionable"

printf 'editor scratch\n' > "$TEST_REPO/src/editor.ignored"
run_core_tool verify >/dev/null || fail "ignored editor debris changed the core fingerprint"

printf 'const added = true;\n' > "$TEST_REPO/src/new.zig"
if run_core_tool verify >"$TEMP_DIR/untracked.out" 2>&1; then
  fail "verification accepted a new unignored core input"
fi
/bin/rm "$TEST_REPO/src/new.zig"

printf 'const answer = 43;\n' > "$TEST_REPO/src/core.zig"
if run_core_tool verify >"$TEMP_DIR/stale.out" 2>&1; then
  fail "verification accepted changed core sources"
fi
/usr/bin/grep -q 'core sources changed' "$TEMP_DIR/stale.out" || fail "stale-source failure was not actionable"

run_core_tool build >/dev/null
/bin/rm -rf "$TEST_REPO/zig-out/share/terminfo"
if run_core_tool verify >"$TEMP_DIR/resources.out" 2>&1; then
  fail "verification accepted missing generated resources"
fi
/usr/bin/grep -Eq 'generated resources do not match|resource directory is missing' "$TEMP_DIR/resources.out" || fail "resource failure was not actionable"

run_core_tool build >/dev/null
printf 'tampered\n' >> "$TEST_REPO/macos/GhosttyKit.xcframework/macos-arm64_x86_64/libghostty.a"
if run_core_tool verify >"$TEMP_DIR/tamper.out" 2>&1; then
  fail "verification accepted a tampered framework"
fi
/usr/bin/grep -Eq 'payload does not match|archive does not match' "$TEMP_DIR/tamper.out" || fail "tamper failure was not actionable"

run_core_tool build >/dev/null
if FAKE_ZIG_VERSION=0.16.0 run_core_tool build >"$TEMP_DIR/version.out" 2>&1; then
  fail "build accepted the wrong Zig version"
fi
/usr/bin/grep -q 'exactly 0.15.2 is required' "$TEMP_DIR/version.out" || fail "wrong-version failure was not actionable"
unset FAKE_ZIG_VERSION

/bin/chmod 500 "$TEST_REPO/zig-out"
if run_core_tool build >"$TEMP_DIR/publish.out" 2>&1; then
  /bin/chmod 700 "$TEST_REPO/zig-out"
  fail "core publication unexpectedly succeeded through a nonwritable resource parent"
fi
/bin/chmod 700 "$TEST_REPO/zig-out"
run_core_tool verify >/dev/null || fail "failed core publication did not preserve the prior payload"

ARTIFACT_ROOT="$TEMP_DIR/artifact"
ARTIFACT_ZIP="$TEMP_DIR/HolyGhostty-Core-ReleaseFast.zip"
/bin/mkdir -p "$ARTIFACT_ROOT/macos" "$ARTIFACT_ROOT/zig-out"
/usr/bin/ditto "$TEST_REPO/macos/GhosttyKit.xcframework" "$ARTIFACT_ROOT/macos/GhosttyKit.xcframework"
/usr/bin/ditto "$TEST_REPO/zig-out/share" "$ARTIFACT_ROOT/zig-out/share"
(cd "$ARTIFACT_ROOT" && /usr/bin/zip -qry "$ARTIFACT_ZIP" macos zig-out)
/bin/rm -rf "$TEST_REPO/macos/GhosttyKit.xcframework" "$TEST_REPO/zig-out/share"
run_core_tool import "$ARTIFACT_ZIP" >/dev/null
run_core_tool verify >/dev/null || fail "verified CI payload import did not publish a usable core"

# Exercise the real installer against isolated app, registration, and process
# fakes. This proves fresh-clone construction, failure-before-pkill, rollback,
# and successful replacement rather than only checking source-line order.
FAKE_XCODEBUILD="$TEMP_DIR/xcodebuild"
FAKE_LSREGISTER="$TEMP_DIR/lsregister"
FAKE_PKILL="$TEMP_DIR/pkill"
FAKE_PGREP="$TEMP_DIR/pgrep"
REGISTER_LOG="$TEMP_DIR/register.log"
PKILL_LOG="$TEMP_DIR/pkill.log"
PROCESS_STATE="$TEMP_DIR/old-app-running"
APPLICATIONS_DIR="$TEMP_DIR/Applications"
export REGISTER_LOG PKILL_LOG PROCESS_STATE

cat > "$FAKE_XCODEBUILD" <<'EOF'
#!/bin/sh
set -eu
case " $* " in
  *" -showBuildSettings "*)
    swift_optimization=-O
    [ ! -f .test-debug-settings ] || swift_optimization=-Onone
    printf '    CONFIGURATION = ReleaseLocal\n'
    printf '    ENABLE_NS_ASSERTIONS = NO\n'
    printf '    GCC_OPTIMIZATION_LEVEL = fast\n'
    printf '    SWIFT_COMPILATION_MODE = wholemodule\n'
    printf '    SWIFT_OPTIMIZATION_LEVEL = %s\n' "$swift_optimization"
    printf '    ENABLE_TESTABILITY = NO\n'
    if [ -f .test-debug-flags ]; then
      printf '    SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG\n'
      printf '    OTHER_SWIFT_FLAGS = -Onone -DDEBUG\n'
      printf '    OTHER_CFLAGS = -O0\n'
      printf '    GCC_PREPROCESSOR_DEFINITIONS = DEBUG=1\n'
    fi
    exit 0
    ;;
esac
[ ! -f .test-xcode-fail ] || exit 42
bundle_id=org.holyghostty.app
[ ! -f .test-bundle-id ] || bundle_id=$(cat .test-bundle-id)
receipt=GhosttyKit.xcframework/.holy-ghostty-core
core_version=$(awk -F '=' '$1 == "core_version" { print $2; exit }' "$receipt")
app="build/ReleaseLocal/Holy Ghostty.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
printf '%s\n' \
  '<?xml version="1.0" encoding="UTF-8"?>' \
  '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
  '<plist version="1.0"><dict>' \
  '<key>CFBundleExecutable</key><string>holy-ghostty</string>' \
  "<key>CFBundleIdentifier</key><string>$bundle_id</string>" \
  '<key>CFBundlePackageType</key><string>APPL</string>' \
  '</dict></plist>' > "$app/Contents/Info.plist"
{
  printf '#!/bin/sh\n'
  printf "cat <<'VERSION'\n"
  printf 'Ghostty %s\n\n' "$core_version"
  printf 'Version\n  - version: %s\n' "$core_version"
  printf 'Build Config\n  - Zig version   : 0.15.2\n  - build mode    : .ReleaseFast\n'
  printf 'VERSION\n'
} > "$app/Contents/MacOS/holy-ghostty"
chmod +x "$app/Contents/MacOS/holy-ghostty"
printf 'new build\n' > "$app/Contents/Resources/new-build.txt"
[ -f .test-unsigned ] || /usr/bin/codesign --force --sign - "$app"
EOF

cat > "$FAKE_LSREGISTER" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$REGISTER_LOG"
[ ! -f "${HOLY_TEST_REPO}/macos/.test-register-fail" ] || exit 71
EOF

cat > "$FAKE_PKILL" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$PKILL_LOG"
[ ! -f "${HOLY_TEST_REPO}/macos/.test-pkill-stuck" ] || exit 72
rm -f "$PROCESS_STATE"
EOF

cat > "$FAKE_PGREP" <<'EOF'
#!/bin/sh
[ -f "$PROCESS_STATE" ] || exit 1
printf '4242\n'
EOF

/bin/chmod +x "$FAKE_XCODEBUILD" "$FAKE_LSREGISTER" "$FAKE_PKILL" "$FAKE_PGREP"
/bin/mkdir -p "$APPLICATIONS_DIR/Holy Ghostty.app/Contents"
printf 'old build\n' > "$APPLICATIONS_DIR/Holy Ghostty.app/Contents/old-build.txt"
/usr/bin/touch "$PROCESS_STATE"

run_installer() {
  HOLY_GHOSTTY_TESTING=1 \
  HOLY_GHOSTTY_APPLICATIONS_DIR="$APPLICATIONS_DIR" \
  HOLY_GHOSTTY_XCODEBUILD="$FAKE_XCODEBUILD" \
  HOLY_GHOSTTY_LSREGISTER="$FAKE_LSREGISTER" \
  HOLY_GHOSTTY_PKILL="$FAKE_PKILL" \
  HOLY_GHOSTTY_PGREP="$FAKE_PGREP" \
  HOLY_GHOSTTY_SKIP_STABLE_SIGNING=1 \
  HOLY_GHOSTTY_ZIG="$FAKE_ZIG" \
  HOLY_GHOSTTY_LIPO="$FAKE_LIPO" \
  HOLY_TEST_REPO="$TEST_REPO" \
    "$TEST_REPO/scripts/install-holy-ghostty.sh" "$@"
}

/bin/rm -rf "$TEST_REPO/macos/GhosttyKit.xcframework" "$TEST_REPO/zig-out/share"
/usr/bin/touch "$TEST_REPO/macos/.test-register-fail"
if run_installer >"$TEMP_DIR/rollback.out" 2>&1; then
  fail "installer accepted failed LaunchServices registration"
fi
[ -f "$APPLICATIONS_DIR/Holy Ghostty.app/Contents/old-build.txt" ] || fail "installer did not roll back the prior app"
[ ! -s "$PKILL_LOG" ] || fail "installer stopped the running app before rollback-safe registration"
/bin/rm "$TEST_REPO/macos/.test-register-fail"

if ! run_installer >"$TEMP_DIR/success.out" 2>&1; then
  /bin/cat "$TEMP_DIR/success.out" >&2
  fail "verified transactional install failed"
fi
[ -f "$APPLICATIONS_DIR/Holy Ghostty.app/Contents/Resources/new-build.txt" ] || fail "installer did not publish the verified app"
[ ! -f "$APPLICATIONS_DIR/Holy Ghostty.app/Contents/old-build.txt" ] || fail "installer left the old app at the destination"
[ -s "$PKILL_LOG" ] || fail "installer did not stop the old process after successful publication"
[ ! -f "$PROCESS_STATE" ] || fail "installer reported success while the old process was still running"

: > "$PKILL_LOG"
/usr/bin/touch "$PROCESS_STATE" "$TEST_REPO/macos/.test-pkill-stuck"
if run_installer >"$TEMP_DIR/pkill.out" 2>&1; then
  fail "installer reported success when the old process could not be stopped"
fi
[ -f "$APPLICATIONS_DIR/Holy Ghostty.app/Contents/Resources/new-build.txt" ] || fail "failed process termination did not restore the prior app"
[ -f "$PROCESS_STATE" ] || fail "process-stop failure fixture was not retained"
/usr/bin/grep -q 'old Holy Ghostty process could not be stopped' "$TEMP_DIR/pkill.out" || fail "process-stop failure was not actionable"
/bin/rm "$TEST_REPO/macos/.test-pkill-stuck" "$PROCESS_STATE"

: > "$PKILL_LOG"
/usr/bin/touch "$PROCESS_STATE"
printf 'com.example.wrong\n' > "$TEST_REPO/macos/.test-bundle-id"
if run_installer >"$TEMP_DIR/bundle.out" 2>&1; then
  fail "installer accepted the wrong bundle identifier"
fi
[ -f "$APPLICATIONS_DIR/Holy Ghostty.app/Contents/Resources/new-build.txt" ] || fail "bad bundle preflight replaced the installed app"
[ ! -s "$PKILL_LOG" ] || fail "bad bundle preflight stopped the running app"
[ -f "$PROCESS_STATE" ] || fail "bad bundle preflight lost the running process"
/bin/rm "$TEST_REPO/macos/.test-bundle-id"

: > "$PKILL_LOG"
/usr/bin/touch "$TEST_REPO/macos/.test-xcode-fail"
if run_installer >"$TEMP_DIR/xcode.out" 2>&1; then
  fail "installer accepted a failed Swift build"
fi
[ -f "$APPLICATIONS_DIR/Holy Ghostty.app/Contents/Resources/new-build.txt" ] || fail "failed Swift build replaced the installed app"
[ ! -s "$PKILL_LOG" ] || fail "failed Swift build stopped the running app"
/bin/rm "$TEST_REPO/macos/.test-xcode-fail"

: > "$PKILL_LOG"
/usr/bin/touch "$TEST_REPO/macos/.test-debug-settings"
if run_installer >"$TEMP_DIR/settings.out" 2>&1; then
  fail "installer accepted Debug Swift compiler settings"
fi
[ -f "$APPLICATIONS_DIR/Holy Ghostty.app/Contents/Resources/new-build.txt" ] || fail "Debug Swift settings replaced the installed app"
[ ! -s "$PKILL_LOG" ] || fail "Debug Swift settings stopped the running app"
/usr/bin/grep -q 'Swift optimization is not -O' "$TEMP_DIR/settings.out" || fail "Debug Swift settings failure was not actionable"
/bin/rm "$TEST_REPO/macos/.test-debug-settings"

: > "$PKILL_LOG"
/usr/bin/touch "$TEST_REPO/macos/.test-debug-flags"
if run_installer >"$TEMP_DIR/flags.out" 2>&1; then
  fail "installer accepted hidden Debug compiler flags"
fi
[ -f "$APPLICATIONS_DIR/Holy Ghostty.app/Contents/Resources/new-build.txt" ] || fail "hidden Debug flags replaced the installed app"
[ ! -s "$PKILL_LOG" ] || fail "hidden Debug flags stopped the running app"
/usr/bin/grep -q 'Debug or unoptimized Swift flags\|DEBUG Swift compilation condition' "$TEMP_DIR/flags.out" || fail "hidden Debug flags failure was not actionable"
/bin/rm "$TEST_REPO/macos/.test-debug-flags"

if HOLY_GHOSTTY_SKIP_BUILD=1 run_installer >"$TEMP_DIR/skip.out" 2>&1; then
  fail "installer retained the stale Swift skip-build bypass"
fi
/usr/bin/grep -q 'no longer supported' "$TEMP_DIR/skip.out" || fail "skip-build rejection was not actionable"

/usr/bin/grep -q '"$CORE_TOOL" build' "$ROOT_DIR/scripts/install-holy-ghostty.sh" || fail "installer does not own the core build"
/usr/bin/grep -q 'verify-app' "$ROOT_DIR/scripts/install-holy-ghostty.sh" || fail "installer does not verify the linked core"
/usr/bin/grep -q 'build-holy-ghostty-core.sh\\" verify' "$ROOT_DIR/macos/Ghostty.xcodeproj/project.pbxproj" || fail "Xcode does not gate linking on the build receipt"
/usr/bin/grep -q 'HOLY_GHOSTTY_CORE_FROM_ZIG_GRAPH' "$ROOT_DIR/macos/Ghostty.xcodeproj/project.pbxproj" || fail "Xcode gate does not preserve Zig-owned app builds"
/usr/bin/grep -q 'HOLY_GHOSTTY_CORE_FROM_ZIG_GRAPH=1' "$ROOT_DIR/src/build/GhosttyXcodebuild.zig" || fail "Zig-owned app builds do not disclose their core ownership"
/usr/bin/grep -q 'xcodebuild -target Ghostty -configuration Debug' "$ROOT_DIR/.github/workflows/test.yml" || fail "upstream Debug-core CI still selects ReleaseLocal"
/usr/bin/grep -q 'scripts/build-holy-ghostty-core.sh build' "$ROOT_DIR/.github/workflows/build-holy-macos.yml" || fail "macOS CI bypasses the canonical core builder"
/usr/bin/grep -q 'HolyGhostty-Core-ReleaseFast-${{ github.sha }}' "$ROOT_DIR/.github/workflows/build-holy-macos.yml" || fail "macOS CI artifact is not commit-addressed"
/usr/bin/grep -q 'zig-out/share' "$ROOT_DIR/.github/workflows/build-holy-macos.yml" || fail "macOS CI artifact omits generated resources"
if /usr/bin/grep -Eq 'actions/(checkout|upload-artifact)@v[0-9]' \
  "$ROOT_DIR/.github/workflows/build-holy-macos.yml" \
  "$ROOT_DIR/.github/workflows/holy-build-contract.yml"
then
  fail "Holy provenance workflows use mutable action tags"
fi

if /usr/bin/grep -R -E -n '^[[:space:]]*zig build -Demit-xcframework' \
  "$ROOT_DIR/README.md" \
  "$ROOT_DIR/CONTRIBUTING.md" \
  "$ROOT_DIR/docs/holy-ghostty/README.md" \
  "$ROOT_DIR/docs/holy-ghostty/engineering-spec.md"
then
  fail "Holy onboarding still documents the unsafe Debug-default framework command"
fi

printf 'Holy build contract tests passed.\n'
