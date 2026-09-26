---
workflow: 2
manna: mn-e6f0f7
track: mn-eb7a80
source: usersample 2026-09-26 20:04Z jump; lane mn-579814 report; today's audio and log-query experiments
base_commit: 35cdf9de61e364aebdbdcfa5abe8724d57c9e506
scope: '[P1][KERNEL] Sampler names the process: per-process kernel-object counts (IOKit user clients, mach ports, sockets, files, ptys) every 5 minutes'
inputs:
- usersample 2026-09-26 20:04Z jump; lane mn-579814 report; today's audio and log-query experiments
binding: sha256:57d2a6886e78dd342031176abb526e08911d58b4bdc8957df4328d7b84082140
---

# Handoff: [P1][KERNEL] Sampler names the process: per-process kernel-object counts (IOKit user clients, mach ports, sockets, files, ptys) every 5 minutes

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-e6f0f7
```

## Scope

[P1][KERNEL] Sampler names the process: per-process kernel-object counts (IOKit user clients, mach ports, sockets, files, ptys) every 5 minutes

## Inputs

- usersample 2026-09-26 20:04Z jump; lane mn-579814 report; today's audio and log-query experiments

## Work order

Why: data.kalloc.1024 is a kernel pool and nothing in userland attributes a kernel allocation to a process; the 5-minute sampler (mn-579814) records only a process list, so at an onset it can say which processes appeared, not which one is consuming. The leak's three episodes ran at 202k, 395k, and 2.76M elements per hour with no change in the process population, so the consumer is probably a process that was already running and started doing something at a fixed rate. Kernel objects held on behalf of a process are the userland-visible proxies: IOKit user clients (ioreg -c IOUserClient -l, the IOUserClientCreator property carries pid and name), mach ports (lsmp -a, per pid), sockets (netstat -anv carries pid on macOS 26, or lsof -nP -i), open files (lsof -nP per pid or proc_pidinfo), ptys (/dev/ttys owners via lsof), and per-interface packet counters (netstat -ib, for the utun tunnels of Tailscale and GlobalProtect). Measured today with the existing sampler across a 4,800-element jump at 20:04Z: the census diff named only contactsd helpers and Spotlight workers appearing, which is not attribution. Deliver: (1) scripts/holy-kernel-zone-usersample.sh sample records, per pid, user-client count, mach port count, socket count, open-file count, and pty count into the snapshot (gzipped, same rotation), plus per-interface packets and bytes; measure each collector's cost on this machine and cite it in the header (lsof over 1,000 processes may take seconds; sample only pids with etime over the interval or cap by measured cost, never a guessed cap); collectors that need root are skipped with a named reason; (2) report prints, for each onset, the processes whose counts grew fastest over the onset window and the interface whose packet rate changed, ranked by growth per hour, with the raw before and after numbers; (3) replay the 09-26 samples and show the output shape; (4) tests in scripts/test-holy-kernel-zone-usersample.sh for the new parsers using captured fixtures. Own the two sampler scripts and their test only; do not modify the root watcher or the studio guards; reinstall the user LaunchAgent with the existing installer once the test passes and confirm the next sample carries the new columns.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-e6f0f7`.
4. Commit with `Manna: mn-e6f0f7` and run `agent-do manna done mn-e6f0f7` only after the work is verified.

## Report

**Branch:** `lane/mn-e6f0f7`, cut from 8a78a385e. Commit 99f87ed8a changes only `scripts/holy-kernel-zone-usersample.sh` and `scripts/test-holy-kernel-zone-usersample.sh`. The installer did not need a change.

**Collectors.** Each was measured on this machine: macOS 26.6.1, uid 501, 940 to 954 processes, `/usr/bin/time -p`, three runs each. The numbers are cited in the script header.

| Kernel object | Collector | Interactive | First launchd sample | Root? |
|---|---|---|---|---|
| IOKit user clients | `ioreg -r -c IOUserClient -k IOUserClientCreator -d 1` | 0.03 to 0.04 s | 0.13 s | No. Covers every pid, root daemons included. |
| Mach ports | `top -l 1 -stats pid,ports` | 0.49 to 0.51 s | 2.30 s | No. Covers every pid. |
| Mach ports | `lsmp -a` | exits at once | not run | **Yes.** As uid 501 it exits 1 with `task_for_pid() failed`. It is skipped every sample with that reason recorded in collectors.tsv. |
| Sockets | `netstat -anv` | 0.03 to 0.04 s | 0.24 s | No. Reads the process:pid column of every socket section. |
| Open fds and pty fds | `lsof -nPw -F pfn` | 0.14 to 0.15 s | 0.45 s | Partly. Unprivileged, it lists only this uid's processes (613 to 627 of about 955 pids). Other pids are recorded as `-`, never 0. |
| Interface packets and bytes | `netstat -ib` | 0.02 to 0.32 s | 0.02 s | No. 39 interfaces, including utun0 to utun6. |

Other measurements:
- The unfiltered `ioreg -c IOUserClient -l` took 0.46 s and wrote 11 MB for the same creator count, so the sampler uses the filtered form.
- No collector is limited to a subset of pids:
  - None passes a few seconds.
  - Scoping top does not help: `top -l 1 -pid 1` took the same 0.50 s.
- A whole sample now takes 1.31 to 1.32 s interactively, up from 0.36 s.
- Disk use is 32.6 KB per sample, about 9.4 MB per day, and at most about 263 MB across the two rotated generations.

**New data per sample:**
- `snapshots/<id>.kobjects.tsv.gz` has the columns `pid, iokit_user_clients, mach_ports, sockets, open_fds, pty_fds`, one row per census pid.
  - ioreg and netstat list the whole system, so a pid they do not name is 0.
  - top and lsof name only what they can see, so a pid they omit is `-`.
  - A failed collector writes `-` for its whole column. The zone rows are still written.
- `snapshots/<id>.interfaces.tsv.gz` has `interface, ipkts, ierrs, ibytes, opkts, oerrs, obytes`, taken from each interface's `<Link#>` row.
- `collectors.tsv` gets one row per collector per sample: `schema_version, timestamp_utc, sample_epoch_seconds, snapshot_id, collector, status (ok|partial|skipped|failed), wall_seconds, pids_reported, detail (totals or error)`. It rotates with samples.tsv.
- The new snapshot files are pruned by the same rotation as the census files.
- samples.tsv is unchanged (schema 1).

**Report output.** At each onset, after the census diff, the report adds two sections:
- `grew<TAB>metric<TAB>growth_per_hour<TAB>before->after<TAB>pid<TAB>comm`
  - One line per grown metric per pid, for every pid that grew. There is no cap.
  - Lines are ranked by growth per hour within each metric.
  - A process that is new in the window, or a reused pid, shows `new` as its before value.
- `interface<TAB>name<TAB>packets_per_hour_window<TAB>previous_interval<TAB>change<TAB>ipkts a->b<TAB>opkts<TAB>ibytes<TAB>obytes`
  - Ranked by how much the packet rate changed from the previous same-boot interval.
  - An interface whose counters went backwards (it was recreated) is shown as `counter_reset`.

There is also a new subcommand, `compare <before_snapshot_id> <after_snapshot_id> [zone]`, which prints the same attribution for any two samples.

**Replay of the 09-26 samples:**
- `report` over 39 samples (17:13:23Z to 20:24:21Z) found `onsets=0`.
- `compare 1790452753-6356 1790453055-69781` covers the 20:04Z jump: +4,797 elements in 302 s, 57,183 per hour. It prints the census diff (contactsd +9, mdworker_shared -3, caffeinate +2) and then `kernel objects: unavailable` and `interfaces: unavailable`, because those samples came before this change.
- `compare 1790454443-82861 1790454749-34722` covers two live launchd samples and shows the full shape: 174 grew lines. The top lines per metric include:
  - `mach_ports 1141 980->1077 632 launchservicesd`
  - `sockets 482 2624->2665 1627 com.docker.backend`
  - `open_fds 141 21->33 19267 claude`
  - `interface en1 3363118 3684757 -321639 ...`
  - `interface utun6 3026965 3161152 -134187 ...`

**Tests:**
- `scripts/test-holy-kernel-zone-usersample.sh` passes. Its fixtures are lines captured from this machine's ioreg, top, lsof -F, netstat -anv, and netstat -ib output.
- It covers:
  - top's `+` suffix
  - a comm with spaces in netstat (`Comet Helper:3300`)
  - IPv6 addresses not being mistaken for a pid
  - cwd and txt entries not counting as descriptors
  - `/dev/ptmx` and ttys counted as pty descriptors
  - lsof-invisible pids recorded as `-`
  - interfaces that are down or have address rows
  - ranking, `new` for fresh and reused pids, and counter reset
  - `compare`, including reverse order being refused
  - a failed collector
  - root lsof status `ok`
  - legacy samples showing `unavailable`
  - rotation and pruning of collectors.tsv and the new snapshots
- `scripts/test-holy-studio-guards.sh` passes.
- Mutation checks: six of seven mutations were caught (top suffix, numeric-fd filter, `-` vs 0, ranking, fresh logic, trailing `*`). The one that survived removed the 5-hex state-column check, which is redundant with the 8-hex and 16-hex checks that remain.

**Reinstall receipt:**
- `scripts/install-holy-kernel-zone-usersample.sh` reinstalled `gui/501/org.holyghostty.kernel-zone-usersample` with StartInterval 300.
- The load sample landed at 2026-09-26T20:27:23Z (inuse=29147), 6 s after install.
- The first scheduled sample landed at **2026-09-26T20:32:29Z** (snapshot `1790454749-34722`, inuse=28990). It carries all the new data:
  - ioreg ok, 0.10 s, 892 user clients
  - top ok, 1.22 s, 126,088 ports over 951 pids
  - lsmp skipped
  - netstat sockets ok, 0.17 s, 3,758 sockets
  - lsof partial, 0.43 s, 627 of 953 pids
  - netstat -ib ok, 0.03 s, 39 interfaces
- `launchctl print` shows `runs = 2`, `last exit code = 0`.

**Risks:**
- lsof sees only uid 501, so fds and ptys held by root daemons are invisible. Sockets, ports, and user clients cover every pid.
- Under launchd, top ran 2.4x to 4.6x slower than interactively (1.22 to 2.30 s). collectors.tsv records this every sample, so drift will be visible.
- Mach port counts move a lot between samples (runningboardd and launchd change by ±30 in seconds). At an onset, read growth per hour against that background.
- A hung lsof or netstat, for example on a stale network mount, would stall the sample. launchd does not start overlapping runs, so the damage would be missed samples, not a pile-up.
- Nothing userland can see attributes a kalloc allocation directly. These counts are proxies. What would confirm attribution is a process whose count grows at the zone's rate at the next onset.
