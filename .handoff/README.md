# agent-do handoffs

This directory is generated workflow state. `.manna/` owns status, tracks,
claims, and blockers. Each actionable Manna item owns exactly one Markdown
work order here, and the two are content-bound.

Rules:

- Create work through `agent-do manna create`; do not hand-build parallel
  prompt roots such as `.handoffs/`, `.dev/session-prompts/`, or
  `<campaign>/handoff-prompts/`.
- The Manna item `prompt` field points to
  `.handoff/<NN>[b<MM>]-mn-xxxxxx-<slug>.md` after synchronization.
- Frontmatter identifies the item, track, source, base commit, scope, inputs,
  and SHA-256 binding for the complete document.
- Edit a work order, then run `agent-do manna handoff seal mn-xxxxxx` before
  claiming it. A claim fails closed on any unsealed change.
- Board state stays in Manna. The handoff contains scope, authority,
  deliverables, and verification, never a second backlog.
- Priority lives in `.manna/handoff-order.yaml`. Run `agent-do manna sync`
  after board changes; never hand-maintain numbered filenames or this index.
- A bare numbered filename is safe to launch. `bMM` means the item is held
  until priority `MM` closes. The full dependency truth remains `blocked_by`.
- Completed pairs return to unnumbered sealed history on sync, so no numbered
  filename advertises work that is already done.
- Commit `.manna/workflow.yaml`, `.manna/handoff-order.yaml`,
  `.manna/issues.jsonl`, and `.handoff/`.

## Generated index

| Priority | Manna ID | Status | Full blocker list | Handoff |
| ---: | --- | --- | --- | --- |
| 01 | `mn-211310` | blocked | `mn-56f896` | `.handoff/01b02-mn-211310-roster-drag-to-reorder-sessions-in-left-menu.md` |
| 02 | `mn-56f896` | open | none | `.handoff/02-mn-56f896-p0-meta-preserve-notes-today-pins-titles-and-identity-across-lif.md` |
| 03 | `mn-ca1805` | open | none | `.handoff/03-mn-ca1805-p1-db-session-events-retention-unbounded-growth-409-of-443-mb-11.md` |
| 04 | `mn-569b91` | blocked | `mn-495322` | `.handoff/04-mn-569b91-verify-tmux-reconcile-known-sessions-and-safely-reap-true-orphan.md` |
| 05 | `mn-c3b48a` | open | none | `.handoff/05-mn-c3b48a-p0-pty-make-paste-and-injected-input-byte-exact.md` |
| 06 | `mn-e13961` | open | none | `.handoff/06-mn-e13961-p0-hooks-complete-the-open-harness-identity-lifecycle-and-model-p.md` |
| 07 | `mn-8179b6` | blocked | `mn-e13961`, `mn-7e8e0d`, `mn-cf5fb6`, `mn-137c79`, `mn-596f61`, `mn-a0406e`, `mn-490160`, `mn-307da2` | `.handoff/07b39-mn-8179b6-accept-state-prove-six-state-indicators-and-reliable-notificatio.md` |
| 08 | `mn-679893` | blocked | `mn-e13961` | `.handoff/08b06-mn-679893-accept-model-keep-the-displayed-model-truthful-after-model.md` |
| 09 | `mn-15ba3d` | blocked | `mn-56f896` | `.handoff/09b02-mn-15ba3d-p1-sync-define-stable-bidirectional-cross-host-metadata-semantic.md` |
| 10 | `mn-9eb075` | blocked | `mn-15ba3d` | `.handoff/10b09-mn-9eb075-p1-sync-add-opt-in-sync-session-config-to-menu-and-attach-all.md` |
| 11 | `mn-3cdfa0` | blocked | `mn-56f896`, `mn-e13961` | `.handoff/11b06-mn-3cdfa0-p0-recovery-write-automatic-generational-recovery-manifests.md` |
| 12 | `mn-9a6145` | open | none | `.handoff/12-mn-9a6145-p0-recovery-add-restore-all-restore-selected-and-recovery-backup.md` |
| 13 | `mn-e59548` | blocked | `mn-e13961` | `.handoff/13b06-mn-e59548-p1-holyctl-expose-versioned-read-only-sessions-list-and-observe.md` |
| 14 | `mn-c674c4` | blocked | `mn-e59548` | `.handoff/14b13-mn-c674c4-p1-watch-add-cross-session-watch-with-provenance.md` |
| 15 | `mn-e49b22` | blocked | `mn-e13961` | `.handoff/15b06-mn-e49b22-p0-control-prove-a-pane-is-safe-for-autonomous-input.md` |
| 16 | `mn-573ec9` | blocked | `mn-c3b48a`, `mn-c674c4`, `mn-e49b22` | `.handoff/16b15-mn-573ec9-p2-control-add-brokered-leases-human-preemption-quotas-and-audit.md` |
| 17 | `mn-610814` | blocked | `mn-573ec9` | `.handoff/17b16-mn-610814-p2-control-add-byte-verified-messages-and-runtime-safe-control-a.md` |
| 18 | `mn-9febbc` | open | none | `.handoff/18-mn-9febbc-meta-manna-board-durability-git-tracked-as-of-5e6ab5fb3-verify-s.md` |
| 19 | `mn-137c79` | open | none | `.handoff/19-mn-137c79-p1-ux-state-prompt-to-enable-authoritative-agent-indicators-on-l.md` |
| 20 | `mn-510a47` | open | none | `.handoff/20-mn-510a47-p2-ux-sidebar-header-gear-menu-for-holy-feature-toggles.md` |
| 21 | `mn-a11942` | open | none | `.handoff/21-mn-a11942-p2-ux-mirror-workspace-commands-into-the-macos-menu-bar.md` |
| 22 | `mn-7e8e0d` | open | none | `.handoff/22-mn-7e8e0d-p1-state-verify-committed-finish-latency-vs-the-2-second-unread-c.md` |
| 23 | `mn-cf5fb6` | open | none | `.handoff/23-mn-cf5fb6-p0-state-restore-stalled-looping-agent-alerts-via-working-lease-e.md` |
| 24 | `mn-737aa0` | open | none | `.handoff/24-mn-737aa0-p2-state-restore-notification-click-ownership-guard-without-brea.md` |
| 25 | `mn-00761e` | open | none | `.handoff/25-mn-00761e-p3-cleanup-agent-state-review-cleanups-shared-posixquote-dead-si.md` |
| 26 | `mn-a320e4` | open | none | `.handoff/26-mn-a320e4-p3-ux-heat-gauge-session-usage-intensity-over-rolling-24h-window.md` |
| 27 | `mn-55a186` | open | none | `.handoff/27-mn-55a186-p2-ux-hooks-remote-bridge-installer-should-recognize-a-host-s-ow.md` |
| 28 | `mn-a0406e` | open | none | `.handoff/28-mn-a0406e-p0-state-launch-time-focus-churn-marks-every-session-seen-used-a.md` |
| 29 | `mn-26259c` | blocked | `mn-c85876` | `.handoff/29b40-mn-26259c-p1-secondchair-c1-on-demand-focused-session-chat-panel-lifetime-c.md` |
| 30 | `mn-5016e9` | blocked | `mn-26259c` | `.handoff/30b29-mn-5016e9-p1-secondchair-c2-proposal-review-control-byte-safe-insertdraft-h.md` |
| 31 | `mn-c38172` | blocked | `mn-56f896`, `mn-26259c` | `.handoff/31b29-mn-c38172-p2-secondchair-c3-roster-aware-pull-q-a-ask-about-other-sessions.md` |
| 32 | `mn-70a8ac` | blocked | `mn-26259c`, `mn-e49b22`, `mn-610814` | `.handoff/32b29-mn-70a8ac-parked-secondchair-old-j4-autonomous-hands-superseded-by-human-e.md` |
| 33 | `mn-a40d06` | blocked | `mn-c38172` | `.handoff/33b31-mn-a40d06-p3-secondchair-optional-c4-ptt-tts-via-hardened-agent-do-voice-s.md` |
| 34 | `mn-fca1e5` | open | none | `.handoff/34-mn-fca1e5-p2-overseer-red-team-mitigations-attribution-redaction-alias-reg.md` |
| 35 | `mn-596e37` | blocked | `mn-5016e9`, `mn-c38172` | `.handoff/35b31-mn-596e37-parked-trust-program-human-directed-relay-machine-enter-separate.md` |
| 36 | `mn-d70c83` | open | none | `.handoff/36-mn-d70c83-p2-verify-selection-define-wheel-selection-semantics-under-tmux-m.md` |
| 37 | `mn-d35a9f` | open | none | `.handoff/37-mn-d35a9f-p2-core-port-and-benchmark-ghostty-renderer-state-fairness.md` |
| 38 | `mn-307da2` | open | none | `.handoff/38-mn-307da2-p1-notify-coalesce-notification-removal-and-make-cleanup-idempot.md` |
| 39 | `mn-490160` | open | none | `.handoff/39-mn-490160-p1-perf-state-decouple-animated-terminal-titles-from-session-ref.md` |
| 40 | `mn-c85876` | open | none | `.handoff/40-mn-c85876-p1-secondchair-c0-chair-protocol-fake-provider-vertical-slice.md` |
| 41 | `mn-8749ca` | open | none | `.handoff/41-mn-8749ca-p1-perf-scroll-not-butter-smooth-on-macbook-class-hardware-local.md` |
| 42 | `mn-2b3a11` | open | none | `.handoff/42-mn-2b3a11-p1-sync-always-on-cross-host-note-pin-sync-via-tmux-user-options.md` |
| 43 | `mn-c3a823` | open | none | `.handoff/43-mn-c3a823-p1-sync-remote-ward-sync-never-ran-automatically-dead-periodic-p.md` |
| 44 | `mn-fe1b48` | open | none | `.handoff/44-mn-fe1b48-sessions-panel-right-hand-utility-surface-hosting-agent-sessions.md` |
| 45 | `mn-a98f88` | blocked | `mn-fe1b48` | `.handoff/45b44-mn-a98f88-handoff-wiring-end-to-end-resume-verification.md` |
| 46 | `mn-f0b1cc` | open | none | `.handoff/46-mn-f0b1cc-p2-state-codex-surface-codex-hooks-not-approved-as-a-visible-deg.md` |
| 47 | `mn-f2a0b1` | open | none | `.handoff/47-mn-f2a0b1-p2-state-background-work-orbit-one-census-for-agents-workflows-a.md` |
| 48 | `mn-54c1ae` | open | none | `.handoff/48-mn-54c1ae-pre-existing-test-failure-holyremoteagentstatebridgeservicetests.md` |
| 49 | `mn-4db5d4` | open | none | `.handoff/49-mn-4db5d4-inbox-right-hand-inbox-panel-shell-ready-host-toggle-badge-becom.md` |
| 50 | `mn-31aaf2` | open | none | `.handoff/50-mn-31aaf2-post-merge-cleanup-unify-holymannaprocessrunner-into-the-shared-r.md` |
| 51 | `mn-0532e8` | open | none | `.handoff/51-mn-0532e8-load-flake-holyremotetmuxdiscoverytimeouttests-exitedparentwithi.md` |
| 52 | `mn-6f00cd` | blocked | `mn-3cdfa0` | `.handoff/52b11-mn-6f00cd-p2-recovery-recovery-backups-ui-sessions-recovery-backups-create.md` |
| 53 | `mn-f4d942` | open | none | `.handoff/53-mn-f4d942-p3-ux-inbox-collapsed-right-edge-rail-when-the-inbox-panel-is-cl.md` |
| 54 | `mn-943f71` | open | none | `.handoff/54-mn-943f71-inbox-visual-pass-fixes-retire-collision-alerts-github-first-man.md` |
| 55 | `mn-b2e2e9` | open | none | `.handoff/55-mn-b2e2e9-inbox-focus-instant-manna-per-source-refresh-root-cause-the-unav.md` |
| 56 | `mn-5dc58b` | open | none | `.handoff/56-mn-5dc58b-inbox-brief-intelligent-panel-two-drawers-answer-line-ranked-thr.md` |
| 57 | `mn-81331d` | open | none | `.handoff/57-mn-81331d-p1-state-working-throbber-missing-on-the-focused-holy-session-wh.md` |
| 58 | `mn-7afa94` | open | none | `.handoff/58-mn-7afa94-p1-ux-keys-p-dead-panel-toggle-keystroke-has-never-worked-despit.md` |
| 59 | `mn-7fbb07` | open | none | `.handoff/59-mn-7fbb07-inbox-brief-remote-estates-the-brief-executes-where-the-session-l.md` |
| 60 | `mn-0368e0` | open | none | `.handoff/60-mn-0368e0-p0-app-clear-detach-all-terminates-the-app-within-80ms-flight-re.md` |
| 61 | `mn-61655a` | open | none | `.handoff/61-mn-61655a-p1-restore-ambiguous-picker-allow-restoring-both-matching-conver.md` |
| 62 | `mn-071d16` | open | none | `.handoff/62-mn-071d16-p2-notify-agent-state-notification-pipeline-re-removes-acknowled.md` |
| 63 | `mn-938022` | open | none | `.handoff/63-mn-938022-p0-restore-restored-sessions-carry-wrong-names-and-wrong-notes-i.md` |
| 64 | `mn-13a213` | open | none | `.handoff/64-mn-13a213-p0-recovery-real-crash-2026-08-14-live-but-younger-server-re-ope.md` |
| 65 | `mn-eb6b3e` | open | none | `.handoff/65-mn-eb6b3e-pre-existing-test-failure-holybrieftriagetests-needsmethreadslea.md` |
