---
workflow: 2
manna: mn-579814
track: mn-eb7a80
source: samples.tsv; two panic files; mn-4308c4; mn-b09383
base_commit: 962f13ad23c8f022a2b5d44d29de8085c36339de
scope: '[P1][KERNEL] Zone-leak attribution: user-level 5-minute sampler with process census, and the Apple Feedback packet'
inputs:
- samples.tsv; two panic files; mn-4308c4; mn-b09383
binding: sha256:59b2ee54571f63e44660ab97d37fe9b5fbee258504737a204cdf4edfe7a2cb87
---

# Handoff: [P1][KERNEL] Zone-leak attribution: user-level 5-minute sampler with process census, and the Apple Feedback packet

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-579814
```

## Scope

[P1][KERNEL] Zone-leak attribution: user-level 5-minute sampler with process census, and the Apple Feedback packet

## Inputs

- samples.tsv; two panic files; mn-4308c4; mn-b09383

## Work order

Verdict so far from /Library/Logs/Holy Ghostty/kernel-zone-watch/samples.tsv (24 days, hourly, root daemon at /Library/PrivilegedHelperTools/org.holyghostty.kernel-zone-watch, StartInterval 3600): data.kalloc.1024 grows in constant-rate episodes that start at a moment and run until panic: 09-09 16:34 to 09-11 16:35 at 203k elements per hour then stops; 09-18 16:41 at 395k per hour until the 09-19 20:54 panic (panic-base-2026-09-19-205453.panic, SoC watchdog after panic save); 09-25 about 23:40 at 2,770k per hour until the 09-26 06:16 panic (panic-base+socd-2026-09-26-082459.000.panic, 21,229,168 elements, 20 GB, panicked task pid 24971 env inside AppleMobileFileIntegrity). Quiet boots grow at 1 to 3.4k per hour. The rate did not change when tmux_process_count halved from 82 to 39 mid-episode; ssh_process_count, sshd_process_count, and sshd_launchd_runs were 0 at every sample, so the SSH-churn feeder theory from mn-4308c4 is not what the data shows and the hourly counters cannot name the process. Fine sampling on 2026-09-26 11:43-11:48 with 36 tmux sessions: 1.9k per hour, flat. Deliver: (1) scripts/holy-kernel-zone-usersample.sh, a user-domain LaunchAgent installed by scripts/install-holy-kernel-zone-usersample.sh without sudo (zprint works unprivileged here), every 5 minutes into ~/Library/Logs/Holy Ghostty/kernel-zone-usersample/: data.kalloc.* inuse, sysctl kern.num_files, /dev/ttys count, highest pid, per-command process counts, and a compact process census (pid, ppid, etime, comm) so the sample before and after an onset can be diffed; a report subcommand that finds onsets (rate above a threshold derived from the measured quiet baseline, cite the samples) and prints the processes that appeared or changed at each onset; rotation; a shell test in scripts/test-holy-kernel-zone-usersample.sh in the style of the existing guard tests; (2) the Apple Feedback packet under .dev/apple-feedback/kalloc-1024/: both panic files copied, the per-boot table and episode curves as CSV and a short description (three episodes, constant rate, churn-independent, machine and OS), ready for Erik to file; (3) your final report states the verdict for mn-b09383 in one paragraph. Own only new files under scripts/ and .dev/apple-feedback/; do not modify holy-kernel-zone-watch.sh or install-holy-studio-guards.sh.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-579814`.
4. Commit with `Manna: mn-579814` and run `agent-do manna done mn-579814` only after the work is verified.

## Report

**Created (committed on this lane's branch):**
- `scripts/holy-kernel-zone-usersample.sh` has four subcommands:
  - `sample` records, every 300 s:
    - every data.kalloc.* inuse count (zprint -t, column 7, unprivileged)
    - kern.num_files, the /dev/ttys count, the highest pid, and the process count
    - a gzipped census (pid, ppid, etime, comm) and per-command counts
  - `report` finds onsets and diffs the census before and after each one.
  - `status` shows the launchd job's state, then the report.
  - `interval` prints the sampling interval, which the installer uses.
- `scripts/install-holy-kernel-zone-usersample.sh` installs the agent in the user domain (`gui/<uid>`), without sudo. It is idempotent: rerunning it replaced the job in place. It rolls back on failure. `--uninstall` removes the job, plist, and helper and keeps the logs.
- `scripts/test-holy-kernel-zone-usersample.sh` is a POSIX sh guard test in the house style. It covers:
  - the sample row format and a comm containing spaces
  - onset detection and localization, with no false onset on a loud 5-minute quiet burst
  - census diff: appeared, exited, pid reuse, reparented, and command-count changes
  - an episode ending, an episode still open, and an onset whose census is gone
  - boot-epoch jitter, rotation, same-second samples, and a failed probe
  - the installer: idempotency, rollback, and uninstall

  It passes. Mutation checks confirmed it catches a lowered threshold and a broken pid-reuse check. `scripts/test-holy-studio-guards.sh` still passes.

**Onset threshold:** 129,626 elements per hour, judged over a trailing hour. It is the midpoint between two measured groups in the root log:
- The loudest quiet hour: 75,269/h, over 468 quiet intervals (2026-09-18T14:40:51Z to 15:40:53Z).
- The slowest steady episode hour: 183,983/h, over 80 episode intervals (2026-09-11T13:35:43Z to 14:35:44Z).

Replaying the 24-day root log through `report` finds exactly three onsets, with no false positives across 564 samples and 5 boots.

**Installed:**
- LaunchAgent: `gui/501/org.holyghostty.kernel-zone-usersample`, StartInterval 300, RunAtLoad.
- Plist: `~/Library/LaunchAgents/org.holyghostty.kernel-zone-usersample.plist`.
- Log: `~/Library/Logs/Holy Ghostty/kernel-zone-usersample/samples.tsv`, with snapshots in `snapshots/`.
- `launchctl print` shows runs = 2 and last exit code = 0.
- First sample, written by launchd at load:

  `2026-09-26T17:13:23Z  data.kalloc.1024  inuse=9762  kern.num_files=11694  ttys=86  highest_pid=99338  processes=1003`
- First scheduled sample, 301 s later:

  `2026-09-26T17:18:24Z  inuse=11007  num_files=11460  ttys=85  processes=986`

**Packet:** `/Users/erik/Custom-Coding/holy-ghostty/.dev/apple-feedback/kalloc-1024/` (git-ignored), containing:
- `description.txt`
- `per-boot.csv`
- `episode-curves.csv`
- `kalloc-1024-hourly-series.csv`
- `panic-base-2026-09-19-205453.panic`
- `panic-base+socd-2026-09-26-082459.000.panic`

**Corrections to the work order's episode times.** The root log is UTC; the work order mixes UTC and CDT.
- Episode 1: the onset falls in 09-09 17:34 to 18:34Z. It held 202k/h until 09-11 16:35Z, then ran three hours at 331k to 455k/h, then stopped after 19:35:53Z.
- Episode 2: the onset falls in 09-18 16:40 to 17:40Z. The first four hours ran at 444k to 577k/h, then it held steady at 395k/h.
- Episode 3: the onset falls in 09-26 02:46 to 03:46Z, about 03:40Z (22:40 CDT) by extrapolation, not 23:40.

**Verdict for mn-b09383:** Outcome (c). The leak persists, it does not follow churn, and the packet is assembled; filing it is Erik's step.
- **The item's premise is wrong.** It says zero panics since 2026-09-01, but data.kalloc.1024 panicked the machine twice after that: 2026-09-19 (SoC watchdog, with the zone at 99.4% of the exhaustion count) and 2026-09-26 11:16:24Z ("zone map exhausted", 21,229,168 elements).
- **The rate is constant.** Each episode starts at one moment and holds a near-constant rate: 202k, 395k, and 2.76M elements per hour, varying 0.3% to 3.3% hour to hour. Extrapolating the last sample of episode 3 lands within 0.04% of the panic's own element count.
- **Churn doesn't move it.** ssh, sshd, and sshd launchd runs were 0 at all 564 hourly samples. The rate held while the tmux process count fell from 49 to 1 (episode 1) and from 82 to 39 (episode 3). Measured today: 5,000 exec/exit cycles, 200 `ps -ax` runs, and 200 `zprint` runs left the zone at net zero or below.
- **No process is named yet.** The per-user 5-minute sampler with its process census is now running. The next onset's `report` diff is what can name one, or show that no userland process changes at onset.
- **Out of scope:** the item's side task, recopying the 30-minute safety guard, was not in this work order and is not done.
