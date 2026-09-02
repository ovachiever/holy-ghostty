#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
WATCHER="$ROOT_DIR/scripts/holy-kernel-zone-watch.sh"
INSTALLER="$ROOT_DIR/scripts/install-holy-studio-guards.sh"
TEST_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/private/tmp}/holy-studio-guards-test.XXXXXX")

cleanup() {
  status=$?
  trap - 0 1 2 3 15
  /bin/rm -rf "$TEST_DIR"
  exit "$status"
}
trap cleanup 0 1 2 3 15

fail() {
  printf 'Holy Studio guard test: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  expected=$1
  file=$2
  /usr/bin/grep -F "$expected" "$file" >/dev/null \
    || fail "expected '$expected' in $file"
}

/bin/sh -n "$WATCHER"
/bin/sh -n "$INSTALLER"

FAKE_ZPRINT="$TEST_DIR/zprint"
FAKE_PGREP="$TEST_DIR/pgrep"
FAKE_SYSCTL="$TEST_DIR/sysctl"
FAKE_DATE="$TEST_DIR/date"
FAKE_LAUNCHCTL="$TEST_DIR/launchctl"
FAKE_SCUTIL="$TEST_DIR/scutil"
FAKE_SSHD="$TEST_DIR/sshd"
LAUNCHD_STATE="$TEST_DIR/launchd-state"
export LAUNCHD_STATE

/bin/cat > "$FAKE_ZPRINT" <<'EOF'
#!/bin/sh
set -eu
inuse=${FAKE_ZPRINT_INUSE:-100}
[ "${FAKE_ZPRINT_FAIL:-0}" != "1" ] || {
  printf 'fixture zprint failure\n' >&2
  exit 72
}
printf '%s\n' \
  '                            elem         cur         max        cur         max         cur  alloc  alloc                total' \
  'zone name                   size        size        size      #elts       #elts       inuse   size  count               allocs' \
  '-------------------------------------------------------------------------------------------------------------------------------'
printf 'data.kalloc.512              512       128K       256K        256         512         200     16K      4                     C\n'
printf 'data.kalloc.1024            1024       256K       512K        256         512  %10s     32K      8                  1M C\n' "$inuse"
EOF

/bin/cat > "$FAKE_PGREP" <<'EOF'
#!/bin/sh
set -eu
case "${2:-}" in
  ssh) printf '11\n12\n' ;;
  sshd) printf '21\n22\n23\n' ;;
  tmux) printf '31\n' ;;
  *) exit 1 ;;
esac
EOF

/bin/cat > "$FAKE_SYSCTL" <<'EOF'
#!/bin/sh
printf '{ sec = 1000, usec = 0 } Thu Jan  1 00:16:40 1970\n'
EOF

/bin/cat > "$FAKE_DATE" <<'EOF'
#!/bin/sh
set -eu
epoch=${FAKE_NOW_EPOCH:-4600}
case "$*" in
  *%Y-%m-%dT%H:%M:%SZ*) /bin/date -u -r "$epoch" '+%Y-%m-%dT%H:%M:%SZ' ;;
  *%Y%m%dT%H%M%SZ*) /bin/date -u -r "$epoch" '+%Y%m%dT%H%M%SZ' ;;
  *%s*) printf '%s\n' "$epoch" ;;
  *) exit 64 ;;
esac
EOF

/bin/cat > "$FAKE_LAUNCHCTL" <<'EOF'
#!/bin/sh
set -eu
command_name=${1:-}
target=${2:-}
case "$command_name:$target" in
  print:system/com.openssh.sshd)
    printf '%s\n' \
      'system/com.openssh.sshd = {' \
      '    active count = 3' \
      '    runs = 123' \
      '}'
    ;;
  print:system/org.holyghostty.kernel-zone-watch)
    [ -f "$LAUNCHD_STATE" ] || exit 113
    printf '%s\n' \
      'system/org.holyghostty.kernel-zone-watch = {' \
      '    state = waiting' \
      '    runs = 1' \
      '}'
    ;;
  bootstrap:system)
    /usr/bin/touch "$LAUNCHD_STATE"
    ;;
  bootout:system/org.holyghostty.kernel-zone-watch)
    /bin/rm -f "$LAUNCHD_STATE"
    ;;
  *)
    printf 'unexpected launchctl call: %s\n' "$*" >&2
    exit 64
    ;;
esac
EOF

/bin/cat > "$FAKE_SCUTIL" <<'EOF'
#!/bin/sh
printf 'Eriks-Mac-Studio\n'
EOF

/bin/cat > "$FAKE_SSHD" <<'EOF'
#!/bin/sh
set -eu
case "${1:-}" in
  -t) exit 0 ;;
  -T) printf 'maxsessions %s\n' "${FAKE_SSHD_MAXSESSIONS:-110}" ;;
  *) exit 64 ;;
esac
EOF

/bin/chmod +x "$FAKE_ZPRINT" "$FAKE_PGREP" "$FAKE_SYSCTL" "$FAKE_DATE" "$FAKE_LAUNCHCTL" "$FAKE_SCUTIL" "$FAKE_SSHD"

SAMPLE_LOG_DIR="$TEST_DIR/direct-log"
export HOLY_KERNEL_ZONE_LOG_DIR="$SAMPLE_LOG_DIR"
export HOLY_KERNEL_ZONE_ZPRINT_BIN="$FAKE_ZPRINT"
export HOLY_KERNEL_ZONE_PGREP_BIN="$FAKE_PGREP"
export HOLY_KERNEL_ZONE_SYSCTL_BIN="$FAKE_SYSCTL"
export HOLY_KERNEL_ZONE_DATE_BIN="$FAKE_DATE"
export HOLY_KERNEL_ZONE_LAUNCHCTL_BIN="$FAKE_LAUNCHCTL"

FAKE_NOW_EPOCH=4600 FAKE_ZPRINT_INUSE=100 "$WATCHER" sample > "$TEST_DIR/sample-1.tsv"
FAKE_NOW_EPOCH=8200 FAKE_ZPRINT_INUSE=200 "$WATCHER" sample > "$TEST_DIR/sample-2.tsv"
"$WATCHER" report > "$TEST_DIR/report.txt"

assert_contains 'samples=2' "$TEST_DIR/report.txt"
assert_contains 'growth_elements=100' "$TEST_DIR/report.txt"
assert_contains 'growth_bytes=102400' "$TEST_DIR/report.txt"
assert_contains 'growth_bytes_per_hour=102400' "$TEST_DIR/report.txt"
expected_curve_row=$(printf '1970-01-01T02:16:40Z\t200\t0.195\t2\t3\t1\t123\t3')
assert_contains "$expected_curve_row" "$TEST_DIR/report.txt"
/usr/bin/awk -F '\t' '
  $6 == "data.kalloc.512" && $16 != "unavailable" { exit 1 }
  $6 == "data.kalloc.1024" && $16 != "1M" { exit 1 }
' "$SAMPLE_LOG_DIR/samples.tsv" || fail "watcher mistook zprint zone flags for lifetime allocation data"

SHORT_LOG_DIR="$TEST_DIR/short-window-log"
HOLY_KERNEL_ZONE_LOG_DIR="$SHORT_LOG_DIR" FAKE_NOW_EPOCH=4600 FAKE_ZPRINT_INUSE=100 "$WATCHER" sample >/dev/null
HOLY_KERNEL_ZONE_LOG_DIR="$SHORT_LOG_DIR" FAKE_NOW_EPOCH=4601 FAKE_ZPRINT_INUSE=200 "$WATCHER" sample >/dev/null
HOLY_KERNEL_ZONE_LOG_DIR="$SHORT_LOG_DIR" "$WATCHER" report > "$TEST_DIR/short-window-report.txt"
assert_contains 'elapsed_seconds=1' "$TEST_DIR/short-window-report.txt"
assert_contains 'rate_window_status=insufficient' "$TEST_DIR/short-window-report.txt"
assert_contains 'growth_bytes_per_hour=unavailable' "$TEST_DIR/short-window-report.txt"

FAILURE_LOG_DIR="$TEST_DIR/failure-log"
if HOLY_KERNEL_ZONE_LOG_DIR="$FAILURE_LOG_DIR" FAKE_ZPRINT_FAIL=1 "$WATCHER" sample > "$TEST_DIR/failing-sample.txt" 2>&1; then
  fail "watcher accepted a failed zprint sample"
fi
assert_contains 'zprint failed: fixture zprint failure' "$FAILURE_LOG_DIR/errors.log"

TEST_ROOT="$TEST_DIR/system-root"
/bin/mkdir -p "$TEST_ROOT/etc/ssh/sshd_config.d" "$TEST_ROOT/System/Library/LaunchDaemons"
printf 'Include /etc/ssh/sshd_config.d/*\nMaxSessions 44\n' > "$TEST_ROOT/etc/ssh/sshd_config"
printf 'sealed system plist\n' > "$TEST_ROOT/System/Library/LaunchDaemons/ssh.plist"
main_before=$(/usr/bin/shasum -a 256 "$TEST_ROOT/etc/ssh/sshd_config" | /usr/bin/awk '{ print $1 }')
sealed_before=$(/usr/bin/shasum -a 256 "$TEST_ROOT/System/Library/LaunchDaemons/ssh.plist" | /usr/bin/awk '{ print $1 }')

export HOLY_STUDIO_GUARD_TESTING=1
export HOLY_STUDIO_GUARD_ROOT="$TEST_ROOT"
export HOLY_STUDIO_GUARD_SCUTIL_BIN="$FAKE_SCUTIL"
export HOLY_STUDIO_GUARD_ID_BIN=/usr/bin/id
export HOLY_STUDIO_GUARD_SSHD_BIN="$FAKE_SSHD"
export HOLY_STUDIO_GUARD_LAUNCHCTL_BIN="$FAKE_LAUNCHCTL"
export HOLY_STUDIO_GUARD_DATE_BIN="$FAKE_DATE"

FAKE_NOW_EPOCH=8200 FAKE_ZPRINT_INUSE=200 "$INSTALLER" > "$TEST_DIR/install.txt"
assert_contains 'MaxSessions 110' "$TEST_ROOT/etc/ssh/sshd_config.d/99-holy-ghostty-maxsessions.conf"
assert_contains 'effective_maxsessions=110' "$TEST_ROOT/Library/Logs/Holy Ghostty/kernel-zone-watch/install-receipt.txt"
assert_contains 'data_kalloc_1024_samples=1' "$TEST_ROOT/Library/Logs/Holy Ghostty/kernel-zone-watch/install-receipt.txt"
[ "$(/usr/bin/plutil -extract StartInterval raw -o - "$TEST_ROOT/Library/LaunchDaemons/org.holyghostty.kernel-zone-watch.plist")" = "3600" ] \
  || fail "launchd interval is not one hour"
[ "$(/usr/bin/plutil -extract RunAtLoad raw -o - "$TEST_ROOT/Library/LaunchDaemons/org.holyghostty.kernel-zone-watch.plist")" = "true" ] \
  || fail "launchd job does not run at load"
$FAKE_LAUNCHCTL print system/org.holyghostty.kernel-zone-watch >/dev/null \
  || fail "installer did not bootstrap the watcher"

main_after=$(/usr/bin/shasum -a 256 "$TEST_ROOT/etc/ssh/sshd_config" | /usr/bin/awk '{ print $1 }')
sealed_after=$(/usr/bin/shasum -a 256 "$TEST_ROOT/System/Library/LaunchDaemons/ssh.plist" | /usr/bin/awk '{ print $1 }')
[ "$main_after" = "$main_before" ] || fail "installer changed the main sshd_config"
[ "$sealed_after" = "$sealed_before" ] || fail "installer changed the sealed ssh plist"

previous_dropin=$(/usr/bin/shasum -a 256 "$TEST_ROOT/etc/ssh/sshd_config.d/99-holy-ghostty-maxsessions.conf" | /usr/bin/awk '{ print $1 }')
if FAKE_SSHD_MAXSESSIONS=44 "$INSTALLER" > "$TEST_DIR/failing-install.txt" 2>&1; then
  fail "installer accepted the wrong effective MaxSessions"
fi
restored_dropin=$(/usr/bin/shasum -a 256 "$TEST_ROOT/etc/ssh/sshd_config.d/99-holy-ghostty-maxsessions.conf" | /usr/bin/awk '{ print $1 }')
[ "$restored_dropin" = "$previous_dropin" ] || fail "failed reinstall did not restore the previous drop-in"
$FAKE_LAUNCHCTL print system/org.holyghostty.kernel-zone-watch >/dev/null \
  || fail "failed reinstall did not restore the previous launchd job"

printf 'Holy Studio guard tests passed.\n'
