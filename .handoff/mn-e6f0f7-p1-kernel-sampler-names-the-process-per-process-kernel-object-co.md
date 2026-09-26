---
workflow: 2
manna: mn-e6f0f7
track: mn-eb7a80
source: usersample 2026-09-26 20:04Z jump; lane mn-579814 report; today's audio and log-query experiments
base_commit: 35cdf9de61e364aebdbdcfa5abe8724d57c9e506
scope: '[P1][KERNEL] Sampler names the process: per-process kernel-object counts (IOKit user clients, mach ports, sockets, files, ptys) every 5 minutes'
inputs:
- usersample 2026-09-26 20:04Z jump; lane mn-579814 report; today's audio and log-query experiments
binding: sha256:f5bdf37ee7d264019a741247dce8076308ef93100929e8eb62a597abae82846f
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
