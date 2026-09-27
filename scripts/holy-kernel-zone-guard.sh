#!/bin/sh
# Holy kernel-zone guard: warn, and optionally restart cleanly, before
# data.kalloc.1024 exhausts the zone map and panics the machine.
#
# Authority for every number:
#   EXHAUST_ELEMENTS 21229168 = the element count in the 2026-09-26 panic string
#     ("zone map exhausted ... 21229168 elements allocated", panic-base+socd-2026-09-26-082459).
#   NOTIFY at EXHAUST/4 and RESTART at EXHAUST/2: quiet boots never exceeded
#     0.62M elements in 24 days of the root watcher; the fastest measured episode
#     (2.76M/h) needs 3.8 h from the restart line to exhaustion, so a clean
#     restart at the halfway line leaves hours of margin and cannot fire on a quiet boot.
#   Interval 60 s (installer): the fastest episode adds 46k elements per minute,
#     0.2% of the exhaustion count, so one-minute sampling cannot miss the line.
# Restart is opt-in: it happens only when $RESTART_FLAG exists. Without it the
# guard only notifies and logs. A restart is requested through System Events
# (user domain, no root); it is a normal logout-and-restart, not a panic.
set -eu
EXHAUST_ELEMENTS=21229168
NOTIFY_ELEMENTS=$((EXHAUST_ELEMENTS / 4))
RESTART_ELEMENTS=$((EXHAUST_ELEMENTS / 2))
ZONE=${HOLY_KERNEL_ZONE_NAME:-data.kalloc.1024}
LOG_DIR=${HOLY_KERNEL_ZONE_GUARD_LOG_DIR:-"$HOME/Library/Logs/Holy Ghostty/kernel-zone-guard"}
LOG="$LOG_DIR/guard.log"
STATE="$LOG_DIR/state"
RESTART_FLAG=${HOLY_KERNEL_ZONE_GUARD_RESTART_FLAG:-"$HOME/.holy-kernel-zone-guard-restart"}
ZPRINT=${HOLY_KERNEL_ZONE_ZPRINT_BIN:-/usr/bin/zprint}
mkdir -p "$LOG_DIR"
now() { date '+%Y-%m-%dT%H:%M:%S%z'; }
# The desktop notification lands on the Studio's console; when Erik works from
# the MacBook that console is locked (2026-09-26), so the same text also goes
# through agent-do notify to the "me" alias (email + local pipe). NOTIFY_BIN is
# resolved from PATH first, then the checkout, because launchd's PATH lacks it.
NOTIFY_BIN=${HOLY_KERNEL_ZONE_GUARD_NOTIFY_BIN:-$(command -v agent-do 2>/dev/null || echo /Users/erik/Custom-Coding/agent-do/agent-do)}
NOTIFY_DRY=${HOLY_KERNEL_ZONE_GUARD_NOTIFY_DRY_RUN:-}
notify() {
  /usr/bin/osascript -e "display notification \"$2\" with title \"$1\" sound name \"Basso\"" >/dev/null 2>&1 || true
  if [ -x "$NOTIFY_BIN" ]; then
    if [ -n "$NOTIFY_DRY" ]; then
      "$NOTIFY_BIN" notify send me "$2" --subject "$1" --via email,pipe --all --dry-run >> "$LOG" 2>&1 || true
    else
      "$NOTIFY_BIN" notify send me "$2" --subject "$1" --via email,pipe --all >> "$LOG" 2>&1 || printf '%s\tNOTIFY send failed\n' "$(now)" >> "$LOG"
    fi
  else
    printf '%s\tNOTIFY agent-do not found at %s\n' "$(now)" "$NOTIFY_BIN" >> "$LOG"
  fi
}
boot=$(/usr/sbin/sysctl -n kern.boottime | sed -E 's/.*sec = ([0-9]+).*/\1/')
inuse=${HOLY_KERNEL_ZONE_GUARD_TEST_INUSE:-$("$ZPRINT" "$ZONE" 2>/dev/null | awk -v z="$ZONE" '$1==z {print $7}')}
[ -n "$inuse" ] || { printf '%s\tERROR\tzprint gave no inuse for %s\n' "$(now)" "$ZONE" >> "$LOG"; exit 1; }
level=ok
[ "$inuse" -ge "$NOTIFY_ELEMENTS" ] && level=notify
[ "$inuse" -ge "$RESTART_ELEMENTS" ] && level=restart
last=$(cat "$STATE" 2>/dev/null || echo "none 0")
last_level=${last%% *}; last_boot=${last##* }
[ "$last_boot" = "$boot" ] || last_level=none
printf '%s\t%s\t%s\tinuse=%s\tlevel=%s\n' "$(now)" "$boot" "$ZONE" "$inuse" "$level" >> "$LOG"
case "$level" in
  notify)
    if [ "$last_level" != notify ] && [ "$last_level" != restart ]; then
      notify "Holy kernel-zone guard" "$ZONE at $inuse elements, a quarter of the panic count. An episode is running; save work."
    fi ;;
  restart)
    if [ -e "$RESTART_FLAG" ]; then
      notify "Holy kernel-zone guard" "$ZONE at $inuse elements, half the panic count. Restarting cleanly now."
      printf '%s\tRESTART requested (flag %s present)\n' "$(now)" "$RESTART_FLAG" >> "$LOG"
      sleep 5
      /usr/bin/osascript -e 'tell application "System Events" to restart' >> "$LOG" 2>&1 || printf '%s\tRESTART request failed\n' "$(now)" >> "$LOG"
    elif [ "$last_level" != restart ]; then
      notify "Holy kernel-zone guard" "$ZONE at $inuse elements, half the panic count. Restart NOW (auto-restart is off)."
    fi ;;
esac
printf '%s %s\n' "$level" "$boot" > "$STATE"
