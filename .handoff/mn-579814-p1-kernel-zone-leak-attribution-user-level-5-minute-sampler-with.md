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
