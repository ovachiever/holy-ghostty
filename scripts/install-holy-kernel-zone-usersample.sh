#!/bin/sh
# Installs the kernel-zone user sampler as a LaunchAgent in the user's own
# launchd domain (gui/<uid>). No sudo: zprint -t, sysctl, and ps all work
# unprivileged. Idempotent: a rerun replaces the helper and plist and reloads
# the job. The sampling interval comes from the sampler itself
# (holy-kernel-zone-usersample.sh interval), so it is defined in one place.
#
#   scripts/install-holy-kernel-zone-usersample.sh              install or refresh
#   scripts/install-holy-kernel-zone-usersample.sh --uninstall  remove job, plist, helper (logs kept)
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
SAMPLER_SOURCE="$ROOT_DIR/scripts/holy-kernel-zone-usersample.sh"
LABEL="org.holyghostty.kernel-zone-usersample"
TESTING=${HOLY_KERNEL_ZONE_USERSAMPLE_TESTING:-0}
USER_HOME=${HOLY_KERNEL_ZONE_USERSAMPLE_HOME:-$HOME}

LAUNCHCTL_BIN=${HOLY_KERNEL_ZONE_USERSAMPLE_LAUNCHCTL_BIN:-/bin/launchctl}
PLUTIL_BIN=${HOLY_KERNEL_ZONE_USERSAMPLE_PLUTIL_BIN:-/usr/bin/plutil}
ID_BIN=${HOLY_KERNEL_ZONE_USERSAMPLE_ID_BIN:-/usr/bin/id}
DATE_BIN=${HOLY_KERNEL_ZONE_USERSAMPLE_DATE_BIN:-/bin/date}

HELPER_DIR="$USER_HOME/Library/Application Support/Holy Ghostty/kernel-zone-usersample"
HELPER_PATH="$HELPER_DIR/holy-kernel-zone-usersample.sh"
AGENT_DIR="$USER_HOME/Library/LaunchAgents"
AGENT_PLIST="$AGENT_DIR/$LABEL.plist"
LOG_DIR="$USER_HOME/Library/Logs/Holy Ghostty/kernel-zone-usersample"
RECEIPT_PATH="$LOG_DIR/install-receipt.txt"

fail() {
  printf 'Holy kernel-zone usersample installer: %s\n' "$*" >&2
  exit 1
}

require_executable() {
  [ -x "$1" ] || fail "required executable is unavailable: $1"
}

sha256_file() {
  /usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{ print $1 }'
}

restore_or_remove() {
  path=$1
  backup=$2
  existed=$3
  if [ "$existed" -eq 1 ]; then
    /bin/cp -p "$backup" "$path"
  else
    /bin/rm -f "$path"
  fi
}

mode=install
case "$#:${1:-}" in
  0:) ;;
  1:--uninstall) mode=uninstall ;;
  *)
    printf 'Usage: scripts/install-holy-kernel-zone-usersample.sh [--uninstall]\n' >&2
    exit 64
    ;;
esac

for executable in "$LAUNCHCTL_BIN" "$PLUTIL_BIN" "$ID_BIN" "$DATE_BIN"; do
  require_executable "$executable"
done
uid=$($ID_BIN -u)
if [ "$TESTING" != "1" ] && [ "$uid" -eq 0 ]; then
  fail "run this as the logged-in user, not through sudo; the job belongs in gui/<uid>"
fi
case "$USER_HOME" in
  /*) ;;
  *) fail "home directory must be absolute: $USER_HOME" ;;
esac
DOMAIN="gui/$uid"

if [ "$mode" = uninstall ]; then
  if "$LAUNCHCTL_BIN" print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
    "$LAUNCHCTL_BIN" bootout "$DOMAIN/$LABEL"
  fi
  /bin/rm -f "$AGENT_PLIST" "$HELPER_PATH"
  printf 'Holy kernel-zone usersample removed.\n'
  printf 'removed_job=%s/%s\n' "$DOMAIN" "$LABEL"
  printf 'removed_plist=%s\n' "$AGENT_PLIST"
  printf 'removed_helper=%s\n' "$HELPER_PATH"
  printf 'kept_logs=%s\n' "$LOG_DIR"
  exit 0
fi

require_executable "$SAMPLER_SOURCE"
/bin/sh -n "$SAMPLER_SOURCE" || fail "sampler source failed shell syntax validation"
interval=$("$SAMPLER_SOURCE" interval)
case "$interval" in
  ''|*[!0-9]*) fail "sampler reported a non-numeric interval: $interval" ;;
esac
installed_at_utc=$($DATE_BIN -u '+%Y-%m-%dT%H:%M:%SZ')

work_dir=$(/usr/bin/mktemp -d "${TMPDIR:-/private/tmp}/holy-kernel-zone-usersample-install.XXXXXX") \
  || fail "could not create a temporary workspace"
mutated=0
job_mutated=0
had_helper=0
had_plist=0
had_job=0

cleanup() {
  status=$?
  trap - 0 1 2 3 15
  if [ "$status" -ne 0 ] && [ "$mutated" -eq 1 ]; then
    set +e
    if [ "$job_mutated" -eq 1 ]; then
      "$LAUNCHCTL_BIN" bootout "$DOMAIN/$LABEL" >/dev/null 2>&1
    fi
    restore_or_remove "$HELPER_PATH" "$work_dir/previous-helper" "$had_helper"
    restore_or_remove "$AGENT_PLIST" "$work_dir/previous-plist" "$had_plist"
    if [ "$job_mutated" -eq 1 ] && [ "$had_job" -eq 1 ] && [ -f "$AGENT_PLIST" ]; then
      "$LAUNCHCTL_BIN" bootstrap "$DOMAIN" "$AGENT_PLIST" >/dev/null 2>&1
    fi
    printf 'Holy kernel-zone usersample installer: installation failed; the previous helper, plist, and job were restored. Logs were kept.\n' >&2
    set -e
  fi
  /bin/rm -rf "$work_dir"
  exit "$status"
}
trap cleanup 0 1 2 3 15

case "$HELPER_PATH$LOG_DIR" in
  *'&'*|*'<'*|*'>'*|*'"'*) fail "installation paths contain characters unsafe for a launchd plist" ;;
esac
/bin/cat > "$work_dir/$LABEL.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/sh</string>
        <string>$HELPER_PATH</string>
        <string>sample</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>HOLY_KERNEL_ZONE_USERSAMPLE_LOG_DIR</key>
        <string>$LOG_DIR</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>$interval</integer>
    <key>ProcessType</key>
    <string>Background</string>
    <key>LowPriorityIO</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$LOG_DIR/launchd.stdout.log</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/launchd.stderr.log</string>
</dict>
</plist>
EOF
$PLUTIL_BIN -lint "$work_dir/$LABEL.plist" >/dev/null || fail "generated launchd plist is invalid"

if [ -e "$HELPER_PATH" ]; then
  had_helper=1
  /bin/cp -p "$HELPER_PATH" "$work_dir/previous-helper"
fi
if [ -e "$AGENT_PLIST" ]; then
  had_plist=1
  /bin/cp -p "$AGENT_PLIST" "$work_dir/previous-plist"
fi
if "$LAUNCHCTL_BIN" print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
  had_job=1
fi

/bin/mkdir -p "$HELPER_DIR" "$AGENT_DIR" "$LOG_DIR"
mutated=1
/usr/bin/install -m 0755 "$SAMPLER_SOURCE" "$HELPER_PATH"
/usr/bin/install -m 0644 "$work_dir/$LABEL.plist" "$AGENT_PLIST"

# Validate the installed helper into a scratch log, so the real log only ever
# holds rows the agent wrote.
HOLY_KERNEL_ZONE_USERSAMPLE_LOG_DIR="$work_dir/validation-log" /bin/sh "$HELPER_PATH" sample > "$work_dir/validation-sample.tsv" \
  || fail "the validation sample failed; see $work_dir/validation-log/errors.log"
/usr/bin/awk -F '\t' '$6 == "data.kalloc.1024" { found = 1 } END { exit !found }' "$work_dir/validation-sample.tsv" \
  || fail "validation sample did not contain data.kalloc.1024"

count_rows() {
  if [ -s "$LOG_DIR/samples.tsv" ]; then
    /usr/bin/awk -F '\t' '$6 == "data.kalloc.1024" { count += 1 } END { print count + 0 }' "$LOG_DIR/samples.tsv"
  else
    printf '0\n'
  fi
}
rows_before=$(count_rows)

if [ "$had_job" -eq 1 ]; then
  job_mutated=1
  "$LAUNCHCTL_BIN" bootout "$DOMAIN/$LABEL" >/dev/null
fi
job_mutated=1
"$LAUNCHCTL_BIN" bootstrap "$DOMAIN" "$AGENT_PLIST"
"$LAUNCHCTL_BIN" print "$DOMAIN/$LABEL" >/dev/null || fail "launchd did not admit $DOMAIN/$LABEL"

# RunAtLoad makes launchd take the first sample; wait for it, bounded by one
# StartInterval (the longest launchd may take to run the job at all).
waited=0
while [ "$(count_rows)" -le "$rows_before" ]; do
  [ "$waited" -lt "$interval" ] || fail "launchd admitted the job but no sample landed within $interval s"
  /bin/sleep 1
  waited=$((waited + 1))
done
first_sample=$(/usr/bin/awk -F '\t' '$6 == "data.kalloc.1024" { row = $0 } END { print row }' "$LOG_DIR/samples.tsv")

helper_sha=$(sha256_file "$HELPER_PATH")
plist_sha=$(sha256_file "$AGENT_PLIST")
sample_count=$(/usr/bin/awk -F '\t' '$6 == "data.kalloc.1024" { count += 1 } END { print count + 0 }' "$LOG_DIR/samples.tsv")

/bin/cat > "$work_dir/install-receipt.txt" <<EOF
schema=1
installed_at_utc=$installed_at_utc
launchd_domain=$DOMAIN
launchd_label=$LABEL
launchd_plist=$AGENT_PLIST
launchd_plist_sha256=$plist_sha
start_interval_seconds=$interval
sampler_helper=$HELPER_PATH
sampler_helper_sha256=$helper_sha
sampler_source_sha256=$(sha256_file "$SAMPLER_SOURCE")
sample_log=$LOG_DIR/samples.tsv
data_kalloc_1024_samples=$sample_count
remove_with=scripts/install-holy-kernel-zone-usersample.sh --uninstall
EOF
/usr/bin/install -m 0644 "$work_dir/install-receipt.txt" "$RECEIPT_PATH"

printf 'Holy kernel-zone usersample installed.\n'
printf 'launchd_job=%s/%s\n' "$DOMAIN" "$LABEL"
printf 'launchd_plist=%s\n' "$AGENT_PLIST"
printf 'sampler_helper=%s\n' "$HELPER_PATH"
printf 'start_interval_seconds=%s\n' "$interval"
printf 'sample_log=%s/samples.tsv\n' "$LOG_DIR"
printf 'receipt=%s\n' "$RECEIPT_PATH"
printf 'first_sample=%s\n' "$first_sample"
printf 'first_sample_wait_seconds=%s\n' "$waited"
printf 'report_with=%s report\n' "$HELPER_PATH"
printf 'remove_with=scripts/install-holy-kernel-zone-usersample.sh --uninstall (from a holy-ghostty checkout)\n'
printf "remove_by_hand=launchctl bootout %s/%s; rm '%s' '%s'\n" "$DOMAIN" "$LABEL" "$AGENT_PLIST" "$HELPER_PATH"
