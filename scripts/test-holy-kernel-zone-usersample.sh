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

# Kernel-object collectors (mn-e6f0f7). Each fake prints a captured fixture for
# the phase in FAKE_KOBJ_PHASE (before, after) and checks its own arguments.
FIXTURES="$TEST_DIR/fixtures"
export FIXTURES
/bin/mkdir -p "$FIXTURES"
FAKE_IOREG="$TEST_DIR/ioreg"
FAKE_TOP="$TEST_DIR/top"
FAKE_LSOF="$TEST_DIR/lsof"
FAKE_NETSTAT="$TEST_DIR/netstat"
FAKE_ID="$TEST_DIR/id"

/bin/cat > "$FAKE_IOREG" <<'EOF'
#!/bin/sh
set -eu
[ "$*" = "-r -c IOUserClient -k IOUserClientCreator -d 1" ] || { printf 'unexpected ioreg call: %s\n' "$*" >&2; exit 64; }
[ "${FAKE_IOREG_FAIL:-0}" != "1" ] || { printf 'fixture ioreg failure\n' >&2; exit 71; }
/bin/cat "$FIXTURES/ioreg-${FAKE_KOBJ_PHASE:-before}.txt"
EOF

/bin/cat > "$FAKE_TOP" <<'EOF'
#!/bin/sh
set -eu
[ "$*" = "-l 1 -stats pid,ports" ] || { printf 'unexpected top call: %s\n' "$*" >&2; exit 64; }
/bin/cat "$FIXTURES/top-${FAKE_KOBJ_PHASE:-before}.txt"
EOF

/bin/cat > "$FAKE_LSOF" <<'EOF'
#!/bin/sh
set -eu
[ "$*" = "-nPw -F pfn" ] || { printf 'unexpected lsof call: %s\n' "$*" >&2; exit 64; }
/bin/cat "$FIXTURES/lsof-${FAKE_KOBJ_PHASE:-before}.txt"
EOF

/bin/cat > "$FAKE_NETSTAT" <<'EOF'
#!/bin/sh
set -eu
case "$*" in
  -anv) /bin/cat "$FIXTURES/netstat-anv-${FAKE_KOBJ_PHASE:-before}.txt" ;;
  -ib) /bin/cat "$FIXTURES/netstat-ib-${FAKE_KOBJ_PHASE:-before}.txt" ;;
  *) printf 'unexpected netstat call: %s\n' "$*" >&2; exit 64 ;;
esac
EOF

/bin/cat > "$FAKE_ID" <<'EOF'
#!/bin/sh
set -eu
if [ -n "${FAKE_EUID:-}" ] && [ "$*" = "-u" ]; then
  printf '%s\n' "$FAKE_EUID"
else
  exec /usr/bin/id "$@"
fi
EOF

/bin/chmod +x "$FAKE_ZPRINT" "$FAKE_SYSCTL" "$FAKE_DATE" "$FAKE_PS" "$FAKE_LAUNCHCTL" \
  "$FAKE_IOREG" "$FAKE_TOP" "$FAKE_LSOF" "$FAKE_NETSTAT" "$FAKE_ID"

# Fixtures: lines captured from this machine on 2026-09-26 (ioreg -r -c
# IOUserClient -k IOUserClientCreator -d 1, top -l 1 -stats pid,ports,
# lsof -nPw -F pfn, netstat -anv, netstat -ib), with pids rewritten onto the
# census fixtures below. Between before and after, zsh 4000 gains 4 user
# clients, 1,000 mach ports, 3 sockets, and 4 descriptors; the new leaky-helper
# 5000 opens a user client, ports, a socket, and a pty; utun6 carries 90,000
# packets; utun0 is recreated (its counters go backwards).
/bin/cat > "$FIXTURES/ioreg-before.txt" <<'EOF'
+-o RootDomainUserClient  <class RootDomainUserClient, id 0x100001c92, !registered, !matched, active, busy 0, retain 5>
    {
      "IOUserClientDefaultLocking" = Yes
      "IOUserClientCreator" = "pid 1, launchd"
      "IOUserClientEntitlements" = No
    }

+-o AppleKeyStoreUserClient  <class AppleKeyStoreUserClient, id 0x100001d10, !registered, !matched, active, busy 0, retain 6>
    {
      "IOUserClientCreator" = "pid 3300, Comet Helper (Renderer)"
    }
+-o IOSurfaceRootUserClient  <class IOSurfaceRootUserClient, id 0x100001d11, !registered, !matched, active, busy 0, retain 6>
    {
      "IOUserClientCreator" = "pid 3300, Comet Helper (Renderer)"
    }
+-o IOHIDLibUserClient  <class IOHIDLibUserClient, id 0x100001d12, !registered, !matched, active, busy 0, retain 6>
    {
      "IOUserClientCreator" = "pid 4000, zsh"
    }
EOF
/bin/cp "$FIXTURES/ioreg-before.txt" "$FIXTURES/ioreg-after.txt"
for n in 1 2 3 4; do
  printf '+-o IOHIDLibUserClient  <class IOHIDLibUserClient, id 0x10000200%s>\n    {\n      "IOUserClientCreator" = "pid 4000, zsh"\n    }\n' "$n"
done >> "$FIXTURES/ioreg-after.txt"
printf '+-o IOAudioEngineUserClient  <class IOAudioEngineUserClient, id 0x100003001>\n    {\n      "IOUserClientCreator" = "pid 5000, leaky-helper"\n    }\n' \
  >> "$FIXTURES/ioreg-after.txt"

TOP_HEADER='Processes: 940 total, 4 running, 936 sleeping, 7217 threads
2026/09/26 15:13:52
Load Avg: 3.09, 2.71, 2.47
CPU usage: 7.8% user, 8.9% sys, 84.82% idle
SharedLibs: 1551M resident, 222M data, 287M linkedit.
MemRegions: 683692 total, 25G resident, 1153M private, 9257M shared.
PhysMem: 74G used (4492M wired, 0B compressor), 180G unused.
VM: 430T vsize, 6144M framework vsize, 0(0) swapins, 0(0) swapouts.
Networks: packets: 2902593/1669M in, 3102299/2348M out.
Disks: 29799158/208G read, 18921176/211G written.

PID    #PORTS'
{
  printf '%s\n' "$TOP_HEADER"
  printf '%s\n' '4000   66    ' '3300   287   ' '3200   25    ' '3100   30    ' '3001   20    ' '3000   50    ' '1      4432  ' '0      0     '
} > "$FIXTURES/top-before.txt"
{
  printf '%s\n' "$TOP_HEADER"
  printf '%s\n' '5000   12    ' '4000   1066+ ' '3300   287   ' '3200   25    ' '3100   31    ' '3000   50    ' '1      4432  ' '0      0     '
} > "$FIXTURES/top-after.txt"

# lsof -F: launchd (pid 1, root) is not listed, as unprivileged lsof omits it.
/bin/cat > "$FIXTURES/lsof-before.txt" <<'EOF'
p3000
fcwd
n/
ftxt
n/opt/homebrew/bin/tmux
f0
n/dev/null
f3
n/dev/ptmx
p3300
f5
n/Users/erik/Library/Application Support/Comet/Default/History
p4000
fcwd
n/Users/erik
ftxt
n/bin/zsh
f0
n/dev/ttys001
f1
n/dev/ttys001
f2
n/dev/ttys001
f10
n/Users/erik/.zsh_history
EOF
/bin/cat "$FIXTURES/lsof-before.txt" > "$FIXTURES/lsof-after.txt"
printf '%s\n' f11 n/private/tmp/a f12 n/private/tmp/b f13 n/private/tmp/c f14 n/private/tmp/d p5000 f0 n/dev/ttys002 \
  >> "$FIXTURES/lsof-after.txt"

/bin/cat > "$FIXTURES/netstat-anv-before.txt" <<'EOF'
Active Internet connections (including servers)
Proto Recv-Q Send-Q  Local Address                                 Foreign Address                               (state)          rxbytes      txbytes  rhiwat  shiwat          process:pid    state  options           gencnt    flags   flags1 usecnt rtncnt fltrs
tcp4       0      0  192.168.50.143.64245   142.251.178.188.5228   ESTABLISHED        13928         2265  131072  131600   Comet Helper:3300   00102 00000008 0000000000344a58 00000080 04000900      2      0 000000
tcp6       0      0  fe80::c34:4384:6.49194 fe80::142d:1153:.64524 ESTABLISHED        10640         1962  131072  131376         rapportd:3000    00102 00000004 000000000033af39 00080083 01000800      2      0 000000
Active Multipath Internet connections
Proto/ID  Flags      Local Address          Foreign Address        (state)
Active LOCAL (UNIX) domain sockets
Address          Type   Recv-Q Send-Q            Inode             Conn             Refs          Nextref      rxbytes      txbytes  rhiwat  shiwat          process:pid    state  options           gencnt    flags   flags1 usecnt rtncnt fltrs Addr
884704a288ad5059 stream      0      0                0 c77b5c4fd4d46d6d                0                0            0            0    8192  524288       claude.exe:4000  00102 00000000 0000000000344942 00008001 00000000      2      0 000000
Registered kernel control modules
id       name
1        com.apple.flow-divert
Active kernel event sockets
Proto Recv-Q Send-Q vendor  class  subcl      rxbytes      txbytes  rhiwat  shiwat          process:pid    state  options           gencnt    flags   flags1 usecnt rtncnt fltrs
kevt       0      0      1      1      9       313320            0   32768    4096    mDNSResponder:3000    00100 00000000 0000000000040dc7 00008000 00000000      1      0 000000
Active kernel control sockets
Proto Recv-Q Send-Q      rxbytes      txbytes  rhiwat  shiwat          process:pid    state  options           gencnt    flags   flags1 usecnt rtncnt fltrs   unit     id name
kctl       0      0            0          577 2097152 1048576   UserEventAgent:1    00182 00000000 0000000000005005 00008000 00000000      1      0 000000      1      2 com.apple.flow-divert
EOF
/bin/cat "$FIXTURES/netstat-anv-before.txt" > "$FIXTURES/netstat-anv-after.txt"
for n in 1 2 3; do
  printf 'c77b5c4fd4d46d6%s stream      0      0                0 884704a288ad5059                0                0            0            0  524288    8192       claude.exe:4000  00002 00000000 000000000034494%s 00008001 00000000      2      0 000000\n' "$n" "$n"
done >> "$FIXTURES/netstat-anv-after.txt"
printf '%s\n' 'udp4       0      0  *.138                  *.*                                       83012        19350  786896    9216     leaky-helper:5000   00080 00000024 0000000000003533 00000003 04002800      1      0 000002' \
  >> "$FIXTURES/netstat-anv-after.txt"

NETSTAT_IB_HEADER='Name       Mtu   Network       Address            Ipkts Ierrs     Ibytes    Opkts Oerrs     Obytes  Coll'
{
  printf '%s\n' "$NETSTAT_IB_HEADER"
  printf '%s\n' \
    'lo0        16384 <Link#1>                         36536     0  133081914    36536     0  133081914     0' \
    'lo0        16384 127           localhost          36536     -  133081914    36536     -  133081914     -' \
    'en0*       1500  <Link#10>   1c:1d:d3:dd:60:f3        0     0          0        0     0          0     0' \
    'utun0      1280  <Link#33>                         6172     0     425032      178     0      20601     0' \
    'utun0      1280  100.64.0.2/ example-studio     6172     -     425032      178     -      20601     -' \
    'utun6      1280  <Link#39>                       267543     0   24680991   714431     0  790539309     0' \
    'utun6      1280  example-stu fe80:27::1e1d:d3f   267543     -   24680991   714431     -  790539309     -'
} > "$FIXTURES/netstat-ib-before.txt"
{
  printf '%s\n' "$NETSTAT_IB_HEADER"
  printf '%s\n' \
    'lo0        16384 <Link#1>                         36636     0  133091914    36636     0  133091914     0' \
    'en0*       1500  <Link#10>   1c:1d:d3:dd:60:f3        0     0          0        0     0          0     0' \
    'utun0      1280  <Link#40>                           12     0        900        3     0        240     0' \
    'utun6      1280  <Link#39>                       297543     0   27680991   774431     0  850539309     0'
} > "$FIXTURES/netstat-ib-after.txt"

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
export HOLY_KERNEL_ZONE_USERSAMPLE_IOREG_BIN="$FAKE_IOREG"
export HOLY_KERNEL_ZONE_USERSAMPLE_TOP_BIN="$FAKE_TOP"
export HOLY_KERNEL_ZONE_USERSAMPLE_LSOF_BIN="$FAKE_LSOF"
export HOLY_KERNEL_ZONE_USERSAMPLE_NETSTAT_BIN="$FAKE_NETSTAT"
export HOLY_KERNEL_ZONE_USERSAMPLE_ID_BIN="$FAKE_ID"

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
  phase=before
  [ "$sample_number" -lt 16 ] || { ps_file=$PS_AFTER; phase=after; }
  boot=1000000
  [ $((sample_number % 2)) -eq 0 ] || boot=1000001
  HOLY_KERNEL_ZONE_USERSAMPLE_LOG_DIR="$EPISODE_LOG" FAKE_NOW_EPOCH=$epoch FAKE_BOOT_EPOCH=$boot \
    FAKE_ZPRINT_INUSE=$inuse FAKE_PS_FILE=$ps_file FAKE_KOBJ_PHASE=$phase FAKE_NUM_FILES=$((11000 + sample_number)) \
    "$SAMPLER" sample > "$TEST_DIR/sample-$sample_number.tsv"
  sample_number=$((sample_number + 1))
done
# Boot 2: a fresh boot, quiet; its lower inuse must not read as an event.
for epoch in 2000600 2000900 2001200; do
  HOLY_KERNEL_ZONE_USERSAMPLE_LOG_DIR="$EPISODE_LOG" FAKE_NOW_EPOCH=$epoch FAKE_BOOT_EPOCH=2000000 \
    FAKE_ZPRINT_INUSE=600 FAKE_PS_FILE=$PS_AFTER FAKE_KOBJ_PHASE=after "$SAMPLER" sample >/dev/null
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

# Parsers, through the snapshot they feed. Sample 16 read the "after" fixtures.
TAB=$(printf '\t')
/usr/bin/gzip -dc "$EPISODE_LOG/snapshots/$sample_16_snapshot.kobjects.tsv.gz" > "$TEST_DIR/kobjects-16.tsv"
assert_contains "$(printf 'pid\tiokit_user_clients\tmach_ports\tsockets\topen_fds\tpty_fds')" "$TEST_DIR/kobjects-16.tsv"
# launchd: one user client, top ports, one kctl socket; lsof cannot see it (-).
assert_contains "$(printf '1\t1\t4432\t1\t-\t-')" "$TEST_DIR/kobjects-16.tsv"
# zsh: 5 user clients, ports with top's "+" suffix stripped, 4 unix sockets,
# 8 numeric descriptors (cwd and txt are not descriptors), 3 on /dev/ttys001.
assert_contains "$(printf '4000\t5\t1066\t4\t8\t3')" "$TEST_DIR/kobjects-16.tsv"
# tmux: rapportd's IPv6 socket and mDNSResponder's kevt socket (pid 3000 in the
# fixture); its /dev/ptmx counts as a pty descriptor, cwd and txt do not count.
assert_contains "$(printf '3000\t0\t50\t2\t2\t1')" "$TEST_DIR/kobjects-16.tsv"
# The comm with spaces parses: "Comet Helper:3300" is one tcp4 socket.
assert_contains "$(printf '3300\t2\t287\t1\t1\t0')" "$TEST_DIR/kobjects-16.tsv"
assert_contains "$(printf '5000\t1\t12\t1\t1\t1')" "$TEST_DIR/kobjects-16.tsv"
/usr/bin/gzip -dc "$EPISODE_LOG/snapshots/$sample_16_snapshot.interfaces.tsv.gz" > "$TEST_DIR/interfaces-16.tsv"
assert_contains "$(printf 'utun6\t297543\t0\t27680991\t774431\t0\t850539309')" "$TEST_DIR/interfaces-16.tsv"
assert_contains "$(printf 'en0\t0\t0\t0\t0\t0\t0')" "$TEST_DIR/interfaces-16.tsv"
[ "$(/usr/bin/grep -c "^lo0$TAB" "$TEST_DIR/interfaces-16.tsv")" = "1" ] || fail "an interface's address rows were counted as interfaces"
assert_contains "$(printf 'lsmp_mach_ports\tskipped')" "$EPISODE_LOG/collectors.tsv"
assert_contains "$(printf 'top_mach_ports\tok')" "$EPISODE_LOG/collectors.tsv"
assert_contains 'mach_ports=5903' "$EPISODE_LOG/collectors.tsv"
if [ "$(/usr/bin/id -u)" != 0 ]; then
  assert_contains "$(printf 'lsof_fds\tpartial')" "$EPISODE_LOG/collectors.tsv"
fi
[ "$(/usr/bin/awk -F '\t' 'NR > 1 { count += 1 } END { print count + 0 }' "$EPISODE_LOG/collectors.tsv")" = "$((38 * 6))" ] \
  || fail "collectors.tsv does not carry six collector rows for each of the 38 samples"

# Onset attribution: every metric that grew, ranked by growth per hour, with
# raw before and after; pid reuse and new processes grow from "new".
assert_contains "$(printf 'grew\tmach_ports\t12000\t66->1066\t4000\t/bin/zsh')" "$TEST_DIR/report.txt"
assert_contains "$(printf 'grew\tmach_ports\t144\tnew->12\t5000\t/usr/local/bin/leaky-helper')" "$TEST_DIR/report.txt"
assert_contains "$(printf 'grew\tmach_ports\t372\tnew->31\t3100\t/usr/bin/login')" "$TEST_DIR/report.txt"
assert_contains "$(printf 'grew\tiokit_user_clients\t48\t1->5\t4000\t/bin/zsh')" "$TEST_DIR/report.txt"
assert_contains "$(printf 'grew\tsockets\t36\t1->4\t4000\t/bin/zsh')" "$TEST_DIR/report.txt"
assert_contains "$(printf 'grew\topen_fds\t48\t4->8\t4000\t/bin/zsh')" "$TEST_DIR/report.txt"
assert_contains "$(printf 'grew\tpty_fds\t12\tnew->1\t5000\t/usr/local/bin/leaky-helper')" "$TEST_DIR/report.txt"
assert_not_contains "$(printf 'grew\tmach_ports\t0')" "$TEST_DIR/report.txt"
zsh_line=$(/usr/bin/grep -n "$(printf 'grew\tmach_ports\t12000')" "$TEST_DIR/report.txt" | /usr/bin/cut -d: -f1)
login_line=$(/usr/bin/grep -n "$(printf 'grew\tmach_ports\t372')" "$TEST_DIR/report.txt" | /usr/bin/cut -d: -f1)
helper_line=$(/usr/bin/grep -n "$(printf 'grew\tmach_ports\t144')" "$TEST_DIR/report.txt" | /usr/bin/cut -d: -f1)
[ "$zsh_line" -lt "$login_line" ] && [ "$login_line" -lt "$helper_line" ] \
  || fail "mach port growth is not ranked by growth per hour"
# utun6: 90,000 packets in 300 s = 1,080,000/h against a flat previous interval;
# lo0: 200 packets = 2,400/h; utun0 went backwards; en0 did not move.
assert_contains "$(printf 'interface\tutun6\t1080000\t0\t+1080000\t267543->297543\t714431->774431\t24680991->27680991\t790539309->850539309')" "$TEST_DIR/report.txt"
assert_contains "$(printf 'interface\tlo0\t2400\t0\t+2400')" "$TEST_DIR/report.txt"
assert_contains "$(printf 'interface\tutun0\tcounter_reset')" "$TEST_DIR/report.txt"
assert_not_contains "$(printf 'interface\ten0')" "$TEST_DIR/report.txt"
utun6_line=$(/usr/bin/grep -n "$(printf 'interface\tutun6')" "$TEST_DIR/report.txt" | /usr/bin/cut -d: -f1)
lo0_line=$(/usr/bin/grep -n "$(printf 'interface\tlo0')" "$TEST_DIR/report.txt" | /usr/bin/cut -d: -f1)
[ "$utun6_line" -lt "$lo0_line" ] || fail "interfaces are not ranked by packet-rate change"

# compare: the same attribution for any two samples, named by snapshot id.
sample_15_snapshot=$(/usr/bin/awk -F '\t' '{ print $14 }' "$TEST_DIR/sample-15.tsv")
HOLY_KERNEL_ZONE_USERSAMPLE_LOG_DIR="$EPISODE_LOG" "$SAMPLER" compare "$sample_15_snapshot" "$sample_16_snapshot" \
  > "$TEST_DIR/compare.txt"
assert_contains 'window_seconds=300 zone_rate_per_hour=2760000' "$TEST_DIR/compare.txt"
assert_contains "$(printf 'appeared\t5000\t4000\t03:10\t/usr/local/bin/leaky-helper\tparent=/bin/zsh')" "$TEST_DIR/compare.txt"
assert_contains "$(printf 'grew\tmach_ports\t12000\t66->1066\t4000\t/bin/zsh')" "$TEST_DIR/compare.txt"
assert_contains "$(printf 'interface\tutun6\t1080000')" "$TEST_DIR/compare.txt"
if HOLY_KERNEL_ZONE_USERSAMPLE_LOG_DIR="$EPISODE_LOG" "$SAMPLER" compare "$sample_16_snapshot" "$sample_15_snapshot" \
  > /dev/null 2>&1; then
  fail "compare accepted samples in reverse order"
fi

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
assert_contains "$(printf 'grew\tnone')" "$TEST_DIR/open-report.txt"
assert_contains "$(printf 'interface\tnone')" "$TEST_DIR/open-report.txt"
# Samples written before mn-e6f0f7 have no kernel-object snapshots.
/bin/rm -f "$OPEN_LOG/snapshots/"*.kobjects.tsv.gz "$OPEN_LOG/snapshots/"*.interfaces.tsv.gz
HOLY_KERNEL_ZONE_USERSAMPLE_LOG_DIR="$OPEN_LOG" "$SAMPLER" report > "$TEST_DIR/legacy-report.txt"
assert_contains 'kernel objects: unavailable' "$TEST_DIR/legacy-report.txt"
assert_contains 'interfaces: unavailable' "$TEST_DIR/legacy-report.txt"

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
[ ! -e "$ROTATE_LOG/snapshots/$first_snapshot.kobjects.tsv.gz" ] || fail "second rotation kept expired kernel objects"
[ ! -e "$ROTATE_LOG/snapshots/$first_snapshot.interfaces.tsv.gz" ] || fail "second rotation kept expired interface counters"
[ -s "$ROTATE_LOG/snapshots/$second_snapshot.kobjects.tsv.gz" ] || fail "second rotation pruned kept kernel objects"
[ "$(/usr/bin/awk -F '\t' 'NR == 2 { print $3 }' "$ROTATE_LOG/collectors.tsv.1")" = "$second_epoch" ] \
  || fail "collectors.tsv did not rotate with samples.tsv"
[ "$(/usr/bin/awk -F '\t' 'NR == 2 { print $3 }' "$ROTATE_LOG/collectors.tsv")" = "$third_epoch" ] \
  || fail "new collectors generation does not start at the rotating sample"
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

# A failed kernel-object collector never drops the zone rows: its column is "-",
# collectors.tsv and errors.log name it. As root, lsof sees every pid (ok).
COLLECTOR_FAILURE_LOG="$TEST_DIR/collector-failure-log"
HOLY_KERNEL_ZONE_USERSAMPLE_LOG_DIR="$COLLECTOR_FAILURE_LOG" FAKE_IOREG_FAIL=1 FAKE_EUID=0 FAKE_NOW_EPOCH=8000600 \
  FAKE_BOOT_EPOCH=8000000 FAKE_PS_FILE=$PS_BEFORE "$SAMPLER" sample > "$TEST_DIR/collector-failure-sample.tsv" \
  || fail "a failed ioreg collector failed the whole sample"
assert_contains 'data.kalloc.1024' "$TEST_DIR/collector-failure-sample.tsv"
assert_contains "$(printf 'ioreg_user_clients\tfailed\t')" "$COLLECTOR_FAILURE_LOG/collectors.tsv"
assert_contains 'fixture ioreg failure' "$COLLECTOR_FAILURE_LOG/collectors.tsv"
assert_contains "$(printf 'lsof_fds\tok\t')" "$COLLECTOR_FAILURE_LOG/collectors.tsv"
assert_contains 'collector ioreg_user_clients failed: fixture ioreg failure' "$COLLECTOR_FAILURE_LOG/errors.log"
failure_snapshot=$(/usr/bin/awk -F '\t' '{ print $14 }' "$TEST_DIR/collector-failure-sample.tsv")
/usr/bin/gzip -dc "$COLLECTOR_FAILURE_LOG/snapshots/$failure_snapshot.kobjects.tsv.gz" > "$TEST_DIR/collector-failure-kobjects.tsv"
assert_contains "$(printf '4000\t-\t66\t1\t4\t3')" "$TEST_DIR/collector-failure-kobjects.tsv"

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
