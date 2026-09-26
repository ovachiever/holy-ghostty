#!/bin/sh
# Holy Ghostty kernel-zone user sampler (mn-579814).
#
# A user-domain companion to the root hourly watcher (holy-kernel-zone-watch.sh).
# The hourly counters could not name the process that feeds data.kalloc.1024, so
# this sampler records, every interval, the zone inuse counts plus the host-side
# quantities a feeder would move (open files, ptys, pid churn, per-command process
# counts) and a compact process census, so the samples on either side of an onset
# can be diffed. Everything it reads works unprivileged on macOS 26.6.1:
# zprint -t column 7 (inuse elements), sysctl kern.num_files, kern.boottime, ps.
#
# Named quantities and where each comes from:
#
#   SAMPLE_INTERVAL_SECONDS=300
#     The cadence the work order sets (every 5 minutes). At the slowest measured
#     episode rate (about 203k elements per hour, 2026-09-09..11) one interval
#     gains about 16.9k elements, and an onset is bounded to a 300 s window,
#     twelve times finer than the root watcher's StartInterval of 3600 s. The
#     installer writes this value into the LaunchAgent's StartInterval.
#
#   RATE_WINDOW_SECONDS=3600
#     Onset rates are judged over a trailing hour because both threshold bounds
#     below were measured on the root watcher's hourly intervals; judging a
#     5-minute rate against an hourly bound would compare different quantities.
#
#   QUIET_MAX_RATE_PER_HOUR=75269
#     Highest hourly growth of data.kalloc.1024 outside the three episodes, over
#     468 hourly intervals of /Library/Logs/Holy Ghostty/kernel-zone-watch/
#     samples.tsv: 2026-09-18T14:40:51Z -> 15:40:53Z, +75,311 elements in 3602 s.
#
#   EPISODE_MIN_RATE_PER_HOUR=183983
#     Lowest hourly growth inside any episode, over 80 steady episode intervals:
#     2026-09-11T13:35:43Z -> 14:35:44Z, +184,034 elements in 3601 s.
#
#   ONSET_RATE_PER_HOUR = (QUIET_MAX + EPISODE_MIN) / 2 = 129,626 elements/hour.
#     The midpoint of the gap between the two measured populations: 1.72x the
#     loudest quiet hour, 0.70x the slowest episode hour, 38x the highest
#     quiet-boot average (3,372/h, boot of 2026-09-19T17:51:55Z).
#
#   BOOT_EPOCH_TOLERANCE_SECONDS=1
#     kern.boottime seconds jitter by one within a single boot in the root log
#     (1788240487/1788240486, 1789840315/1789840314, 1790421414/1790421415).
#
#   ROTATE_AFTER_SECONDS=1209600 (14 days)
#     The longest boot in the root log ran 939,010 s (10.9 days, 2026-09-08T21:01Z
#     to 2026-09-19T17:51Z); rounded up to whole weeks so one generation always
#     spans a full boot. When the oldest row of samples.tsv is older than this,
#     samples.tsv becomes samples.tsv.1 (replacing the previous generation) and
#     snapshots older than the oldest kept row are pruned, so 14 to 28 days stay
#     on disk. Measured cost per sample on 2026-09-26T17:02Z (1,005 processes,
#     22 zones): 15.0 KB gzipped census + 8.7 KB gzipped command counts + 2.65 KB
#     of rows = 26.4 KB, so 288 samples a day is about 7.6 MB per day and at most
#     about 213 MB across both generations (28 days). A sample took 0.36 s.
set -eu

LABEL="org.holyghostty.kernel-zone-usersample"
DEFAULT_LOG_DIR="$HOME/Library/Logs/Holy Ghostty/kernel-zone-usersample"
LOG_DIR=${HOLY_KERNEL_ZONE_USERSAMPLE_LOG_DIR:-$DEFAULT_LOG_DIR}
LOG_FILE="$LOG_DIR/samples.tsv"
PREVIOUS_LOG_FILE="$LOG_DIR/samples.tsv.1"
SNAPSHOT_DIR="$LOG_DIR/snapshots"
ERROR_LOG="$LOG_DIR/errors.log"
DEFAULT_ZONE=${HOLY_KERNEL_ZONE_USERSAMPLE_ZONE:-data.kalloc.1024}
DEV_DIR=${HOLY_KERNEL_ZONE_USERSAMPLE_DEV_DIR:-/dev}

SAMPLE_INTERVAL_SECONDS=300
RATE_WINDOW_SECONDS=3600
QUIET_MAX_RATE_PER_HOUR=75269
EPISODE_MIN_RATE_PER_HOUR=183983
ONSET_RATE_PER_HOUR=$(((QUIET_MAX_RATE_PER_HOUR + EPISODE_MIN_RATE_PER_HOUR) / 2))
BOOT_EPOCH_TOLERANCE_SECONDS=1
ROTATE_AFTER_SECONDS=1209600

ZPRINT_BIN=${HOLY_KERNEL_ZONE_USERSAMPLE_ZPRINT_BIN:-/usr/bin/zprint}
SYSCTL_BIN=${HOLY_KERNEL_ZONE_USERSAMPLE_SYSCTL_BIN:-/usr/sbin/sysctl}
DATE_BIN=${HOLY_KERNEL_ZONE_USERSAMPLE_DATE_BIN:-/bin/date}
PS_BIN=${HOLY_KERNEL_ZONE_USERSAMPLE_PS_BIN:-/bin/ps}
LAUNCHCTL_BIN=${HOLY_KERNEL_ZONE_USERSAMPLE_LAUNCHCTL_BIN:-/bin/launchctl}
AWK_BIN=/usr/bin/awk
GZIP_BIN=/usr/bin/gzip
MKTEMP_BIN=/usr/bin/mktemp
SORT_BIN=/usr/bin/sort

usage() {
  printf '%s\n' \
    'Usage: holy-kernel-zone-usersample.sh sample' \
    '       holy-kernel-zone-usersample.sh report [zone]' \
    '       holy-kernel-zone-usersample.sh status [zone]' \
    '       holy-kernel-zone-usersample.sh interval'
}

fail() {
  printf 'Holy kernel-zone usersample: %s\n' "$*" >&2
  exit 1
}

require_executable() {
  [ -x "$1" ] || fail "required executable is unavailable: $1"
}

record_failure() {
  failure_message=$1
  timestamp=$($DATE_BIN -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || printf 'timestamp-unavailable')
  /bin/mkdir -p "$LOG_DIR" 2>/dev/null || true
  printf '%s\t%s\n' "$timestamp" "$failure_message" >> "$ERROR_LOG" 2>/dev/null || true
}

die_recorded() {
  record_failure "$1"
  fail "$1"
}

make_work_dir() {
  work_dir=$($MKTEMP_BIN -d "${TMPDIR:-/private/tmp}/holy-kernel-zone-usersample.XXXXXX") \
    || fail "could not create a temporary workspace"
  cleanup_work_dir() {
    status=$?
    trap - 0 1 2 3 15
    /bin/rm -rf "$work_dir"
    exit "$status"
  }
  trap cleanup_work_dir 0 1 2 3 15
}

first_data_epoch() {
  "$AWK_BIN" -F '\t' 'NR == 2 { print $3; exit }' "$1"
}

rotate_if_due() {
  now_epoch=$1
  [ -s "$LOG_FILE" ] || return 0
  oldest=$(first_data_epoch "$LOG_FILE")
  case "$oldest" in
    ''|*[!0-9]*) return 0 ;;
  esac
  [ $((now_epoch - oldest)) -gt "$ROTATE_AFTER_SECONDS" ] || return 0
  /bin/mv -f "$LOG_FILE" "$PREVIOUS_LOG_FILE"
  keep_from=$(first_data_epoch "$PREVIOUS_LOG_FILE")
  case "$keep_from" in
    ''|*[!0-9]*) return 0 ;;
  esac
  for snapshot in "$SNAPSHOT_DIR"/*.census.tsv.gz "$SNAPSHOT_DIR"/*.commands.tsv.gz; do
    [ -e "$snapshot" ] || continue
    snapshot_epoch=${snapshot##*/}
    snapshot_epoch=${snapshot_epoch%%.*}
    snapshot_epoch=${snapshot_epoch%%-*}
    case "$snapshot_epoch" in
      ''|*[!0-9]*) continue ;;
    esac
    [ "$snapshot_epoch" -ge "$keep_from" ] || /bin/rm -f "$snapshot"
  done
}

sample() {
  for executable in "$ZPRINT_BIN" "$SYSCTL_BIN" "$DATE_BIN" "$PS_BIN" "$AWK_BIN" "$GZIP_BIN" "$MKTEMP_BIN" "$SORT_BIN"; do
    require_executable "$executable"
  done

  umask 022
  /bin/mkdir -p "$LOG_DIR" "$SNAPSHOT_DIR" || fail "could not create log directory: $LOG_DIR"
  make_work_dir

  timestamp_utc=$($DATE_BIN -u '+%Y-%m-%dT%H:%M:%SZ')
  sample_epoch=$($DATE_BIN '+%s')
  case "$sample_epoch" in
    ''|*[!0-9]*) die_recorded "date returned a non-numeric epoch" ;;
  esac
  # Two samples can land in one second (a manual run beside the agent), so the
  # snapshot id carries this sampler's pid as well as the epoch.
  snapshot_id="$sample_epoch-$$"

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
    ''|*[!0-9]*) die_recorded "kern.boottime was unavailable" ;;
  esac
  uptime_seconds=$((sample_epoch - boot_epoch))
  [ "$uptime_seconds" -ge 0 ] || die_recorded "sample time preceded kern.boottime"

  num_files=$($SYSCTL_BIN -n kern.num_files 2>/dev/null || true)
  case "$num_files" in
    ''|*[!0-9]*) num_files=unavailable ;;
  esac

  tty_count=0
  for tty_path in "$DEV_DIR"/ttys[0-9]*; do
    [ -e "$tty_path" ] || continue
    tty_count=$((tty_count + 1))
  done

  if ! "$PS_BIN" -axo pid=,ppid=,etime=,comm= > "$work_dir/ps.txt" 2> "$work_dir/ps.err"; then
    detail=$(/usr/bin/head -c 512 "$work_dir/ps.err" | /usr/bin/tr '\t\r\n' '   ')
    die_recorded "ps failed: ${detail:-no diagnostic}"
  fi
  # Census: pid, ppid, etime, comm (comm may contain spaces; it is the rest of the line).
  "$AWK_BIN" '
    $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ && NF >= 4 {
      pid = $1; ppid = $2; etime = $3
      line = $0
      sub(/^[[:space:]]*[0-9]+[[:space:]]+[0-9]+[[:space:]]+[-0-9:]+[[:space:]]+/, "", line)
      gsub(/\t/, " ", line)
      printf "%s\t%s\t%s\t%s\n", pid, ppid, etime, line
    }
  ' "$work_dir/ps.txt" > "$work_dir/census.tsv"
  [ -s "$work_dir/census.tsv" ] || die_recorded "ps returned no processes"
  process_count=$("$AWK_BIN" 'END { print NR + 0 }' "$work_dir/census.tsv")
  highest_pid=$("$AWK_BIN" -F '\t' '$1 > max { max = $1 + 0 } END { print max + 0 }' "$work_dir/census.tsv")
  "$AWK_BIN" -F '\t' '{ count[$4] += 1 } END { for (name in count) printf "%d\t%s\n", count[name], name }' \
    "$work_dir/census.tsv" | "$SORT_BIN" -t "$(printf '\t')" -k2,2 > "$work_dir/commands.tsv"

  if ! "$ZPRINT_BIN" -t > "$work_dir/zprint.txt" 2> "$work_dir/zprint.err"; then
    detail=$(/usr/bin/head -c 512 "$work_dir/zprint.err" | /usr/bin/tr '\t\r\n' '   ')
    die_recorded "zprint failed: ${detail:-no diagnostic}"
  fi

  if ! "$AWK_BIN" \
    -v schema=1 \
    -v timestamp="$timestamp_utc" \
    -v sample_epoch="$sample_epoch" \
    -v boot_epoch="$boot_epoch" \
    -v uptime="$uptime_seconds" \
    -v num_files="$num_files" \
    -v ttys="$tty_count" \
    -v highest_pid="$highest_pid" \
    -v processes="$process_count" \
    -v snapshot_id="$snapshot_id" '
      $1 ~ /^data\.kalloc\.[0-9]+$/ && NF >= 7 && $7 ~ /^[0-9]+$/ {
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%.0f\t%s\t%s\t%s\t%s\t%s\n", \
          schema, timestamp, sample_epoch, boot_epoch, uptime, $1, $2, $7, $2 * $7, \
          num_files, ttys, highest_pid, processes, snapshot_id
        count += 1
      }
      END { if (count == 0) exit 42 }
    ' "$work_dir/zprint.txt" > "$work_dir/rows.tsv"; then
    die_recorded "zprint returned no data.kalloc size-class rows"
  fi

  target_row=$("$AWK_BIN" -F '\t' -v zone="$DEFAULT_ZONE" '$6 == zone { row = $0 } END { print row }' "$work_dir/rows.tsv")
  [ -n "$target_row" ] || die_recorded "$DEFAULT_ZONE was absent from the sample"

  rotate_if_due "$sample_epoch"

  "$GZIP_BIN" -c "$work_dir/census.tsv" > "$work_dir/census.tsv.gz"
  "$GZIP_BIN" -c "$work_dir/commands.tsv" > "$work_dir/commands.tsv.gz"
  /bin/mv -f "$work_dir/census.tsv.gz" "$SNAPSHOT_DIR/$snapshot_id.census.tsv.gz"
  /bin/mv -f "$work_dir/commands.tsv.gz" "$SNAPSHOT_DIR/$snapshot_id.commands.tsv.gz"

  if [ ! -s "$LOG_FILE" ]; then
    printf '%b\n' 'schema_version\ttimestamp_utc\tsample_epoch_seconds\tboot_epoch_seconds\tuptime_seconds\tzone\telement_size_bytes\tinuse_elements\tderived_inuse_bytes\tkern_num_files\tdev_ttys_count\thighest_pid\tprocess_count\tsnapshot_id' > "$LOG_FILE"
  fi
  /bin/cat "$work_dir/rows.tsv" >> "$LOG_FILE"
  printf '%s\n' "$target_row"
}

# Prints the zone's rows from both generations, oldest first.
zone_rows() {
  zone=$1
  for source_file in "$PREVIOUS_LOG_FILE" "$LOG_FILE"; do
    [ -s "$source_file" ] || continue
    "$AWK_BIN" -F '\t' -v zone="$zone" 'NR > 1 && $6 == zone' "$source_file"
  done
}

census_path() {
  printf '%s/%s.census.tsv.gz' "$SNAPSHOT_DIR" "$1"
}

commands_path() {
  printf '%s/%s.commands.tsv.gz' "$SNAPSHOT_DIR" "$1"
}

# Diff the census of two samples: processes that appeared, exited, or were
# reparented, plus per-command count changes. A pid present in both samples is
# a new process when its etime is shorter than the gap between the samples.
diff_snapshots() {
  before_id=$1
  after_id=$2
  gap_seconds=$3
  before_census=$(census_path "$before_id")
  after_census=$(census_path "$after_id")
  if [ ! -s "$before_census" ] || [ ! -s "$after_census" ]; then
    printf '  census: unavailable (snapshot %s or %s was pruned or never written)\n' "$before_id" "$after_id"
    return 0
  fi
  "$GZIP_BIN" -dc "$before_census" > "$work_dir/before.census"
  "$GZIP_BIN" -dc "$after_census" > "$work_dir/after.census"
  "$AWK_BIN" -F '\t' -v gap="$gap_seconds" '
    function seconds(etime,    days, rest, parts, count) {
      days = 0
      rest = etime
      if (index(rest, "-") > 0) {
        days = substr(rest, 1, index(rest, "-") - 1)
        rest = substr(rest, index(rest, "-") + 1)
      }
      count = split(rest, parts, ":")
      if (count == 3) return days * 86400 + parts[1] * 3600 + parts[2] * 60 + parts[3]
      if (count == 2) return days * 86400 + parts[1] * 60 + parts[2]
      return days * 86400 + parts[1]
    }
    FNR == NR { before_ppid[$1] = $2; before_etime[$1] = $3; before_comm[$1] = $4; next }
    {
      after_ppid[$1] = $2; after_etime[$1] = $3; after_comm[$1] = $4
    }
    END {
      for (pid in after_comm) {
        fresh = !(pid in before_comm) || before_comm[pid] != after_comm[pid] || seconds(after_etime[pid]) < gap
        if (fresh) {
          parent = (after_ppid[pid] in after_comm) ? after_comm[after_ppid[pid]] : "exited-or-unknown"
          printf "  appeared\t%s\t%s\t%s\t%s\tparent=%s\n", pid, after_ppid[pid], after_etime[pid], after_comm[pid], parent
          if (pid in before_comm) reused[pid] = 1
        } else if (before_ppid[pid] != after_ppid[pid]) {
          printf "  reparented\t%s\t%s->%s\t%s\t%s\n", pid, before_ppid[pid], after_ppid[pid], after_etime[pid], after_comm[pid]
        }
      }
      for (pid in before_comm) {
        if (!(pid in after_comm) || (pid in reused)) {
          printf "  exited\t%s\t%s\t%s\t%s\n", pid, before_ppid[pid], before_etime[pid], before_comm[pid]
        }
      }
    }
  ' "$work_dir/before.census" "$work_dir/after.census" | "$SORT_BIN" -t "$(printf '\t')" -k1,1 -k2,2n
  before_commands=$(commands_path "$before_id")
  after_commands=$(commands_path "$after_id")
  if [ -s "$before_commands" ] && [ -s "$after_commands" ]; then
    "$GZIP_BIN" -dc "$before_commands" > "$work_dir/before.commands"
    "$GZIP_BIN" -dc "$after_commands" > "$work_dir/after.commands"
    "$AWK_BIN" -F '\t' '
      FNR == NR { before[$2] = $1; names[$2] = 1; next }
      { after[$2] = $1; names[$2] = 1 }
      END {
        for (name in names) {
          delta = after[name] - before[name]
          if (delta != 0) printf "  command_count\t%+d\t%d->%d\t%s\n", delta, before[name], after[name], name
        }
      }
    ' "$work_dir/before.commands" "$work_dir/after.commands" | "$SORT_BIN" -t "$(printf '\t')" -k4,4
  fi
}

field() {
  printf '%s\n' "$1" | "$AWK_BIN" -F '\t' -v column="$2" '{ print $column }'
}

report() {
  zone=${1:-$DEFAULT_ZONE}
  [ -s "$LOG_FILE" ] || [ -s "$PREVIOUS_LOG_FILE" ] || fail "sample log is missing or empty: $LOG_FILE"
  make_work_dir
  zone_rows "$zone" > "$work_dir/rows.tsv"
  [ -s "$work_dir/rows.tsv" ] || fail "no samples for $zone were found in $LOG_DIR"

  printf 'zone=%s\n' "$zone"
  printf 'log_dir=%s\n' "$LOG_DIR"
  printf 'onset_rate_per_hour=%s\n' "$ONSET_RATE_PER_HOUR"
  printf 'onset_rate_derivation=(quiet_max %s + episode_min %s) / 2, both hourly rates from the root watcher log\n' \
    "$QUIET_MAX_RATE_PER_HOUR" "$EPISODE_MIN_RATE_PER_HOUR"
  printf 'rate_window_seconds=%s\n' "$RATE_WINDOW_SECONDS"

  # Detection: the trailing-hour rate crosses ONSET_RATE_PER_HOUR. Localization:
  # from the loudest interval of that hour, walk back through the contiguous run
  # of intervals above QUIET_MAX_RATE_PER_HOUR; the census diff spans the first
  # interval of that run (its before and after samples).
  "$AWK_BIN" -F '\t' \
    -v threshold="$ONSET_RATE_PER_HOUR" \
    -v quiet_max="$QUIET_MAX_RATE_PER_HOUR" \
    -v window="$RATE_WINDOW_SECONDS" \
    -v tolerance="$BOOT_EPOCH_TOLERANCE_SECONDS" '
    function rate(a, b) { return (epoch[b] > epoch[a]) ? (inuse[b] - inuse[a]) * 3600 / (epoch[b] - epoch[a]) : 0 }
    function flush_boot(    i, j, k, m, best, trailing, active, start) {
      if (n == 0) return
      active = 0
      for (i = 2; i <= n; i += 1) {
        j = 0
        for (k = i - 1; k >= 1; k -= 1) {
          if (epoch[k] <= epoch[i] - window) { j = k; break }
        }
        if (j == 0) continue
        trailing = rate(j, i)
        if (!active && trailing >= threshold) {
          active = 1
          m = i
          if (rate(i - 1, i) < threshold) {
            best = i
            for (k = j + 1; k <= i; k += 1) if (rate(k - 1, k) > rate(best - 1, best)) best = k
            m = best
          }
          # Walk back through every contiguous interval louder than the loudest
          # quiet hour on record: a partial onset interval (the leak started
          # mid-interval) belongs to the episode even when it is under the line.
          while (m - 2 >= 1 && rate(m - 2, m - 1) > quiet_max) m -= 1
          start = m
          printf "ONSET\t%d\t%d\t%.0f\t%.0f\n", row[m - 1], row[m], rate(m - 1, m), trailing
        } else if (active && trailing < threshold) {
          active = 0
          printf "END\t%d\t%d\t%.0f\n", row[start], row[i], rate(start, i)
        }
      }
      if (active) printf "OPEN\t%d\t%d\t%.0f\n", row[start], row[n], rate(start, n)
    }
    {
      if (n > 0 && ($4 - boot > tolerance || boot - $4 > tolerance)) { flush_boot(); n = 0 }
      boot = $4
      n += 1
      row[n] = NR
      epoch[n] = $3
      inuse[n] = $8
    }
    END { flush_boot() }
  ' "$work_dir/rows.tsv" > "$work_dir/events.tsv"

  boots=$("$AWK_BIN" -F '\t' -v tolerance="$BOOT_EPOCH_TOLERANCE_SECONDS" '
    NR == 1 || $4 - boot > tolerance || boot - $4 > tolerance { count += 1 } { boot = $4 } END { print count + 0 }
  ' "$work_dir/rows.tsv")
  samples=$("$AWK_BIN" 'END { print NR + 0 }' "$work_dir/rows.tsv")
  printf 'boots=%s\n' "$boots"
  printf 'samples=%s\n' "$samples"
  printf 'first_timestamp_utc=%s\n' "$("$AWK_BIN" -F '\t' 'NR == 1 { print $2 }' "$work_dir/rows.tsv")"
  printf 'last_timestamp_utc=%s\n' "$("$AWK_BIN" -F '\t' 'END { print $2 }' "$work_dir/rows.tsv")"

  onset_count=$("$AWK_BIN" -F '\t' '$1 == "ONSET" { count += 1 } END { print count + 0 }' "$work_dir/events.tsv")
  printf 'onsets=%s\n' "$onset_count"

  onset_number=0
  while IFS="$(printf '\t')" read -r kind first_row second_row rate_value trailing_value; do
    before_line=$("$AWK_BIN" -v row="$first_row" 'NR == row' "$work_dir/rows.tsv")
    after_line=$("$AWK_BIN" -v row="$second_row" 'NR == row' "$work_dir/rows.tsv")
    case "$kind" in
      ONSET)
        onset_number=$((onset_number + 1))
        before_epoch=$(field "$before_line" 3)
        after_epoch=$(field "$after_line" 3)
        printf '\nonset %d\n' "$onset_number"
        printf '  before_sample_utc=%s inuse=%s\n' "$(field "$before_line" 2)" "$(field "$before_line" 8)"
        printf '  after_sample_utc=%s inuse=%s\n' "$(field "$after_line" 2)" "$(field "$after_line" 8)"
        printf '  onset_interval_rate_per_hour=%s trailing_hour_rate_per_hour_at_detection=%s\n' "$rate_value" "$trailing_value"
        printf '  kern_num_files=%s->%s dev_ttys=%s->%s highest_pid=%s->%s processes=%s->%s\n' \
          "$(field "$before_line" 10)" "$(field "$after_line" 10)" \
          "$(field "$before_line" 11)" "$(field "$after_line" 11)" \
          "$(field "$before_line" 12)" "$(field "$after_line" 12)" \
          "$(field "$before_line" 13)" "$(field "$after_line" 13)"
        printf '  census diff (kind, pid, ppid, etime, comm):\n'
        diff_snapshots "$(field "$before_line" 14)" "$(field "$after_line" 14)" $((after_epoch - before_epoch))
        ;;
      END)
        printf '  episode_end_utc=%s average_rate_per_hour=%s\n' "$(field "$after_line" 2)" "$rate_value"
        ;;
      OPEN)
        printf '  episode_open_at_last_sample_utc=%s average_rate_per_hour=%s\n' "$(field "$after_line" 2)" "$rate_value"
        ;;
    esac
  done < "$work_dir/events.tsv"
}

status() {
  "$LAUNCHCTL_BIN" print "gui/$(/usr/bin/id -u)/$LABEL" 2>&1 | "$AWK_BIN" '
    /^[[:space:]]*(path|state|runs|last exit code|run interval) = / { print }
  '
  printf '\n'
  report "${1:-$DEFAULT_ZONE}"
}

case "${1:-}" in
  sample)
    [ "$#" -eq 1 ] || { usage >&2; exit 64; }
    sample
    ;;
  report)
    [ "$#" -le 2 ] || { usage >&2; exit 64; }
    report "${2:-$DEFAULT_ZONE}"
    ;;
  status)
    [ "$#" -le 2 ] || { usage >&2; exit 64; }
    status "${2:-$DEFAULT_ZONE}"
    ;;
  interval)
    printf '%s\n' "$SAMPLE_INTERVAL_SECONDS"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 64
    ;;
esac
