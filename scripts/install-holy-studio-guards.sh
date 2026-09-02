#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
WATCHER_SOURCE="$ROOT_DIR/scripts/holy-kernel-zone-watch.sh"
LABEL="org.holyghostty.kernel-zone-watch"
MAX_SESSIONS=110
EXPECTED_HOST=${HOLY_STUDIO_GUARD_EXPECTED_HOST:-Eriks-Mac-Studio}
TESTING=${HOLY_STUDIO_GUARD_TESTING:-0}
SYSTEM_ROOT=${HOLY_STUDIO_GUARD_ROOT:-}

SCUTIL_BIN=${HOLY_STUDIO_GUARD_SCUTIL_BIN:-/usr/sbin/scutil}
ID_BIN=${HOLY_STUDIO_GUARD_ID_BIN:-/usr/bin/id}
SSHD_BIN=${HOLY_STUDIO_GUARD_SSHD_BIN:-/usr/sbin/sshd}
LAUNCHCTL_BIN=${HOLY_STUDIO_GUARD_LAUNCHCTL_BIN:-/bin/launchctl}
PLUTIL_BIN=${HOLY_STUDIO_GUARD_PLUTIL_BIN:-/usr/bin/plutil}
DATE_BIN=${HOLY_STUDIO_GUARD_DATE_BIN:-/bin/date}

SSHD_CONFIG="$SYSTEM_ROOT/etc/ssh/sshd_config"
SSHD_DROPIN="$SYSTEM_ROOT/etc/ssh/sshd_config.d/99-holy-ghostty-maxsessions.conf"
SEALED_SSH_PLIST="$SYSTEM_ROOT/System/Library/LaunchDaemons/ssh.plist"
HELPER_PATH="$SYSTEM_ROOT/Library/PrivilegedHelperTools/$LABEL"
LAUNCHD_PLIST="$SYSTEM_ROOT/Library/LaunchDaemons/$LABEL.plist"
LOG_DIR="$SYSTEM_ROOT/Library/Logs/Holy Ghostty/kernel-zone-watch"
RECEIPT_PATH="$LOG_DIR/install-receipt.txt"
ARCHIVE_PARENT="$SYSTEM_ROOT/Library/Application Support/Holy Ghostty/Host Guard/Archive"

fail() {
  printf 'Holy Studio guards: %s\n' "$*" >&2
  exit 1
}

require_executable() {
  [ -x "$1" ] || fail "required executable is unavailable: $1"
}

sha256_file() {
  /usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{ print $1 }'
}

install_file() {
  mode=$1
  source_path=$2
  destination_path=$3
  if [ "$TESTING" = "1" ]; then
    /usr/bin/install -m "$mode" "$source_path" "$destination_path"
  else
    /usr/bin/install -o root -g wheel -m "$mode" "$source_path" "$destination_path"
  fi
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

if [ "$#" -ne 0 ]; then
  printf 'Usage: sudo scripts/install-holy-studio-guards.sh\n' >&2
  exit 64
fi

case "$SYSTEM_ROOT" in
  ''|/*) ;;
  *) fail "HOLY_STUDIO_GUARD_ROOT must be empty or absolute" ;;
esac
if [ "$TESTING" != "1" ] && [ -n "$SYSTEM_ROOT" ]; then
  fail "a system-root override is allowed only in test mode"
fi
if [ "$TESTING" != "1" ] && [ "$($ID_BIN -u)" -ne 0 ]; then
  fail "run this installer once through sudo"
fi

for executable in "$SCUTIL_BIN" "$ID_BIN" "$SSHD_BIN" "$LAUNCHCTL_BIN" "$PLUTIL_BIN" "$DATE_BIN"; do
  require_executable "$executable"
done
require_executable "$WATCHER_SOURCE"
/bin/sh -n "$WATCHER_SOURCE" || fail "watcher source failed shell syntax validation"

host=$($SCUTIL_BIN --get LocalHostName 2>/dev/null || true)
[ "$host" = "$EXPECTED_HOST" ] || fail "refusing host $host; expected $EXPECTED_HOST"
[ -f "$SSHD_CONFIG" ] || fail "sshd_config is missing: $SSHD_CONFIG"
[ -f "$SEALED_SSH_PLIST" ] || fail "sealed Apple ssh plist is missing: $SEALED_SSH_PLIST"
/usr/bin/grep -Eq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*' "$SSHD_CONFIG" \
  || fail "sshd_config does not include /etc/ssh/sshd_config.d/* before local settings"

sshd_config_sha_before=$(sha256_file "$SSHD_CONFIG")
sealed_ssh_plist_sha_before=$(sha256_file "$SEALED_SSH_PLIST")
watcher_source_sha=$(sha256_file "$WATCHER_SOURCE")
installed_at_utc=$($DATE_BIN -u '+%Y-%m-%dT%H:%M:%SZ')
archive_stamp=$($DATE_BIN -u '+%Y%m%dT%H%M%SZ')

work_dir=$(/usr/bin/mktemp -d "${TMPDIR:-/private/tmp}/holy-studio-guards.XXXXXX") \
  || fail "could not create a temporary workspace"
complete=0
mutated=0
job_mutated=0
had_dropin=0
had_helper=0
had_launchd_plist=0
had_job=0

cleanup() {
  status=$?
  trap - 0 1 2 3 15
  if [ "$status" -ne 0 ] && [ "$mutated" -eq 1 ]; then
    set +e
    if [ "$job_mutated" -eq 1 ]; then
      "$LAUNCHCTL_BIN" bootout "system/$LABEL" >/dev/null 2>&1
    fi
    restore_or_remove "$SSHD_DROPIN" "$work_dir/previous-dropin" "$had_dropin"
    restore_or_remove "$HELPER_PATH" "$work_dir/previous-helper" "$had_helper"
    restore_or_remove "$LAUNCHD_PLIST" "$work_dir/previous-launchd-plist" "$had_launchd_plist"
    if [ "$job_mutated" -eq 1 ] && [ "$had_job" -eq 1 ] && [ -f "$LAUNCHD_PLIST" ]; then
      "$LAUNCHCTL_BIN" bootstrap system "$LAUNCHD_PLIST" >/dev/null 2>&1
    fi
    printf 'Holy Studio guards: installation failed; installed configuration was rolled back. Logs and permanent archives were preserved.\n' >&2
    set -e
  fi
  /bin/rm -rf "$work_dir"
  exit "$status"
}
trap cleanup 0 1 2 3 15

printf '%s\n' \
  '# Managed by Holy Ghostty. New sshd instances read this through the stock Include directive.' \
  "MaxSessions $MAX_SESSIONS" > "$work_dir/maxsessions.conf"
/bin/cp "$WATCHER_SOURCE" "$work_dir/$LABEL"
/bin/chmod 0755 "$work_dir/$LABEL"

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
        <string>$HELPER_PATH</string>
        <string>sample</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>3600</integer>
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
$PLUTIL_BIN -lint "$work_dir/$LABEL.plist" >/dev/null \
  || fail "generated launchd plist is invalid"

if [ -e "$SSHD_DROPIN" ]; then
  had_dropin=1
  /bin/cp -p "$SSHD_DROPIN" "$work_dir/previous-dropin"
fi
if [ -e "$HELPER_PATH" ]; then
  had_helper=1
  /bin/cp -p "$HELPER_PATH" "$work_dir/previous-helper"
fi
if [ -e "$LAUNCHD_PLIST" ]; then
  had_launchd_plist=1
  /bin/cp -p "$LAUNCHD_PLIST" "$work_dir/previous-launchd-plist"
fi
if "$LAUNCHCTL_BIN" print "system/$LABEL" >/dev/null 2>&1; then
  had_job=1
fi

if [ "$had_dropin" -eq 1 ] || [ "$had_helper" -eq 1 ] || [ "$had_launchd_plist" -eq 1 ]; then
  archive_dir="$ARCHIVE_PARENT/$archive_stamp"
  /bin/mkdir -p "$archive_dir"
  [ "$had_dropin" -eq 0 ] || /bin/cp -p "$SSHD_DROPIN" "$archive_dir/99-holy-ghostty-maxsessions.conf"
  [ "$had_helper" -eq 0 ] || /bin/cp -p "$HELPER_PATH" "$archive_dir/$LABEL"
  [ "$had_launchd_plist" -eq 0 ] || /bin/cp -p "$LAUNCHD_PLIST" "$archive_dir/$LABEL.plist"
fi

/bin/mkdir -p "$(dirname "$SSHD_DROPIN")" "$(dirname "$HELPER_PATH")" "$(dirname "$LAUNCHD_PLIST")" "$LOG_DIR"
/bin/chmod 0755 "$LOG_DIR"
/usr/bin/touch "$LOG_DIR/launchd.stdout.log" "$LOG_DIR/launchd.stderr.log"
/bin/chmod 0644 "$LOG_DIR/launchd.stdout.log" "$LOG_DIR/launchd.stderr.log"

mutated=1
install_file 0644 "$work_dir/maxsessions.conf" "$SSHD_DROPIN"
install_file 0755 "$work_dir/$LABEL" "$HELPER_PATH"
install_file 0644 "$work_dir/$LABEL.plist" "$LAUNCHD_PLIST"

if ! "$SSHD_BIN" -t; then
  fail "sshd rejected the installed configuration"
fi
effective_maxsessions=$("$SSHD_BIN" -T 2>/dev/null | /usr/bin/awk '$1 == "maxsessions" { print $2; exit }')
[ "$effective_maxsessions" = "$MAX_SESSIONS" ] \
  || fail "sshd reports maxsessions ${effective_maxsessions:-unavailable}, expected $MAX_SESSIONS"

sshd_config_sha_after=$(sha256_file "$SSHD_CONFIG")
sealed_ssh_plist_sha_after=$(sha256_file "$SEALED_SSH_PLIST")
[ "$sshd_config_sha_after" = "$sshd_config_sha_before" ] \
  || fail "main sshd_config changed unexpectedly"
[ "$sealed_ssh_plist_sha_after" = "$sealed_ssh_plist_sha_before" ] \
  || fail "sealed Apple ssh plist changed unexpectedly"

HOLY_KERNEL_ZONE_LOG_DIR="$LOG_DIR" "$HELPER_PATH" sample > "$work_dir/initial-sample.tsv"
/usr/bin/awk -F '\t' '$6 == "data.kalloc.1024" { found = 1 } END { exit !found }' "$work_dir/initial-sample.tsv" \
  || fail "initial sample did not contain data.kalloc.1024"

if [ "$had_job" -eq 1 ]; then
  "$LAUNCHCTL_BIN" bootout "system/$LABEL" >/dev/null
  job_mutated=1
fi
"$LAUNCHCTL_BIN" bootstrap system "$LAUNCHD_PLIST"
job_mutated=1
"$LAUNCHCTL_BIN" print "system/$LABEL" >/dev/null \
  || fail "launchd did not admit $LABEL"

dropin_sha=$(sha256_file "$SSHD_DROPIN")
helper_sha=$(sha256_file "$HELPER_PATH")
launchd_plist_sha=$(sha256_file "$LAUNCHD_PLIST")
sample_log="$LOG_DIR/samples.tsv"
sample_count=$(/usr/bin/awk -F '\t' '$6 == "data.kalloc.1024" { count += 1 } END { print count + 0 }' "$sample_log")

/bin/cat > "$work_dir/install-receipt.txt" <<EOF
schema=1
installed_at_utc=$installed_at_utc
host=$host
effective_maxsessions=$effective_maxsessions
sshd_dropin=$SSHD_DROPIN
sshd_dropin_sha256=$dropin_sha
main_sshd_config_sha256=$sshd_config_sha_after
sealed_ssh_plist_sha256=$sealed_ssh_plist_sha_after
watcher_helper=$HELPER_PATH
watcher_helper_sha256=$helper_sha
launchd_label=$LABEL
launchd_plist=$LAUNCHD_PLIST
launchd_plist_sha256=$launchd_plist_sha
sample_log=$sample_log
data_kalloc_1024_samples=$sample_count
watcher_source_sha256=$watcher_source_sha
ssh_service_restarted=no
EOF
install_file 0644 "$work_dir/install-receipt.txt" "$RECEIPT_PATH"

complete=1
printf 'Holy Studio guards installed.\n'
printf 'effective_maxsessions=%s\n' "$effective_maxsessions"
printf 'launchd_label=%s\n' "$LABEL"
printf 'sample_log=%s\n' "$sample_log"
printf 'receipt=%s\n' "$RECEIPT_PATH"
