#!/bin/sh
# Holy Ghostty kernel-zone user sampler (mn-579814; per-process kernel objects mn-e6f0f7).
#
# A user-domain companion to the root hourly watcher (holy-kernel-zone-watch.sh).
# The hourly counters could not name the process that feeds data.kalloc.1024, so
# this sampler records, every interval, the zone inuse counts plus the host-side
# quantities a feeder would move (open files, ptys, pid churn, per-command process
# counts) and a compact process census, so the samples on either side of an onset
# can be diffed. Everything it reads works unprivileged on macOS 26.6.1:
# zprint -t column 7 (inuse elements), sysctl kern.num_files, kern.boottime, ps,
# and the kernel-object collectors described below (lsmp needs root; not run).
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
#     With the kernel-object collectors below (measured 2026-09-26T20:19Z, 955
#     processes, three samples): +5.1 KB gzipped kobjects, +0.35 KB gzipped
#     interfaces, +0.82 KB of collectors.tsv rows = 32.6 KB per sample, about
#     9.4 MB per day and at most about 263 MB across both generations. A sample
#     took 1.31-1.32 s.
#
# Per-process kernel objects (mn-e6f0f7). A zone allocation carries no owner, so
# the sampler also records, per pid, the kernel objects a process holds, which
# userland can see: IOKit user clients, mach ports, sockets, open file
# descriptors, and pty descriptors, plus per-interface packet and byte counters.
# Each collector was measured on this machine (Mac Studio, macOS 26.6.1, uid 501,
# 940-954 processes, 2026-09-26T20:10Z-20:20Z, three runs each, /usr/bin/time -p):
#
#   ioreg -r -c IOUserClient -k IOUserClientCreator -d 1   0.03-0.04 s, unprivileged,
#     every pid (root daemons included), 908-916 creators. The unfiltered
#     ioreg -c IOUserClient -l took 0.46-0.48 s for the same creator count and
#     11 MB of output, so the filtered form is used.
#   top -l 1 -stats pid,ports                              0.49-0.51 s, unprivileged,
#     #PORTS for every process (launchd 4432, logd 2672, kernel_task 0).
#   lsmp -a                                                needs root: as uid 501 it
#     exits 1 at once with "task_for_pid() failed". Not run; top #PORTS gives the
#     per-pid mach port count without it. Recorded as skipped in collectors.tsv.
#   netstat -anv                                           0.03-0.04 s, unprivileged,
#     every socket with its process:pid (inet, unix, kernel event, kernel control,
#     pfkey, routing; 3,616 lines).
#   lsof -nPw -F pfn                                       0.14-0.15 s, unprivileged
#     but it lists only this uid's processes: 613 of 954 pids. Other users' pids
#     get "-" for open_fds and pty_fds (not visible), never 0.
#   netstat -ib                                            0.02-0.32 s, unprivileged,
#     39 interfaces (utun0-utun6 included).
#
# Under launchd (ProcessType Background, LowPriorityIO) the first installed
# sample, 2026-09-26T20:25:51Z, measured ioreg 0.13 s, top 2.30 s, netstat -anv
# 0.24 s, lsof 0.45 s, netstat -ib 0.02 s: 3.14 s in all, top the slowest.
# Interactively they add under 1 s. No collector is scoped to a pid subset: the
# work order's scoping rule (sample only long-lived pids, or cap by measured
# cost) applies past a few seconds per collector, and the slowest measured,
# top at 2.30 s under launchd, does not get cheaper when scoped: top -l 1 -pid 1
# took 0.50 s interactively, the same as the unscoped run. Each sample appends every collector's measured wall time, coverage, and
# status to collectors.tsv, so a slow or failing collector shows up in the log
# instead of being assumed. A failed collector writes "-" for its column and
# never drops the zone rows.
set -eu

LABEL="org.holyghostty.kernel-zone-usersample"
DEFAULT_LOG_DIR="$HOME/Library/Logs/Holy Ghostty/kernel-zone-usersample"
LOG_DIR=${HOLY_KERNEL_ZONE_USERSAMPLE_LOG_DIR:-$DEFAULT_LOG_DIR}
LOG_FILE="$LOG_DIR/samples.tsv"
PREVIOUS_LOG_FILE="$LOG_DIR/samples.tsv.1"
COLLECTOR_LOG="$LOG_DIR/collectors.tsv"
PREVIOUS_COLLECTOR_LOG="$LOG_DIR/collectors.tsv.1"
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
IOREG_BIN=${HOLY_KERNEL_ZONE_USERSAMPLE_IOREG_BIN:-/usr/sbin/ioreg}
TOP_BIN=${HOLY_KERNEL_ZONE_USERSAMPLE_TOP_BIN:-/usr/bin/top}
LSOF_BIN=${HOLY_KERNEL_ZONE_USERSAMPLE_LSOF_BIN:-/usr/sbin/lsof}
NETSTAT_BIN=${HOLY_KERNEL_ZONE_USERSAMPLE_NETSTAT_BIN:-/usr/sbin/netstat}
ID_BIN=${HOLY_KERNEL_ZONE_USERSAMPLE_ID_BIN:-/usr/bin/id}
TIME_BIN=/usr/bin/time
AWK_BIN=/usr/bin/awk
GZIP_BIN=/usr/bin/gzip
MKTEMP_BIN=/usr/bin/mktemp
SORT_BIN=/usr/bin/sort

usage() {
  printf '%s\n' \
    'Usage: holy-kernel-zone-usersample.sh sample' \
    '       holy-kernel-zone-usersample.sh report [zone]' \
    '       holy-kernel-zone-usersample.sh compare <before_snapshot_id> <after_snapshot_id> [zone]' \
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
  if [ -e "$COLLECTOR_LOG" ]; then
    /bin/mv -f "$COLLECTOR_LOG" "$PREVIOUS_COLLECTOR_LOG"
  fi
  keep_from=$(first_data_epoch "$PREVIOUS_LOG_FILE")
  case "$keep_from" in
    ''|*[!0-9]*) return 0 ;;
  esac
  for snapshot in "$SNAPSHOT_DIR"/*.census.tsv.gz "$SNAPSHOT_DIR"/*.commands.tsv.gz \
    "$SNAPSHOT_DIR"/*.kobjects.tsv.gz "$SNAPSHOT_DIR"/*.interfaces.tsv.gz; do
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

# Runs one collector under /usr/bin/time and leaves, in $work_dir: <name>.raw
# (stdout), <name>.err, and <name>.seconds (measured wall time). Returns the
# collector's exit status; a missing executable returns 127 with a named reason.
run_collector() {
  collector_name=$1
  shift
  if [ ! -x "$1" ]; then
    printf 'executable unavailable: %s\n' "$1" > "$work_dir/$collector_name.err"
    : > "$work_dir/$collector_name.raw"
    printf 'unmeasured\n' > "$work_dir/$collector_name.seconds"
    return 127
  fi
  collector_status=0
  "$TIME_BIN" -p -o "$work_dir/$collector_name.time" "$@" \
    > "$work_dir/$collector_name.raw" 2> "$work_dir/$collector_name.err" || collector_status=$?
  "$AWK_BIN" '$1 == "real" { print $2; found = 1 } END { if (!found) print "unmeasured" }' \
    "$work_dir/$collector_name.time" > "$work_dir/$collector_name.seconds" 2>/dev/null \
    || printf 'unmeasured\n' > "$work_dir/$collector_name.seconds"
  return "$collector_status"
}

collector_error() {
  /usr/bin/head -c 256 "$work_dir/$1.err" | /usr/bin/tr '\t\r\n' '   '
}

# Appends one collectors.tsv row to $work_dir/collectors.rows.
collector_row() {
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    1 "$timestamp_utc" "$sample_epoch" "$snapshot_id" "$1" "$2" "$3" "$4" "$5" >> "$work_dir/collectors.rows"
}

# Parsers. Each reads one collector's raw output and prints "pid<TAB>count"
# (or the interface table); they are separate so the test can feed them fixtures.

# ioreg: every "IOUserClientCreator" = "pid 589, logd" is one user client.
parse_ioreg_user_clients() {
  "$AWK_BIN" '
    /"IOUserClientCreator" = "pid [0-9]+,/ {
      if (match($0, /"pid [0-9]+,/)) count[substr($0, RSTART + 5, RLENGTH - 6)] += 1
    }
    END { for (pid in count) printf "%s\t%d\n", pid, count[pid] }
  ' "$1"
}

# top -l 1 -stats pid,ports: rows after the "PID #PORTS" header.
parse_top_ports() {
  "$AWK_BIN" '
    header && $1 ~ /^[0-9]+$/ && NF >= 2 {
      ports = $2
      gsub(/[^0-9]/, "", ports)
      if (ports != "") printf "%s\t%s\n", $1, ports
    }
    $1 == "PID" { header = 1 }
  ' "$1"
}

# netstat -anv: every section with a process:pid column (inet, unix, kernel
# event, kernel control, pfkey, routing). The process name is truncated and may
# hold spaces ("Browser Helper:1201"), so the pid is the field ending in :digits
# that is followed by the state (5 hex), options (8 hex), and gencnt (16 hex)
# columns; IPv6 addresses end in .port, never :digits followed by that shape.
parse_netstat_sockets() {
  "$AWK_BIN" '
    function hex(value, width) { return length(value) == width && value ~ /^[0-9a-f]+$/ }
    {
      for (i = 1; i + 3 <= NF; i += 1) {
        if ($i ~ /:[0-9]+$/ && hex($(i + 1), 5) && hex($(i + 2), 8) && hex($(i + 3), 16)) {
          pid = $i
          sub(/.*:/, "", pid)
          count[pid] += 1
          break
        }
      }
    }
    END { for (pid in count) printf "%s\t%d\n", pid, count[pid] }
  ' "$1"
}

# lsof -F pfn: "p<pid>", then per file "f<fd>" and "n<name>". Counts numeric
# descriptors (what kern.num_files counts; cwd, txt, and mapped files excluded)
# and, of those, /dev/ttys* and /dev/ptmx descriptors. Prints pid, fds, ptys
# for every pid lsof listed, zero counts included.
parse_lsof_fds() {
  "$AWK_BIN" '
    /^p[0-9]+$/ { pid = substr($0, 2); fds[pid] += 0; ptys[pid] += 0; numeric = 0; next }
    /^f/ { numeric = (substr($0, 2) ~ /^[0-9]+$/); if (numeric && pid != "") fds[pid] += 1; next }
    /^n/ { if (numeric && pid != "" && substr($0, 2) ~ /^\/dev\/(ttys[0-9]+|ptmx)$/) ptys[pid] += 1; next }
    END { for (pid in fds) printf "%s\t%d\t%d\n", pid, fds[pid], ptys[pid] }
  ' "$1"
}

# netstat -ib: the <Link#N> row of each interface carries its counters; the
# Address column is empty for some (utun), so counters are read from the end.
# A trailing * (interface down) is dropped so the name stays one key.
parse_netstat_interfaces() {
  "$AWK_BIN" '
    $3 ~ /^<Link#[0-9]+>$/ && NF >= 10 {
      name = $1
      sub(/\*$/, "", name)
      ok = 1
      for (i = NF - 6; i <= NF - 1; i += 1) if ($i !~ /^[0-9]+$/) ok = 0
      if (ok) printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", name, $(NF - 6), $(NF - 5), $(NF - 4), $(NF - 3), $(NF - 2), $(NF - 1)
    }
  ' "$1"
}

# Runs the kernel-object collectors and writes $work_dir/kobjects.tsv (one row
# per census pid) and $work_dir/interfaces.tsv, plus collectors.rows.
collect_kernel_objects() {
  : > "$work_dir/collectors.rows"
  euid=$("$ID_BIN" -u 2>/dev/null || printf 'unknown')
  census_pids=$("$AWK_BIN" 'END { print NR + 0 }' "$work_dir/census.tsv")

  iokit_state=failed
  if run_collector ioreg "$IOREG_BIN" -r -c IOUserClient -k IOUserClientCreator -d 1; then
    parse_ioreg_user_clients "$work_dir/ioreg.raw" > "$work_dir/iokit.tsv"
    iokit_state=ok
    collector_row ioreg_user_clients ok "$(/bin/cat "$work_dir/ioreg.seconds")" \
      "$("$AWK_BIN" 'END { print NR + 0 }' "$work_dir/iokit.tsv")" \
      "user_clients=$("$AWK_BIN" -F '\t' '{ total += $2 } END { print total + 0 }' "$work_dir/iokit.tsv")"
  else
    : > "$work_dir/iokit.tsv"
    collector_row ioreg_user_clients failed "$(/bin/cat "$work_dir/ioreg.seconds")" 0 "$(collector_error ioreg)"
  fi

  ports_state=failed
  : > "$work_dir/ports.tsv"
  if run_collector top "$TOP_BIN" -l 1 -stats pid,ports; then
    parse_top_ports "$work_dir/top.raw" > "$work_dir/ports.tsv"
    if [ -s "$work_dir/ports.tsv" ]; then
      ports_state=ok
      collector_row top_mach_ports ok "$(/bin/cat "$work_dir/top.seconds")" \
        "$("$AWK_BIN" 'END { print NR + 0 }' "$work_dir/ports.tsv")" \
        "mach_ports=$("$AWK_BIN" -F '\t' '{ total += $2 } END { print total + 0 }' "$work_dir/ports.tsv")"
    else
      collector_row top_mach_ports failed "$(/bin/cat "$work_dir/top.seconds")" 0 'top printed no PID #PORTS rows'
    fi
  else
    collector_row top_mach_ports failed "$(/bin/cat "$work_dir/top.seconds")" 0 "$(collector_error top)"
  fi
  collector_row lsmp_mach_ports skipped - - \
    'not run: lsmp -a needs root (as uid 501 it exits 1, task_for_pid() failed, measured 2026-09-26); top #PORTS covers every pid unprivileged'

  sockets_state=failed
  if run_collector netstat_sockets "$NETSTAT_BIN" -anv; then
    parse_netstat_sockets "$work_dir/netstat_sockets.raw" > "$work_dir/sockets.tsv"
    sockets_state=ok
    collector_row netstat_sockets ok "$(/bin/cat "$work_dir/netstat_sockets.seconds")" \
      "$("$AWK_BIN" 'END { print NR + 0 }' "$work_dir/sockets.tsv")" \
      "sockets=$("$AWK_BIN" -F '\t' '{ total += $2 } END { print total + 0 }' "$work_dir/sockets.tsv")"
  else
    : > "$work_dir/sockets.tsv"
    collector_row netstat_sockets failed "$(/bin/cat "$work_dir/netstat_sockets.seconds")" 0 "$(collector_error netstat_sockets)"
  fi

  fds_state=failed
  if run_collector lsof "$LSOF_BIN" -nPw -F pfn; then
    parse_lsof_fds "$work_dir/lsof.raw" > "$work_dir/fds.tsv"
    fds_state=ok
    visible=$("$AWK_BIN" 'END { print NR + 0 }' "$work_dir/fds.tsv")
    lsof_status=ok
    lsof_detail="open_fds=$("$AWK_BIN" -F '\t' '{ total += $2 } END { print total + 0 }' "$work_dir/fds.tsv") pty_fds=$("$AWK_BIN" -F '\t' '{ total += $3 } END { print total + 0 }' "$work_dir/fds.tsv")"
    if [ "$euid" != 0 ]; then
      lsof_status=partial
      lsof_detail="$lsof_detail unprivileged (uid $euid): lsof lists only this uid's processes, $visible of $census_pids census pids; the rest are recorded as -"
    fi
    collector_row lsof_fds "$lsof_status" "$(/bin/cat "$work_dir/lsof.seconds")" "$visible" "$lsof_detail"
  else
    : > "$work_dir/fds.tsv"
    collector_row lsof_fds failed "$(/bin/cat "$work_dir/lsof.seconds")" 0 "$(collector_error lsof)"
  fi

  if run_collector netstat_interfaces "$NETSTAT_BIN" -ib; then
    parse_netstat_interfaces "$work_dir/netstat_interfaces.raw" > "$work_dir/interfaces.body"
    collector_row netstat_interfaces ok "$(/bin/cat "$work_dir/netstat_interfaces.seconds")" - \
      "interfaces=$("$AWK_BIN" 'END { print NR + 0 }' "$work_dir/interfaces.body")"
  else
    : > "$work_dir/interfaces.body"
    collector_row netstat_interfaces failed "$(/bin/cat "$work_dir/netstat_interfaces.seconds")" - "$(collector_error netstat_interfaces)"
  fi
  {
    printf 'interface\tipkts\tierrs\tibytes\topkts\toerrs\tobytes\n'
    "$SORT_BIN" -t "$(printf '\t')" -k1,1 "$work_dir/interfaces.body"
  } > "$work_dir/interfaces.tsv"

  # One row per census pid. ioreg and netstat list the whole system, so a pid
  # they do not name holds none (0); top and lsof name every pid they can see,
  # so a pid they omit is unknown (-). A failed collector is - for every pid.
  {
    printf 'pid\tiokit_user_clients\tmach_ports\tsockets\topen_fds\tpty_fds\n'
    "$AWK_BIN" -F '\t' \
      -v iokit_state="$iokit_state" -v ports_state="$ports_state" \
      -v sockets_state="$sockets_state" -v fds_state="$fds_state" '
      FILENAME == ARGV[1] { iokit[$1] = $2; next }
      FILENAME == ARGV[2] { ports[$1] = $2; next }
      FILENAME == ARGV[3] { sockets[$1] = $2; next }
      FILENAME == ARGV[4] { fds[$1] = $2; ptys[$1] = $3; next }
      {
        pid = $1
        u = iokit_state != "ok" ? "-" : (pid in iokit ? iokit[pid] : 0)
        p = ports_state != "ok" ? "-" : (pid in ports ? ports[pid] : "-")
        s = sockets_state != "ok" ? "-" : (pid in sockets ? sockets[pid] : 0)
        f = fds_state != "ok" ? "-" : (pid in fds ? fds[pid] : "-")
        t = fds_state != "ok" ? "-" : (pid in fds ? ptys[pid] : "-")
        printf "%s\t%s\t%s\t%s\t%s\t%s\n", pid, u, p, s, f, t
      }
    ' "$work_dir/iokit.tsv" "$work_dir/ports.tsv" "$work_dir/sockets.tsv" "$work_dir/fds.tsv" "$work_dir/census.tsv"
  } > "$work_dir/kobjects.tsv"
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

  collect_kernel_objects
  "$AWK_BIN" -F '\t' '$6 == "failed" { printf "%s\tcollector %s failed: %s\n", $2, $5, $9 }' \
    "$work_dir/collectors.rows" >> "$ERROR_LOG" 2>/dev/null || true

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
  "$GZIP_BIN" -c "$work_dir/kobjects.tsv" > "$work_dir/kobjects.tsv.gz"
  "$GZIP_BIN" -c "$work_dir/interfaces.tsv" > "$work_dir/interfaces.tsv.gz"
  /bin/mv -f "$work_dir/kobjects.tsv.gz" "$SNAPSHOT_DIR/$snapshot_id.kobjects.tsv.gz"
  /bin/mv -f "$work_dir/interfaces.tsv.gz" "$SNAPSHOT_DIR/$snapshot_id.interfaces.tsv.gz"
  if [ ! -s "$COLLECTOR_LOG" ]; then
    printf '%b\n' 'schema_version\ttimestamp_utc\tsample_epoch_seconds\tsnapshot_id\tcollector\tstatus\twall_seconds\tpids_reported\tdetail' > "$COLLECTOR_LOG"
  fi
  /bin/cat "$work_dir/collectors.rows" >> "$COLLECTOR_LOG"

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

kobjects_path() {
  printf '%s/%s.kobjects.tsv.gz' "$SNAPSHOT_DIR" "$1"
}

interfaces_path() {
  printf '%s/%s.interfaces.tsv.gz' "$SNAPSHOT_DIR" "$1"
}

# Per-process kernel-object growth between two samples, every metric, every pid
# that grew, ranked within each metric by growth per hour. A process new in the
# window (by the census rule above) grows from 0 and prints "new" as its before
# value. A "-" on either side (not visible, collector failed) is never compared.
kernel_object_growth() {
  before_id=$1
  after_id=$2
  gap_seconds=$3
  before_kobjects=$(kobjects_path "$before_id")
  after_kobjects=$(kobjects_path "$after_id")
  if [ ! -s "$before_kobjects" ] || [ ! -s "$after_kobjects" ]; then
    printf '  kernel objects: unavailable (snapshot %s or %s predates mn-e6f0f7, was pruned, or was never written)\n' "$before_id" "$after_id"
    return 0
  fi
  "$GZIP_BIN" -dc "$before_kobjects" > "$work_dir/before.kobjects"
  "$GZIP_BIN" -dc "$after_kobjects" > "$work_dir/after.kobjects"
  : > "$work_dir/before.census.k"
  : > "$work_dir/after.census.k"
  if [ -s "$(census_path "$before_id")" ] && [ -s "$(census_path "$after_id")" ]; then
    "$GZIP_BIN" -dc "$(census_path "$before_id")" > "$work_dir/before.census.k"
    "$GZIP_BIN" -dc "$(census_path "$after_id")" > "$work_dir/after.census.k"
  fi
  printf '  kernel objects grown over the window, ranked per metric (metric, growth_per_hour, before->after, pid, comm):\n'
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
    FILENAME == ARGV[1] { before_comm[$1] = $4; next }
    FILENAME == ARGV[2] { after_comm[$1] = $4; after_etime[$1] = $3; have_census = 1; next }
    FILENAME == ARGV[3] {
      if ($1 == "pid") next
      for (c = 2; c <= NF; c += 1) before[$1, c] = $c
      in_before[$1] = 1
      next
    }
    FILENAME == ARGV[4] {
      if ($1 == "pid") { for (c = 2; c <= NF; c += 1) metric[c] = $c; columns = NF; next }
      pid = $1
      fresh = !(pid in in_before)
      if (have_census && (pid in after_comm)) {
        fresh = fresh || !(pid in before_comm) || before_comm[pid] != after_comm[pid] || seconds(after_etime[pid]) < gap
      }
      comm = (pid in after_comm) ? after_comm[pid] : "unknown"
      for (c = 2; c <= columns; c += 1) {
        after_value = $c
        if (after_value !~ /^[0-9]+$/) continue
        if (fresh) {
          before_value = 0
          shown = "new"
        } else {
          before_value = before[pid, c]
          if (before_value !~ /^[0-9]+$/) continue
          shown = before_value
        }
        if (after_value + 0 <= before_value + 0) continue
        printf "  grew\t%s\t%.0f\t%s->%s\t%s\t%s\n", metric[c], (after_value - before_value) * 3600 / gap, shown, after_value, pid, comm
        grown += 1
      }
    }
    END { if (grown == 0) printf "  grew\tnone\n" }
  ' "$work_dir/before.census.k" "$work_dir/after.census.k" "$work_dir/before.kobjects" "$work_dir/after.kobjects" \
    | "$SORT_BIN" -t "$(printf '\t')" -k2,2 -k3,3nr -k5,5n
}

# Per-interface packet rate over the window, beside the rate over the interval
# before it (when a same-boot sample precedes the window), ranked by how much
# the packet rate changed. Interfaces with no packets in either interval are
# left out; a counter that went backwards (interface recreated) is named.
interface_change() {
  previous_id=$1
  before_id=$2
  after_id=$3
  previous_gap=$4
  gap_seconds=$5
  before_interfaces=$(interfaces_path "$before_id")
  after_interfaces=$(interfaces_path "$after_id")
  if [ ! -s "$before_interfaces" ] || [ ! -s "$after_interfaces" ]; then
    printf '  interfaces: unavailable (snapshot %s or %s predates mn-e6f0f7, was pruned, or was never written)\n' "$before_id" "$after_id"
    return 0
  fi
  "$GZIP_BIN" -dc "$before_interfaces" > "$work_dir/before.interfaces"
  "$GZIP_BIN" -dc "$after_interfaces" > "$work_dir/after.interfaces"
  : > "$work_dir/previous.interfaces"
  if [ -n "$previous_id" ] && [ -s "$(interfaces_path "$previous_id")" ]; then
    "$GZIP_BIN" -dc "$(interfaces_path "$previous_id")" > "$work_dir/previous.interfaces"
  else
    previous_gap=0
  fi
  printf '  interface packet rates, ranked by change (interface, packets_per_hour window, previous interval, change, ipkts, opkts, ibytes, obytes):\n'
  "$AWK_BIN" -F '\t' -v gap="$gap_seconds" -v previous_gap="$previous_gap" '
    FILENAME == ARGV[1] { if ($1 != "interface") { p_in[$1] = $2; p_out[$1] = $5 } next }
    FILENAME == ARGV[2] { if ($1 != "interface") { b_in[$1] = $2; b_out[$1] = $5; b_ib[$1] = $4; b_ob[$1] = $7 } next }
    $1 != "interface" && ($1 in b_in) {
      name = $1
      window = ($2 + $5) - (b_in[name] + b_out[name])
      counters = sprintf("%s->%s\t%s->%s\t%s->%s\t%s->%s", b_in[name], $2, b_out[name], $5, b_ib[name], $4, b_ob[name], $7)
      if (window < 0) { printf "0\t  interface\t%s\tcounter_reset\t-\t-\t%s\n", name, counters; next }
      window_rate = window * 3600 / gap
      if (previous_gap > 0 && (name in p_in)) {
        previous = (b_in[name] + b_out[name]) - (p_in[name] + p_out[name])
        if (previous < 0) { previous_text = "counter_reset"; change = window_rate }
        else { previous_rate = previous * 3600 / previous_gap; previous_text = sprintf("%.0f", previous_rate); change = window_rate - previous_rate }
      } else {
        previous = 0
        previous_text = "-"
        change = window_rate
      }
      if (window == 0 && previous == 0) next
      magnitude = change < 0 ? -change : change
      printf "%.0f\t  interface\t%s\t%.0f\t%s\t%+.0f\t%s\n", magnitude, name, window_rate, previous_text, change, counters
      shown += 1
    }
    END { if (shown == 0) printf "0\t  interface\tnone\n" }
  ' "$work_dir/previous.interfaces" "$work_dir/before.interfaces" "$work_dir/after.interfaces" \
    | "$SORT_BIN" -t "$(printf '\t')" -k1,1nr -k3,3 | /usr/bin/cut -f 2-
}

# Rows of the zone log whose snapshot precedes row $1 in the same boot, or empty.
previous_same_boot_row() {
  "$AWK_BIN" -F '\t' -v row="$1" -v tolerance="$BOOT_EPOCH_TOLERANCE_SECONDS" '
    NR == row - 1 { previous = $0; previous_boot = $4 }
    NR == row {
      if (previous != "" && $4 - previous_boot <= tolerance && previous_boot - $4 <= tolerance) print previous
      exit
    }
  ' "$work_dir/rows.tsv"
}

# Everything the log knows about the window between two rows of rows.tsv.
attribute_window() {
  before_line=$1
  after_line=$2
  previous_line=$3
  before_epoch=$(field "$before_line" 3)
  after_epoch=$(field "$after_line" 3)
  printf '  census diff (kind, pid, ppid, etime, comm):\n'
  diff_snapshots "$(field "$before_line" 14)" "$(field "$after_line" 14)" $((after_epoch - before_epoch))
  kernel_object_growth "$(field "$before_line" 14)" "$(field "$after_line" 14)" $((after_epoch - before_epoch))
  previous_id=
  previous_gap=0
  if [ -n "$previous_line" ]; then
    previous_id=$(field "$previous_line" 14)
    previous_gap=$((before_epoch - $(field "$previous_line" 3)))
  fi
  interface_change "$previous_id" "$(field "$before_line" 14)" "$(field "$after_line" 14)" "$previous_gap" $((after_epoch - before_epoch))
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
        attribute_window "$before_line" "$after_line" "$(previous_same_boot_row "$first_row")"
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

# The same attribution the report prints at an onset, for any two samples of
# the zone log named by snapshot id (column 14), e.g. a jump under the line.
compare() {
  before_id=$1
  after_id=$2
  zone=${3:-$DEFAULT_ZONE}
  [ -s "$LOG_FILE" ] || [ -s "$PREVIOUS_LOG_FILE" ] || fail "sample log is missing or empty: $LOG_FILE"
  make_work_dir
  zone_rows "$zone" > "$work_dir/rows.tsv"
  before_row=$("$AWK_BIN" -F '\t' -v id="$before_id" '$14 == id { print NR; exit }' "$work_dir/rows.tsv")
  after_row=$("$AWK_BIN" -F '\t' -v id="$after_id" '$14 == id { print NR; exit }' "$work_dir/rows.tsv")
  [ -n "$before_row" ] || fail "no $zone sample has snapshot id $before_id"
  [ -n "$after_row" ] || fail "no $zone sample has snapshot id $after_id"
  [ "$before_row" -lt "$after_row" ] || fail "$before_id is not earlier than $after_id"
  before_line=$("$AWK_BIN" -v row="$before_row" 'NR == row' "$work_dir/rows.tsv")
  after_line=$("$AWK_BIN" -v row="$after_row" 'NR == row' "$work_dir/rows.tsv")
  before_epoch=$(field "$before_line" 3)
  after_epoch=$(field "$after_line" 3)
  gap_seconds=$((after_epoch - before_epoch))
  printf 'zone=%s\n' "$zone"
  printf 'log_dir=%s\n' "$LOG_DIR"
  printf 'before_sample_utc=%s inuse=%s snapshot=%s\n' "$(field "$before_line" 2)" "$(field "$before_line" 8)" "$before_id"
  printf 'after_sample_utc=%s inuse=%s snapshot=%s\n' "$(field "$after_line" 2)" "$(field "$after_line" 8)" "$after_id"
  printf 'window_seconds=%s zone_rate_per_hour=%s\n' "$gap_seconds" \
    "$("$AWK_BIN" -v a="$(field "$before_line" 8)" -v b="$(field "$after_line" 8)" -v gap="$gap_seconds" 'BEGIN { printf "%.0f", (gap > 0) ? (b - a) * 3600 / gap : 0 }')"
  printf 'kern_num_files=%s->%s dev_ttys=%s->%s highest_pid=%s->%s processes=%s->%s\n' \
    "$(field "$before_line" 10)" "$(field "$after_line" 10)" \
    "$(field "$before_line" 11)" "$(field "$after_line" 11)" \
    "$(field "$before_line" 12)" "$(field "$after_line" 12)" \
    "$(field "$before_line" 13)" "$(field "$after_line" 13)"
  attribute_window "$before_line" "$after_line" "$(previous_same_boot_row "$before_row")"
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
  compare)
    [ "$#" -ge 3 ] && [ "$#" -le 4 ] || { usage >&2; exit 64; }
    compare "$2" "$3" "${4:-$DEFAULT_ZONE}"
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
