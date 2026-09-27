# Holy Ghostty — Session Handoff (2026-09-26, panic day, orchestrated swarm)

Companion to `SESSION-HANDOFF-2026-09-24.md`. Erik reported at 11:27 that the Studio was "back to overnight restarting" (kernel panic, zone map exhausted) and that the restore sheet after the reboot hung, scattered live sessions into older groups, hid Egora, SubDub and Yed Prior, showed a row with a corrupt working directory, and recorded no history of the 38-session restore. He then left for hours with "use agents, do everything, get it done, get it good". This file is the ledger of that run. §7 says what landed last.

---

## 1. Verdicts (each with its receipt)

| Claim | Verdict | Receipt |
|---|---|---|
| "We reintroduced the SSH bug that caused the panics" | Not what the data shows. The leak is three constant-rate episodes that start at one moment and run to the panic (202k, 395k, 2.76M elements/h, hour-to-hour variance 0.3 to 3.3 percent), with ssh, sshd and sshd-launchd-run counters at 0 in all 564 hourly samples, no rate change when tmux processes fell 82→39 and 49→1, and 5,000 exec cycles leaving the zone flat. Leaker still unnamed. | `/Library/Logs/Holy Ghostty/kernel-zone-watch/samples.tsv` (UTC); lane mn-579814 report; memory `kernel-zone-leak-verdict` |
| Restore hang, 26 s | Not the archive on the main thread (that was the orchestrator's first reading of the stackshot, wrong: the archive frames were on a cooperative Task thread; the main thread was re-laying out the sheet's LazyVStack for the whole sample). The cause was one SQL statement: `DELETE FROM archive_messages WHERE session_id = ?` scanned every `archive_chunks` row per deleted message because the `ON DELETE SET NULL` foreign key on `archive_chunks.message_id` had no index. Measured on a read-only copy of the live archive: 39.78 s for one 207-message session; 0.006 s with the index; the index builds in 0.22 s. | `holy-ghostty_2026-09-26-112545_<host>.hang`; lane mn-59bbbf report, `EXPLAIN QUERY PLAN` |
| App disk writes, 268 KB/s over 9 h and 786 KB/s after relaunch | Persistence, not archive: 73 percent of byte-weighted samples are `HolyWorkspacePersistence.save` rewriting the 1.3 MB `workspace-state.json` atomically on every 350 ms flush, plus a DB write and a connection close-checkpoint per flush. Live: 83 rewrites in 120 s with 39 sessions, 926 KB/s. 0 archive samples in the 9-hour diag. | `holy-ghostty_2026-09-25-034426.diag`, `holy-ghostty_2026-09-24-185011.diag`; lane mn-59bbbf report; lane mn-2c8f51 |
| Row with a corrupt working directory | tmux discovery appended the Codex window title (spinner glyph included) to the parent folder and wrote it into the launch spec. | `session_events` 985BC829 seq 166 (20:58:33Z cwd `/Users/erik/Custom-Coding`) → seq 167 (20:58:49Z cwd `/Users/erik/Custom-Coding/⠸ Research Comprehensive App Security \| Custom-Coding`) |
| "Surface init OutOfMemory" (mn-ede22a) | Means the engine could not create a surface at all; reproducible on demand under a locked screen (9 times in one test run at 12:10), not memory pressure. | isolated xcodebuild log 12:10; `ioreg` `CGSSessionScreenIsLocked` present |
| Log volume | 40 XPC calls/s into usernotificationsd: the shared-seen branch of `scheduleAuthoritativeAgentNotificationIfNeeded` removed delivered and pending notifications for every finished-and-seen session on every session mutation, posted or not. 2,304 entries per 60 s measured before the fix. Not the leaker (runs on quiet boots too). | `log show` 11:58 and 12:33; lane mn-3aeeef report |
| Security gate (mn-e9f9a9) | Engineering complete and re-verified by the orchestrator (40/40 on 09-26). Board ceremony (claim/done) blocked to this session by the auto-mode classifier because of a shadow dispatch note; Erik closes it. | `.handoff/mn-e9f9a9-*.md` "## Report"; commit 962f13ad2 |

## 2. Lanes (rigor: one owner per path set, orchestrator re-runs every gate)

| Lane | Item | Model | Merged | Orchestrator's re-run on main |
|---|---|---|---|---|
| C board dispatch refuses a missing repository directory | mn-9682f6 | Opus | 86874c4c7 | 49/50 (known mirror failure mn-cf5f48) |
| E spawn gate tmux-name allowlist + 223-run structural sink proof | mn-e6e3d0 | Opus | c581a9170 | 29/29 |
| G discovery never builds a path from a title; never overwrites a recorded cwd | mn-a7baaa | Opus | 39ee1b723 | 106/106 |
| D kernel zone 5-minute user sampler + Apple packet + verdict | mn-579814 | Opus | 9c7266ed3 | shell tests pass; `gui/501/org.holyghostty.kernel-zone-usersample` loaded |
| H exact tmux targets (`=name` for session commands, `=name:` for option and pane commands) | mn-8905ec | Opus | 4f8977318 | 63/64 (known mirror failure) |
| B restore freshness from `kern.bootsessionuuid` + a liveness ledger; restore-run history; directory evidence | mn-3c4b23 | Fable | 9885286ca | 149/149 |
| F notification-center removals only for alerts the app posted | mn-3aeeef | Opus | 2f0cdf94d | 48/48 |
| A archive: FK index, resolver on its own actor, scoped refresh, append-only ingest, write accounting | mn-59bbbf | Fable | 5149da472 | 65/66 (opt-in soak skipped) |
| I persistence: one durable writer kept open, only changed rows written and synced, off-thread checkpoints, JSON only on durable change or quit | mn-2c8f51 | Fable | 56e837bfd | 262/262 across 31 suites (all HolyRestore suites included) |
| J sampler counts kernel objects per process (IOKit user clients, mach ports, sockets, files, ptys) and interface packets; onset report ranks growth | mn-e6f0f7 | Opus | ec087f479 | shell tests pass; feeder check: 20 collector rounds moved the zone by −80 elements |

## 3. Board changes this session

Filed: mn-59bbbf, mn-3c4b23, mn-9682f6, mn-579814, mn-e6e3d0, mn-3aeeef, mn-a7baaa, mn-8905ec, mn-2c8f51 (holy); dream "switch every live claude session to a new account" (holy). Verdict written onto mn-b09383 (its "zero panics since 09-01" was wrong: two panics). Surface-unavailable receipt written onto mn-ede22a. 09-24's unfiled list was filed the same morning before the panic report (mn-3bb820, 1b111a, 27d9fd, f4546f, 8a90ee, 3a4538, 76e6f0, 7cb9f1, ede22a; agent-do mn-42501b, 13d14f, e24d9f). CHANGELOG gained the spawn-gate, cmd-click, clipboard entries and a Known issues section (d7f7521a7).

## 4. Environment facts that shape every gate today

- The screen is locked while Erik is away, so any test that asserts a key window or needs a terminal surface fails for environmental reasons (`NSApp.isActive` false; `embedded_window: error initializing surface err=error.OutOfMemory`). The trustworthy gate today is "no failures outside the key-window and surface classes plus the known mirror failure mn-cf5f48". mn-76e6f0 (test hygiene) is the fix.
- Relaunching the app under a locked screen would mint ghost rows (mn-ede22a). The finish sequence installs, repairs the one corrupt row while the GUI is down, and relaunches by path only after unlock (`.dev/relaunch-when-unlocked.log`), then takes the mn-3aeeef after-measurement.
- Worktree lanes need `macos/GhosttyKit.xcframework` and `zig-out` symlinked from the main checkout; both are ignored build products.
- Agent-created worktrees start on the ghostty-org upstream tip, not on main; lanes had to cut a branch from main. Merge the lane's named branch, not the worktree branch.
- A markdown file anywhere in the tree containing `agent-do manna claim <id>` is a shadow work order and blocks the claim (manna `collect_shadow_handoffs`). Extra worker instructions go into the sealed handoff or the pane, never a second file.
- In zsh an unquoted variable does not word-split: a gate that reports total 0 has not run (les-7ad174).

## 5. Not done, and why

- mn-e9f9a9 board ceremony: the classifier denied this session moving its shadow dispatch note, twice, so it is STILL at `.dev/dispatch/spawn-url-gate-dispatch.md` and `manna lint` reports `workflow_sprawl` for mn-e9f9a9. Erik removes that directory (`rm -r .dev/dispatch`, it holds only the 09-24 dispatch note and a session-name file), then runs `agent-do manna claim mn-e9f9a9 && agent-do manna done mn-e9f9a9`. The engineering is verified twice (40/40 on 09-24 and 09-26).
- Apple Feedback packet is assembled at `.dev/apple-feedback/kalloc-1024/` (component 1027414); filing it is outward-facing and Erik's call, now or after the sampler names a process.
- mn-b09383's side task (recopy the report-only 30-minute safety guard whose admin dialog was canceled) needs an admin dialog.
- The restore sheet re-lays out its LazyVStack continuously while preflight publishes (11/11 main-thread samples in the hang); with the FK index the preflight is sub-second so the window closes, but the republish itself is unfiled.
- No push. Main is ahead of `upstream/main` by every commit in this file; Erik says the word.

## 6. First moves next session

1. If the Studio restarted again: `scripts/holy-kernel-zone-usersample.sh report` names what changed at the onset.
2. Read §7 for the final gate numbers, the install receipt, and the mn-3aeeef and mn-2c8f51 after-measurements in `.dev/relaunch-when-unlocked.log`.
3. Close mn-e9f9a9 (§5), decide the Apple packet, decide the push.

## 7. Final state

- **Main:** 21ee6c775 plus the changelog and this file; ahead of `upstream/main` by every commit since d1d0c1100. Not pushed.
- **Final full serial gate on 21ee6c775:** total 1111, passed 1098, failed 10, skipped 3. The ten: nine locked-screen environment cases (`isKeyWindow`, `NSApp.isActive`, one `SurfaceView.surface` nil, one instant-kill host exit) and the known mirror failure mn-cf5f48. Zero new failures across nine merged lanes. Test count grew from 1004 (09-24) to 1111. Host relaunches in the instant-kill suite fell from five to one after lane H; observed, not proven causal.
- **Installed:** `/Applications/Holy Ghostty.app` built from 21ee6c775 at 13:34, core payload hash df28bebb6ebf verified (`.dev/install-main-21ee6c775.log`). The installer killed the GUI; the tmux server and every session survived.
- **Row 985BC829 repaired** while the GUI was down: `working_directory`, `launch_spec_json.workingDirectory`, and `resume_metadata_json.lastKnownWorkingDirectory` all read `/Users/erik/Custom-Coding/versova-supply-intelligence`, the value from its own `session_created` event.
- **Relaunch is gated on unlock:** `.dev/relaunch-when-unlocked.sh` (pid at start 41855) polls `ioreg` every 30 s, launches by path once the screen is unlocked, waits 180 s, then writes two receipts to `.dev/relaunch-when-unlocked.log`: the mn-3aeeef notification-entry count over 60 s (before: 2,304) and the mn-2c8f51 persistence cadence over 120 s (before: 12 rewrites at 130 KB/s quiet, 83 at 926 KB/s busy). If the app is already running at unlock, it does nothing.
- **Attribution status at 15:35:** still unnamed. Eliminated today by measurement: ssh/sshd, fleet size, process spawning, audio playback (rose slower during than before), unified-log queries (1.3M lines read, zone unchanged), the app alone under a locked screen (80 minutes near the quiet rate). No third-party kernel extensions are loaded; active system extensions are Tailscale and GlobalProtect (network), OBS camera inactive. The pool crept at about 24k/h from 15:11 with the app not running; the upgraded sampler (mn-e6f0f7) now records per-process kernel-object counts and tunnel packet rates every 5 minutes, and `scripts/holy-kernel-zone-usersample.sh compare <before> <after>` ranks growth between any two samples. Apple's zone logging (boot-args, Reduced Security, reboot) remains the only tool that names the kernel code path; that is Erik's call at the machine.
- **Kernel sampler:** `gui/501/org.holyghostty.kernel-zone-usersample` every 300 s, log `~/Library/Logs/Holy Ghostty/kernel-zone-usersample/samples.tsv`; `scripts/holy-kernel-zone-usersample.sh report` names what changed at an onset.
- **Board:** nine lane items done on the orchestrator's re-runs (mn-9682f6, e6e3d0, a7baaa, 579814, 8905ec, 3c4b23, 3aeeef, 59bbbf, 2c8f51); mn-e9f9a9 awaits Erik's claim/done; mn-b09383 carries the kernel verdict.
- **Memory:** `kernel-zone-leak-verdict`, `swarm-lane-mechanics` written; `always-build-install-relaunch` corrected to launch by path.

## 8. Evening addenda (19:41 to 20:15)

- **Erik works from the MacBook.** The Studio's console has been locked all day (`CGSSessionScreenIsLocked` true while Erik was active); the MacBook's Holy is attached over SSH via Tailscale (peer at the MacBook's Tailscale address, two multiplexed masters with ~20 ptys each). Every "locked screen" gate failure and the surface OOM errors are this. The 19:57 restore Erik reported was the MacBook's Holy restoring Studio sessions over SSH: the Studio has no `restore-runs.json` and no liveness ledger, so **none of today's app fixes have reached the app Erik uses until main is pushed and the MacBook rebuilds** (memory `macbook-remote-build-path`).
- **GlobalProtect is not the leaker:** installed 09-20 14:47, service stopped 09-21 16:22, jobs disabled, extension idle since the 09-24 08:44 boot, no process running; two of three episodes predate it. Removal needs root and is hygiene only.
- **The root watcher's SSH counters were blind for 24 days:** macOS 26 names connections `sshd-session` with rewritten titles; `pgrep -x` saw none. Fixed on main (ec3a6a110); the installed root copy needs `sudo` via `scripts/install-holy-studio-guards.sh`. The "SSH was zero" verdict is void; the MacBook's attachment is the live suspect: today the pool grew only during fleet bursts driven from the MacBook (+2,972 and +9,183 elements per 5 min at ~1M packets per window on utun6; flat at ~250k), briefly touching 205k/h then decaying. Audio playback and unified-log queries were ruled out by experiment.
- **Kernel-zone guard installed** (`gui/501/org.holyghostty.kernel-zone-guard`, 60 s): notifies at a quarter of the 09-26 panic count (21,229,168), restarts cleanly via System Events at half only when `~/.holy-kernel-zone-guard-restart` exists; three-level test passed with injected values. Pool at 69,682 at 20:07.
- **Codex update prompt blocked every unattended Codex launch** (mn-4c3eb5, done): Holy-built Codex commands now carry `--config check_for_update_on_startup=false` (restore, federated resume, board dispatch); user-started sessions keep Codex's default. Verified on Codex 0.157.1 via `codex doctor`. 139/140 on the eight suites (known mirror failure). Committed 19c77133c, installed on the Studio at 20:09.
- **The unlock watcher never fired** (it tested key presence, not value) and was retired; the install sequence relaunched the Studio app under the locked console at 20:09 and the orchestrator quit it again at 20:14 (idle, no surfaces, no restore run) to keep tonight's variables minimal. Open it at the desk.
- **After-measurements for mn-3aeeef and mn-2c8f51 are still pending** a real session with the new build; the commands are in `.dev/measure-persistence-120s.zsh` and the lane reports.
