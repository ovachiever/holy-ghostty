#!/bin/sh
set -eu

LABEL="org.holyghostty.kernel-zone-watch"
DEFAULT_LOG_DIR="/Library/Logs/Holy Ghostty/kernel-zone-watch"
LOG_DIR=${HOLY_KERNEL_ZONE_LOG_DIR:-$DEFAULT_LOG_DIR}
LOG_FILE=${HOLY_KERNEL_ZONE_LOG_FILE:-$LOG_DIR/samples.tsv}
ERROR_LOG=${HOLY_KERNEL_ZONE_ERROR_LOG:-$LOG_DIR/errors.log}
DEFAULT_ZONE=${HOLY_KERNEL_ZONE_NAME:-data.kalloc.1024}
MIN_RATE_WINDOW_SECONDS=${HOLY_KERNEL_ZONE_MIN_RATE_WINDOW_SECONDS:-1800}

ZPRINT_BIN=${HOLY_KERNEL_ZONE_ZPRINT_BIN:-/usr/bin/zprint}
PGREP_BIN=${HOLY_KERNEL_ZONE_PGREP_BIN:-/usr/bin/pgrep}
SYSCTL_BIN=${HOLY_KERNEL_ZONE_SYSCTL_BIN:-/usr/sbin/sysctl}
DATE_BIN=${HOLY_KERNEL_ZONE_DATE_BIN:-/bin/date}
LAUNCHCTL_BIN=${HOLY_KERNEL_ZONE_LAUNCHCTL_BIN:-/bin/launchctl}
AWK_BIN=${HOLY_KERNEL_ZONE_AWK_BIN:-/usr/bin/awk}
MKTEMP_BIN=${HOLY_KERNEL_ZONE_MKTEMP_BIN:-/usr/bin/mktemp}

usage() {
  printf '%s\n' \
    'Usage: holy-kernel-zone-watch.sh sample' \
    '       holy-kernel-zone-watch.sh report [zone] [samples.tsv]' \
    '       holy-kernel-zone-watch.sh status [zone] [samples.tsv]'
}

fail() {
  printf 'Holy kernel-zone watch: %s\n' "$*" >&2
  exit 1
}

require_executable() {
  [ -x "$1" ] || fail "required executable is unavailable: $1"
}

process_count() {
  process_name=$1
  if process_ids=$("$PGREP_BIN" -x "$process_name" 2>/dev/null); then
    printf '%s\n' "$process_ids" | "$AWK_BIN" 'NF { count += 1 } END { print count + 0 }'
    return
  else
    status=$?
  fi
  if [ "$status" -eq 1 ]; then
    printf '0\n'
  else
    printf 'unavailable\n'
  fi
}

record_failure() {
  failure_message=$1
  timestamp=$($DATE_BIN -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || printf 'timestamp-unavailable')
  /bin/mkdir -p "$LOG_DIR" 2>/dev/null || true
  printf '%s\t%s\n' "$timestamp" "$failure_message" >> "$ERROR_LOG" 2>/dev/null || true
}

sample() {
  require_executable "$ZPRINT_BIN"
  require_executable "$PGREP_BIN"
  require_executable "$SYSCTL_BIN"
  require_executable "$DATE_BIN"
  require_executable "$LAUNCHCTL_BIN"
  require_executable "$AWK_BIN"
  require_executable "$MKTEMP_BIN"

  umask 022
  /bin/mkdir -p "$LOG_DIR" || fail "could not create log directory: $LOG_DIR"

  work_dir=$($MKTEMP_BIN -d "${TMPDIR:-/private/tmp}/holy-kernel-zone-watch.XXXXXX") \
    || fail "could not create a temporary workspace"
  cleanup_sample() {
    status=$?
    trap - 0 1 2 3 15
    /bin/rm -rf "$work_dir"
    exit "$status"
  }
  trap cleanup_sample 0 1 2 3 15

  timestamp_utc=$($DATE_BIN -u '+%Y-%m-%dT%H:%M:%SZ')
  sample_epoch=$($DATE_BIN '+%s')
  case "$sample_epoch" in
    ''|*[!0-9]*) record_failure "date returned a non-numeric epoch"; fail "date returned a non-numeric epoch" ;;
  esac

  boot_raw=$($SYSCTL_BIN -n kern.boottime 2>/dev/null || true)
  boot_epoch=$(printf '%s\n' "$boot_raw" | "$AWK_BIN" '
    {
      for (field = 1; field <= NF; field += 1) {
        if ($field == "sec" && $(field + 1) == "=") {
          value = $(field + 2)
          gsub(/,/, "", value)
          print value
          exit
        }
      }
    }
  ')
  case "$boot_epoch" in
    ''|*[!0-9]*) record_failure "kern.boottime was unavailable"; fail "kern.boottime was unavailable" ;;
  esac
  uptime_seconds=$((sample_epoch - boot_epoch))
  [ "$uptime_seconds" -ge 0 ] || {
    record_failure "sample time preceded kern.boottime"
    fail "sample time preceded kern.boottime"
  }

  ssh_count=$(process_count ssh)
  sshd_count=$(process_count sshd)
  tmux_count=$(process_count tmux)

  sshd_runs=unavailable
  sshd_active=unavailable
  if "$LAUNCHCTL_BIN" print system/com.openssh.sshd > "$work_dir/sshd-launchctl.txt" 2>/dev/null; then
    parsed_runs=$("$AWK_BIN" -F ' = ' '
      {
        key = $1
        gsub(/[[:space:]]/, "", key)
        if (key == "runs") { print $2; exit }
      }
    ' "$work_dir/sshd-launchctl.txt")
    parsed_active=$("$AWK_BIN" -F ' = ' '
      {
        key = $1
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
        if (key == "active count") { print $2; exit }
      }
    ' "$work_dir/sshd-launchctl.txt")
    [ -z "$parsed_runs" ] || sshd_runs=$parsed_runs
    [ -z "$parsed_active" ] || sshd_active=$parsed_active
  fi

  if ! "$ZPRINT_BIN" -t > "$work_dir/zprint.txt" 2> "$work_dir/zprint.err"; then
    detail=$(/usr/bin/head -c 512 "$work_dir/zprint.err" | /usr/bin/tr '\t\r\n' '   ')
    record_failure "zprint failed: ${detail:-no diagnostic}"
    fail "zprint failed: ${detail:-no diagnostic}"
  fi

  if ! "$AWK_BIN" \
    -v schema=1 \
    -v timestamp="$timestamp_utc" \
    -v sample_epoch="$sample_epoch" \
    -v boot_epoch="$boot_epoch" \
    -v uptime="$uptime_seconds" \
    -v ssh="$ssh_count" \
    -v sshd="$sshd_count" \
    -v tmux="$tmux_count" \
    -v sshd_runs="$sshd_runs" \
    -v sshd_active="$sshd_active" '
      $1 ~ /^data\.kalloc\.[0-9]+$/ && NF >= 9 {
        lifetime = "unavailable"
        for (extra = 10; extra <= NF; extra += 1) {
          if ($extra !~ /^[PC]+$/) {
            lifetime = $extra
            break
          }
        }
        derived_bytes = $2 * $7
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%.0f\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", \
          schema, timestamp, sample_epoch, boot_epoch, uptime, $1, $2, $7, derived_bytes, \
          $3, $4, $5, $6, $8, $9, lifetime, ssh, sshd, tmux, sshd_runs, sshd_active
        count += 1
      }
      END { if (count == 0) exit 42 }
    ' "$work_dir/zprint.txt" > "$work_dir/rows.tsv"; then
    record_failure "zprint returned no data.kalloc size-class rows"
    fail "zprint returned no data.kalloc size-class rows"
  fi

  if [ ! -s "$LOG_FILE" ]; then
    printf '%b\n' 'schema_version\ttimestamp_utc\tsample_epoch_seconds\tboot_epoch_seconds\tuptime_seconds\tzone\telement_size_bytes\tinuse_elements\tderived_inuse_bytes\tcurrent_size_reported\tmaximum_size_reported\tcurrent_elements_reported\tmaximum_elements_reported\talloc_size_reported\talloc_count_reported\tlifetime_allocated_reported\tssh_process_count\tsshd_process_count\ttmux_process_count\tsshd_launchd_runs\tsshd_launchd_active_count' > "$LOG_FILE"
  fi
  /bin/cat "$work_dir/rows.tsv" >> "$LOG_FILE"
  /bin/chmod 0644 "$LOG_FILE"

  target_row=$("$AWK_BIN" -F '\t' -v zone="$DEFAULT_ZONE" '$6 == zone { row = $0 } END { print row }' "$work_dir/rows.tsv")
  [ -n "$target_row" ] || {
    record_failure "$DEFAULT_ZONE was absent from the sample"
    fail "$DEFAULT_ZONE was absent from the sample"
  }
  printf '%s\n' "$target_row"
}

report() {
  zone=${1:-$DEFAULT_ZONE}
  report_file=${2:-$LOG_FILE}
  [ -s "$report_file" ] || fail "sample log is missing or empty: $report_file"
  case "$MIN_RATE_WINDOW_SECONDS" in
    ''|*[!0-9]*) fail "minimum rate window must be a non-negative integer" ;;
  esac

  if ! "$AWK_BIN" -F '\t' -v zone="$zone" -v min_rate_window="$MIN_RATE_WINDOW_SECONDS" '
    NR == 1 { next }
    $6 == zone {
      if (seen && boot != $4) {
        count = 0
      }
      seen = 1
      boot = $4
      count += 1
      timestamp[count] = $2
      epoch[count] = $3
      elements[count] = $8
      bytes[count] = $9
      ssh[count] = $17
      sshd[count] = $18
      tmux[count] = $19
      launchd_runs[count] = $20
      launchd_active[count] = $21
    }
    END {
      if (count == 0) exit 42

      printf "zone=%s\n", zone
      printf "latest_boot_epoch_seconds=%s\n", boot
      printf "samples=%d\n", count
      printf "first_timestamp_utc=%s\n", timestamp[1]
      printf "last_timestamp_utc=%s\n", timestamp[count]
      printf "minimum_rate_window_seconds=%.0f\n", min_rate_window

      if (count > 1 && epoch[count] > epoch[1]) {
        elapsed = epoch[count] - epoch[1]
        growth_elements = elements[count] - elements[1]
        growth_bytes = bytes[count] - bytes[1]
        printf "elapsed_seconds=%.0f\n", elapsed
        printf "growth_elements=%.0f\n", growth_elements
        printf "growth_bytes=%.0f\n", growth_bytes
        if (elapsed >= min_rate_window) {
          bytes_per_hour = growth_bytes * 3600 / elapsed
          printf "rate_window_status=sufficient\n"
          printf "growth_bytes_per_hour=%.0f\n", bytes_per_hour
          printf "growth_mib_per_hour=%.3f\n", bytes_per_hour / 1048576
        } else {
          printf "rate_window_status=insufficient\n"
          printf "growth_bytes_per_hour=unavailable\n"
          printf "growth_mib_per_hour=unavailable\n"
        }
      } else {
        printf "elapsed_seconds=unavailable\n"
        printf "growth_elements=unavailable\n"
        printf "growth_bytes=unavailable\n"
        printf "rate_window_status=insufficient\n"
        printf "growth_bytes_per_hour=unavailable\n"
        printf "growth_mib_per_hour=unavailable\n"
      }

      printf "\ntimestamp_utc\tinuse_elements\tderived_inuse_mib\tssh_process_count\tsshd_process_count\ttmux_process_count\tsshd_launchd_runs\tsshd_launchd_active_count\n"
      for (row = 1; row <= count; row += 1) {
        printf "%s\t%.0f\t%.3f\t%s\t%s\t%s\t%s\t%s\n", \
          timestamp[row], elements[row], bytes[row] / 1048576, ssh[row], sshd[row], \
          tmux[row], launchd_runs[row], launchd_active[row]
      }
    }
  ' "$report_file"; then
    fail "no samples for $zone were found in $report_file"
  fi
}

status() {
  zone=${1:-$DEFAULT_ZONE}
  status_file=${2:-$LOG_FILE}
  "$LAUNCHCTL_BIN" print "system/$LABEL" 2>&1 | "$AWK_BIN" '
    /^[[:space:]]*(path|state|runs|last exit code) = / { print }
  '
  printf '\n'
  report "$zone" "$status_file"
}

case "${1:-}" in
  sample)
    [ "$#" -eq 1 ] || { usage >&2; exit 64; }
    sample
    ;;
  report)
    [ "$#" -le 3 ] || { usage >&2; exit 64; }
    report "${2:-$DEFAULT_ZONE}" "${3:-$LOG_FILE}"
    ;;
  status)
    [ "$#" -le 3 ] || { usage >&2; exit 64; }
    status "${2:-$DEFAULT_ZONE}" "${3:-$LOG_FILE}"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 64
    ;;
esac
