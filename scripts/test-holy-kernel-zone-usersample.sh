#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
SAMPLER="$ROOT_DIR/scripts/holy-kernel-zone-usersample.sh"
INSTALLER="$ROOT_DIR/scripts/install-holy-kernel-zone-usersample.sh"
TEST_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/private/tmp}/holy-kernel-zone-usersample-test.XXXXXX")

cleanup() {
  status=$?
  trap - 0 1 2 3 15
  /bin/rm -rf "$TEST_DIR"
  exit "$status"
}
trap cleanup 0 1 2 3 15

fail() {
  printf 'Holy kernel-zone usersample test: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  expected=$1
  file=$2
  /usr/bin/grep -F -- "$expected" "$file" >/dev/null \
    || fail "expected '$expected' in $file"
}

assert_not_contains() {
  unexpected=$1
  file=$2
  if /usr/bin/grep -F -- "$unexpected" "$file" >/dev/null; then
    fail "did not expect '$unexpected' in $file"
  fi
}

/bin/sh -n "$SAMPLER"
/bin/sh -n "$INSTALLER"

# The sampler is the one source for its tuning; the test reads it, never restates it.
ROTATE_AFTER_SECONDS=$(/usr/bin/sed -n 's/^ROTATE_AFTER_SECONDS=\([0-9][0-9]*\)$/\1/p' "$SAMPLER")
[ -n "$ROTATE_AFTER_SECONDS" ] || fail "could not read ROTATE_AFTER_SECONDS from the sampler"
INTERVAL=$("$SAMPLER" interval)
[ "$INTERVAL" = "300" ] || fail "sampling interval is $INTERVAL, the work order sets 300 s"

FAKE_ZPRINT="$TEST_DIR/zprint"
FAKE_SYSCTL="$TEST_DIR/sysctl"
FAKE_DATE="$TEST_DIR/date"
FAKE_PS="$TEST_DIR/ps"
FAKE_LAUNCHCTL="$TEST_DIR/launchctl"
LAUNCHD_STATE="$TEST_DIR/launchd-state"
FAKE_DEV="$TEST_DIR/dev"
export LAUNCHD_STATE
/bin/mkdir -p "$LAUNCHD_STATE" "$FAKE_DEV"
/usr/bin/touch "$FAKE_DEV/ttys000" "$FAKE_DEV/ttys001" "$FAKE_DEV/ttys002" "$FAKE_DEV/tty.Bluetooth"

/bin/cat > "$FAKE_ZPRINT" <<'EOF'
#!/bin/sh
set -eu
[ "${FAKE_ZPRINT_FAIL:-0}" != "1" ] || {
  printf 'fixture zprint failure\n' >&2
  exit 72
}
printf '%s\n' \
  '                            elem         cur         max        cur         max         cur  alloc  alloc                total' \
  'zone name                   size        size        size      #elts       #elts       inuse   size  count               allocs' \
  '-------------------------------------------------------------------------------------------------------------------------------'
printf 'data.kalloc.512              512          0K          0K          0           0         869     0K      0                   0B\n'
printf 'data.kalloc.1024            1024          0K          0K          0           0  %10s     0K      0                   0B\n' "${FAKE_ZPRINT_INUSE:-100}"
EOF

/bin/cat > "$FAKE_SYSCTL" <<'EOF'
#!/bin/sh
set -eu
case "$*" in
  *kern.boottime*) printf '{ sec = %s, usec = 0 } fixture\n' "${FAKE_BOOT_EPOCH:-1000000}" ;;
  *kern.num_files*) printf '%s\n' "${FAKE_NUM_FILES:-11000}" ;;
  *) exit 1 ;;
esac
EOF

/bin/cat > "$FAKE_DATE" <<'EOF'
#!/bin/sh
set -eu
epoch=${FAKE_NOW_EPOCH:-1000600}
case "$*" in
  *%Y-%m-%dT%H:%M:%SZ*) /bin/date -u -r "$epoch" '+%Y-%m-%dT%H:%M:%SZ' ;;
  *%s*) printf '%s\n' "$epoch" ;;
  *) exit 64 ;;
esac
EOF

/bin/cat > "$FAKE_PS" <<'EOF'
#!/bin/sh
set -eu
[ "$*" = "-axo pid=,ppid=,etime=,comm=" ] || { printf 'unexpected ps call: %s\n' "$*" >&2; exit 64; }
/bin/cat "$FAKE_PS_FILE"
EOF

/bin/cat > "$FAKE_LAUNCHCTL" <<'EOF'
#!/bin/sh
set -eu
command_name=${1:-}
target=${2:-}
case "$command_name" in
  print)
    job=${target##*/}
    [ -f "$LAUNCHD_STATE/$job" ] || exit 113
    printf '%s = {\n    state = waiting\n    runs = 1\n    run interval = 300 seconds\n}\n' "$target"
    ;;
  bootstrap)
    case "$target" in gui/*) ;; *) printf 'bootstrap outside the gui domain: %s\n' "$target" >&2; exit 64 ;; esac
    [ "${FAKE_BOOTSTRAP_FAIL:-0}" != "1" ] || exit 5
    job=$(/usr/bin/basename "$3" .plist)
    [ ! -f "$LAUNCHD_STATE/$job" ] || { printf 'Bootstrap failed: 5: Input/output error\n' >&2; exit 5; }
    /bin/cp "$3" "$LAUNCHD_STATE/$job"
    # RunAtLoad: run the job once the way launchd would, from the plist alone.
    program=$(/usr/bin/plutil -extract ProgramArguments.1 raw -o - "$3")
    log_dir=$(/usr/bin/plutil -extract EnvironmentVariables.HOLY_KERNEL_ZONE_USERSAMPLE_LOG_DIR raw -o - "$3")
    HOLY_KERNEL_ZONE_USERSAMPLE_LOG_DIR="$log_dir" /bin/sh "$program" sample >/dev/null
    ;;
  bootout)
    job=${target##*/}
    [ -f "$LAUNCHD_STATE/$job" ] || exit 3
    /bin/rm -f "$LAUNCHD_STATE/$job"
    ;;
  *)
    printf 'unexpected launchctl call: %s\n' "$*" >&2
    exit 64
    ;;
esac
EOF

/bin/chmod +x "$FAKE_ZPRINT" "$FAKE_SYSCTL" "$FAKE_DATE" "$FAKE_PS" "$FAKE_LAUNCHCTL"

# Census fixtures. Between "before" and "after": a leaky helper appears (pid 5000,
# parent zsh 4000), ssh 3001 exits, pid 3100 is reused by a fresh login, 3200 is
# reparented to launchd, and a comm with spaces survives the round trip.
PS_BEFORE="$TEST_DIR/ps-before.txt"
PS_AFTER="$TEST_DIR/ps-after.txt"
/bin/cat > "$PS_BEFORE" <<'EOF'
    1     0 01:00:00 /sbin/launchd
 3000     1 01:00:00 /opt/homebrew/bin/tmux
 3001  3000    50:00 /usr/bin/ssh
 3100     1    40:00 /usr/bin/login
 3200  3000    30:00 /bin/bash
 3300     1 01:00:00 /Applications/Comet.app/Contents/Frameworks/Comet Helper (Renderer).app/Contents/MacOS/Comet Helper (Renderer)
 4000  3000 01:00:00 /bin/zsh
EOF
/bin/cat > "$PS_AFTER" <<'EOF'
    1     0 01:05:00 /sbin/launchd
 3000     1 01:05:00 /opt/homebrew/bin/tmux
 3100     1    00:20 /usr/bin/login
 3200     1    35:00 /bin/bash
 3300     1 01:05:00 /Applications/Comet.app/Contents/Frameworks/Comet Helper (Renderer).app/Contents/MacOS/Comet Helper (Renderer)
 4000  3000 01:05:00 /bin/zsh
 5000  4000    03:10 /usr/local/bin/leaky-helper
EOF

export HOLY_KERNEL_ZONE_USERSAMPLE_ZPRINT_BIN="$FAKE_ZPRINT"
export HOLY_KERNEL_ZONE_USERSAMPLE_SYSCTL_BIN="$FAKE_SYSCTL"
export HOLY_KERNEL_ZONE_USERSAMPLE_DATE_BIN="$FAKE_DATE"
export HOLY_KERNEL_ZONE_USERSAMPLE_PS_BIN="$FAKE_PS"
export HOLY_KERNEL_ZONE_USERSAMPLE_LAUNCHCTL_BIN="$FAKE_LAUNCHCTL"
export HOLY_KERNEL_ZONE_USERSAMPLE_DEV_DIR="$FAKE_DEV"

# Boot 1: 15 quiet samples at the quiet-boot pace (250 per 300 s = 3,000/h) with
# one loud interval (+11,000 in 300 s = 132k/h, over the line for 5 minutes but
# not for an hour), then an onset at the 2026-09-26 episode pace (230,000 per
# 300 s = 2.76M/h) for 6 intervals, then quiet again until the episode ends.
# kern.boottime alternates 1000000/1000001, the jitter the root log shows.
EPISODE_LOG="$TEST_DIR/episode-log"
inuse=500
sample_number=1
while [ "$sample_number" -le 35 ]; do
  epoch=$((1000600 + (sample_number - 1) * 300))
  if [ "$sample_number" -eq 8 ]; then
    inuse=$((inuse + 11000))
  elif [ "$sample_number" -ge 16 ] && [ "$sample_number" -le 21 ]; then
    inuse=$((inuse + 230000))
  elif [ "$sample_number" -gt 1 ]; then
    inuse=$((inuse + 250))
  fi
  ps_file=$PS_BEFORE
  [ "$sample_number" -lt 16 ] || ps_file=$PS_AFTER
  boot=1000000
  [ $((sample_number % 2)) -eq 0 ] || boot=1000001
  HOLY_KERNEL_ZONE_USERSAMPLE_LOG_DIR="$EPISODE_LOG" FAKE_NOW_EPOCH=$epoch FAKE_BOOT_EPOCH=$boot \
    FAKE_ZPRINT_INUSE=$inuse FAKE_PS_FILE=$ps_file FAKE_NUM_FILES=$((11000 + sample_number)) \
    "$SAMPLER" sample > "$TEST_DIR/sample-$sample_number.tsv"
  sample_number=$((sample_number + 1))
done
# Boot 2: a fresh boot, quiet; its lower inuse must not read as an event.
for epoch in 2000600 2000900 2001200; do
  HOLY_KERNEL_ZONE_USERSAMPLE_LOG_DIR="$EPISODE_LOG" FAKE_NOW_EPOCH=$epoch FAKE_BOOT_EPOCH=2000000 \
    FAKE_ZPRINT_INUSE=600 FAKE_PS_FILE=$PS_AFTER "$SAMPLER" sample >/dev/null
done

row=$(/bin/cat "$TEST_DIR/sample-1.tsv")
expected_row=$(printf '1\t1970-01-12T13:56:40Z\t1000600\t1000001\t599\tdata.kalloc.1024\t1024\t500\t512000\t11001\t3\t4000\t7\t1000600-')
case "$row" in
  "$expected_row"[0-9]*) ;;
  *) fail "first sample row was '$row', expected '$expected_row<pid>'" ;;
esac
first_snapshot=${row##*"$(printf '\t')"}
/usr/bin/awk -F '\t' 'NR > 1 && $6 == "data.kalloc.512" { found = 1 } END { exit !found }' "$EPISODE_LOG/samples.tsv" \
  || fail "sampler dropped the other data.kalloc size classes"
[ -s "$EPISODE_LOG/snapshots/$first_snapshot.census.tsv.gz" ] || fail "census snapshot was not written"
/usr/bin/gzip -dc "$EPISODE_LOG/snapshots/$first_snapshot.census.tsv.gz" > "$TEST_DIR/census-1.tsv"
assert_contains "$(printf '3300\t1\t01:00:00\t/Applications/Comet.app/Contents/Frameworks/Comet Helper (Renderer).app/Contents/MacOS/Comet Helper (Renderer)')" "$TEST_DIR/census-1.tsv"
sample_16_snapshot=$(/usr/bin/awk -F '\t' '{ print $14 }' "$TEST_DIR/sample-16.tsv")
/usr/bin/gzip -dc "$EPISODE_LOG/snapshots/$sample_16_snapshot.commands.tsv.gz" > "$TEST_DIR/commands-16.tsv"
assert_contains "$(printf '1\t/usr/local/bin/leaky-helper')" "$TEST_DIR/commands-16.tsv"

HOLY_KERNEL_ZONE_USERSAMPLE_LOG_DIR="$EPISODE_LOG" "$SAMPLER" report > "$TEST_DIR/report.txt"
before_utc=$(/bin/date -u -r 1004800 '+%Y-%m-%dT%H:%M:%SZ')
after_utc=$(/bin/date -u -r 1005100 '+%Y-%m-%dT%H:%M:%SZ')
end_utc=$(/bin/date -u -r $((1000600 + 32 * 300)) '+%Y-%m-%dT%H:%M:%SZ')
assert_contains 'onset_rate_per_hour=129626' "$TEST_DIR/report.txt"
assert_contains 'boots=2' "$TEST_DIR/report.txt"
assert_contains 'samples=38' "$TEST_DIR/report.txt"
assert_contains 'onsets=1' "$TEST_DIR/report.txt"
assert_contains "before_sample_utc=$before_utc inuse=14750" "$TEST_DIR/report.txt"
assert_contains "after_sample_utc=$after_utc inuse=244750" "$TEST_DIR/report.txt"
assert_contains 'onset_interval_rate_per_hour=2760000' "$TEST_DIR/report.txt"
assert_contains 'kern_num_files=11015->11016 dev_ttys=3->3 highest_pid=4000->5000 processes=7->7' "$TEST_DIR/report.txt"
assert_contains "$(printf 'appeared\t5000\t4000\t03:10\t/usr/local/bin/leaky-helper\tparent=/bin/zsh')" "$TEST_DIR/report.txt"
assert_contains "$(printf 'appeared\t3100\t1\t00:20\t/usr/bin/login')" "$TEST_DIR/report.txt"
assert_contains "$(printf 'exited\t3100\t1\t40:00\t/usr/bin/login')" "$TEST_DIR/report.txt"
assert_contains "$(printf 'exited\t3001\t3000\t50:00\t/usr/bin/ssh')" "$TEST_DIR/report.txt"
assert_contains "$(printf 'reparented\t3200\t3000->1\t35:00\t/bin/bash')" "$TEST_DIR/report.txt"
assert_contains "$(printf 'command_count\t+1\t0->1\t/usr/local/bin/leaky-helper')" "$TEST_DIR/report.txt"
assert_contains "$(printf 'command_count\t-1\t1->0\t/usr/bin/ssh')" "$TEST_DIR/report.txt"
assert_not_contains 'Comet Helper' "$TEST_DIR/report.txt"
assert_contains "episode_end_utc=$end_utc" "$TEST_DIR/report.txt"

# An episode still running at the last sample is reported as open, and a boot
# whose onset census was pruned still reports the onset.
OPEN_LOG="$TEST_DIR/open-log"
inuse=500
sample_number=1
while [ "$sample_number" -le 22 ]; do
  epoch=$((3000600 + (sample_number - 1) * 300))
  # Sample 14 carries a partial onset interval (+8,000 = 96k/h: louder than any
  # quiet hour, under the line); the report must start the episode there.
  if [ "$sample_number" -eq 14 ]; then
    inuse=$((inuse + 8000))
  elif [ "$sample_number" -gt 14 ]; then
    inuse=$((inuse + 17000))
  fi
  HOLY_KERNEL_ZONE_USERSAMPLE_LOG_DIR="$OPEN_LOG" FAKE_NOW_EPOCH=$epoch FAKE_BOOT_EPOCH=3000000 \
    FAKE_ZPRINT_INUSE=$inuse FAKE_PS_FILE=$PS_BEFORE "$SAMPLER" sample >/dev/null
  sample_number=$((sample_number + 1))
done
/bin/rm -f "$OPEN_LOG/snapshots/"*.census.tsv.gz
HOLY_KERNEL_ZONE_USERSAMPLE_LOG_DIR="$OPEN_LOG" "$SAMPLER" report > "$TEST_DIR/open-report.txt"
assert_contains 'onsets=1' "$TEST_DIR/open-report.txt"
assert_contains 'onset_interval_rate_per_hour=96000' "$TEST_DIR/open-report.txt"
assert_contains 'census: unavailable' "$TEST_DIR/open-report.txt"
assert_contains 'episode_open_at_last_sample_utc=' "$TEST_DIR/open-report.txt"

# A quiet log reports no onsets.
QUIET_LOG="$TEST_DIR/quiet-log"
for epoch in 4000600 4000900 4001200 4001500 4001800 4002100 4002400 4002700 4003000 4003300 4003600 4003900 4004200 4004500; do
  HOLY_KERNEL_ZONE_USERSAMPLE_LOG_DIR="$QUIET_LOG" FAKE_NOW_EPOCH=$epoch FAKE_BOOT_EPOCH=4000000 \
    FAKE_ZPRINT_INUSE=$((epoch - 4000000)) FAKE_PS_FILE=$PS_BEFORE "$SAMPLER" sample >/dev/null
done
HOLY_KERNEL_ZONE_USERSAMPLE_LOG_DIR="$QUIET_LOG" "$SAMPLER" report > "$TEST_DIR/quiet-report.txt"
assert_contains 'onsets=0' "$TEST_DIR/quiet-report.txt"

# Rotation: once the oldest row is older than ROTATE_AFTER_SECONDS the log rolls
# to samples.tsv.1, and snapshots older than the oldest kept row are pruned.
ROTATE_LOG="$TEST_DIR/rotate-log"
first_epoch=5000600
second_epoch=$((first_epoch + ROTATE_AFTER_SECONDS + 1))
third_epoch=$((second_epoch + ROTATE_AFTER_SECONDS + 1))
for epoch in "$first_epoch" "$second_epoch"; do
  HOLY_KERNEL_ZONE_USERSAMPLE_LOG_DIR="$ROTATE_LOG" FAKE_NOW_EPOCH=$epoch FAKE_BOOT_EPOCH=5000000 \
    FAKE_ZPRINT_INUSE=700 FAKE_PS_FILE=$PS_BEFORE "$SAMPLER" sample >/dev/null
done
[ -s "$ROTATE_LOG/samples.tsv.1" ] || fail "log did not rotate after ROTATE_AFTER_SECONDS"
[ "$(/usr/bin/awk -F '\t' 'NR == 2 { print $3 }' "$ROTATE_LOG/samples.tsv.1")" = "$first_epoch" ] \
  || fail "rotated generation does not start at the first sample"
[ "$(/usr/bin/awk -F '\t' 'NR == 2 { print $3 }' "$ROTATE_LOG/samples.tsv")" = "$second_epoch" ] \
  || fail "new generation does not start at the rotating sample"
/usr/bin/head -1 "$ROTATE_LOG/samples.tsv" | /usr/bin/grep -q '^schema_version' || fail "new generation lacks a header"
snapshot_for() { /usr/bin/awk -F '\t' -v epoch="$1" '$3 == epoch { print $14; exit }' "$ROTATE_LOG/samples.tsv.1" "$ROTATE_LOG/samples.tsv"; }
first_snapshot=$(snapshot_for "$first_epoch")
second_snapshot=$(snapshot_for "$second_epoch")
[ -s "$ROTATE_LOG/snapshots/$first_snapshot.census.tsv.gz" ] || fail "rotation pruned a snapshot the kept generation still names"
HOLY_KERNEL_ZONE_USERSAMPLE_LOG_DIR="$ROTATE_LOG" "$SAMPLER" report > "$TEST_DIR/rotate-report.txt"
assert_contains 'samples=2' "$TEST_DIR/rotate-report.txt"
HOLY_KERNEL_ZONE_USERSAMPLE_LOG_DIR="$ROTATE_LOG" FAKE_NOW_EPOCH=$third_epoch FAKE_BOOT_EPOCH=5000000 \
  FAKE_ZPRINT_INUSE=700 FAKE_PS_FILE=$PS_BEFORE "$SAMPLER" sample >/dev/null
[ ! -e "$ROTATE_LOG/snapshots/$first_snapshot.census.tsv.gz" ] || fail "second rotation kept an expired census"
[ ! -e "$ROTATE_LOG/snapshots/$first_snapshot.commands.tsv.gz" ] || fail "second rotation kept expired command counts"
[ -s "$ROTATE_LOG/snapshots/$second_snapshot.census.tsv.gz" ] || fail "second rotation pruned a kept census"
[ "$(/usr/bin/awk -F '\t' 'NR == 2 { print $3 }' "$ROTATE_LOG/samples.tsv.1")" = "$second_epoch" ] \
  || fail "second rotation did not replace the previous generation"

# Two samples in one second keep two snapshots.
SAME_SECOND_LOG="$TEST_DIR/same-second-log"
for attempt in 1 2; do
  HOLY_KERNEL_ZONE_USERSAMPLE_LOG_DIR="$SAME_SECOND_LOG" FAKE_NOW_EPOCH=7000600 FAKE_BOOT_EPOCH=7000000 \
    FAKE_ZPRINT_INUSE=700 FAKE_PS_FILE=$PS_BEFORE "$SAMPLER" sample >/dev/null
done
same_second_snapshots=$(/usr/bin/find "$SAME_SECOND_LOG/snapshots" -name '7000600-*.census.tsv.gz' | /usr/bin/wc -l | /usr/bin/tr -d ' ')
[ "$same_second_snapshots" = "2" ] || fail "two samples in one second kept $same_second_snapshots census snapshots"

# A failed probe is recorded and writes no row.
FAILURE_LOG="$TEST_DIR/failure-log"
if HOLY_KERNEL_ZONE_USERSAMPLE_LOG_DIR="$FAILURE_LOG" FAKE_ZPRINT_FAIL=1 FAKE_PS_FILE=$PS_BEFORE \
  "$SAMPLER" sample > "$TEST_DIR/failing-sample.txt" 2>&1; then
  fail "sampler accepted a failed zprint sample"
fi
assert_contains 'zprint failed: fixture zprint failure' "$FAILURE_LOG/errors.log"
[ ! -e "$FAILURE_LOG/samples.tsv" ] || fail "failed sample wrote a row"

# Installer: user domain only, idempotent, reports what it installed and how to remove it.
FAKE_HOME="$TEST_DIR/home dir"
/bin/mkdir -p "$FAKE_HOME"
export HOLY_KERNEL_ZONE_USERSAMPLE_TESTING=1
export HOLY_KERNEL_ZONE_USERSAMPLE_HOME="$FAKE_HOME"
export FAKE_PS_FILE="$PS_BEFORE"
LABEL=org.holyghostty.kernel-zone-usersample
PLIST="$FAKE_HOME/Library/LaunchAgents/$LABEL.plist"
HELPER="$FAKE_HOME/Library/Application Support/Holy Ghostty/kernel-zone-usersample/holy-kernel-zone-usersample.sh"
LOGS="$FAKE_HOME/Library/Logs/Holy Ghostty/kernel-zone-usersample"
uid=$(/usr/bin/id -u)

FAKE_NOW_EPOCH=6000600 FAKE_BOOT_EPOCH=6000000 "$INSTALLER" > "$TEST_DIR/install-1.txt"
FAKE_NOW_EPOCH=6000900 FAKE_BOOT_EPOCH=6000000 "$INSTALLER" > "$TEST_DIR/install-2.txt" \
  || fail "installer is not idempotent: a second run over a loaded job failed"
assert_contains "launchd_job=gui/$uid/$LABEL" "$TEST_DIR/install-2.txt"
assert_contains "launchd_plist=$PLIST" "$TEST_DIR/install-2.txt"
assert_contains 'start_interval_seconds=300' "$TEST_DIR/install-2.txt"
assert_contains 'first_sample=1	' "$TEST_DIR/install-2.txt"
assert_contains 'first_sample_wait_seconds=0' "$TEST_DIR/install-2.txt"
assert_contains 'remove_with=' "$TEST_DIR/install-2.txt"
assert_contains '--uninstall' "$TEST_DIR/install-2.txt"
[ -f "$LAUNCHD_STATE/$LABEL" ] || fail "installer did not bootstrap the agent"
[ "$(/usr/bin/plutil -extract StartInterval raw -o - "$PLIST")" = "$INTERVAL" ] || fail "agent interval is not the sampler's interval"
[ "$(/usr/bin/plutil -extract RunAtLoad raw -o - "$PLIST")" = "true" ] || fail "agent does not run at load"
[ "$(/usr/bin/plutil -extract EnvironmentVariables.HOLY_KERNEL_ZONE_USERSAMPLE_LOG_DIR raw -o - "$PLIST")" = "$LOGS" ] \
  || fail "agent does not pin its log directory"
[ "$(/usr/bin/plutil -extract ProgramArguments.1 raw -o - "$PLIST")" = "$HELPER" ] || fail "agent does not run the installed helper"
/usr/bin/cmp -s "$HELPER" "$SAMPLER" || fail "installed helper differs from the sampler source"
assert_contains 'data_kalloc_1024_samples=2' "$LOGS/install-receipt.txt"
assert_contains "launchd_domain=gui/$uid" "$LOGS/install-receipt.txt"

previous_plist_sha=$(/usr/bin/shasum -a 256 "$PLIST" | /usr/bin/awk '{ print $1 }')
if FAKE_BOOTSTRAP_FAIL=1 FAKE_NOW_EPOCH=6001200 FAKE_BOOT_EPOCH=6000000 "$INSTALLER" > "$TEST_DIR/failing-install.txt" 2>&1; then
  fail "installer accepted a failed bootstrap"
fi
[ "$(/usr/bin/shasum -a 256 "$PLIST" | /usr/bin/awk '{ print $1 }')" = "$previous_plist_sha" ] \
  || fail "failed reinstall did not restore the previous plist"
[ -f "$HELPER" ] || fail "failed reinstall removed the previous helper"

"$INSTALLER" --uninstall > "$TEST_DIR/uninstall.txt"
[ ! -e "$PLIST" ] || fail "uninstall left the plist"
[ ! -e "$HELPER" ] || fail "uninstall left the helper"
[ ! -f "$LAUNCHD_STATE/$LABEL" ] || fail "uninstall left the job loaded"
[ -s "$LOGS/samples.tsv" ] || fail "uninstall removed the sample log"
assert_contains "kept_logs=$LOGS" "$TEST_DIR/uninstall.txt"
"$INSTALLER" --uninstall > /dev/null || fail "uninstall is not idempotent"

printf 'Holy kernel-zone usersample tests passed.\n'
