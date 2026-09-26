# agent-do handoffs

This directory is generated workflow state. `.manna/` owns status, tracks,
claims, and blockers. Each actionable Manna item owns exactly one Markdown
work order here, and the two are content-bound.

Rules:

- Create work through `agent-do manna create`; do not hand-build parallel
  prompt roots such as `.handoffs/`, `.dev/session-prompts/`, or
  `<campaign>/handoff-prompts/`.
- The Manna item `prompt` field points to a board-wide fixed-width name,
  `.handoff/<NN...>[b<MM...>]-mn-xxxxxx-<slug>.md`, after synchronization.
  Width is at least two digits and expands when the active plan exceeds 99.
- Frontmatter identifies the item, track, source, base commit, scope, inputs,
  and SHA-256 binding for the complete document.
- Edit a work order, then run `agent-do manna handoff seal mn-xxxxxx` before
  claiming it. A claim fails closed on any unsealed change.
- Board state stays in Manna. The handoff contains scope, authority,
  deliverables, and verification, never a second backlog.
- Priority lives in `.manna/handoff-order.yaml`. Run `agent-do manna sync`
  after board changes; never hand-maintain numbered filenames or this index.
- A bare numbered filename is safe to launch. `bMM...` means the item is held
  until that numbered priority closes. The full dependency truth remains
  `blocked_by`.
- Completed pairs return to unnumbered sealed history on sync, so no numbered
  filename advertises work that is already done.
- Commit `.manna/workflow.yaml`, `.manna/handoff-order.yaml`,
  `.manna/federation.yaml`, `.manna/issues.jsonl`, and `.handoff/`.

## Generated index

| Priority | Manna ID | Status | Full blocker list | Handoff |
| ---: | --- | --- | --- | --- |
| 01 | `mn-211310` | blocked | `mn-56f896` | `.handoff/01b02-mn-211310-roster-drag-to-reorder-sessions-in-left-menu.md` |
| 02 | `mn-56f896` | open | none | `.handoff/02-mn-56f896-p0-meta-preserve-notes-today-pins-titles-and-identity-across-lif.md` |
| 03 | `mn-ca1805` | open | none | `.handoff/03-mn-ca1805-p1-db-session-events-retention-unbounded-growth-409-of-443-mb-11.md` |
| 04 | `mn-569b91` | open | none | `.handoff/04-mn-569b91-verify-tmux-reconcile-known-sessions-and-safely-reap-true-orphan.md` |
| 05 | `mn-c3b48a` | open | none | `.handoff/05-mn-c3b48a-p0-pty-make-paste-and-injected-input-byte-exact.md` |
| 06 | `mn-e13961` | open | none | `.handoff/06-mn-e13961-p0-hooks-complete-the-open-harness-identity-lifecycle-and-model-p.md` |
| 07 | `mn-8179b6` | blocked | `mn-7e8e0d`, `mn-cf5fb6`, `mn-137c79`, `mn-596f61`, `mn-a0406e`, `mn-490160`, `mn-307da2` | `.handoff/07b38-mn-8179b6-accept-state-prove-six-state-indicators-and-reliable-notificatio.md` |
| 08 | `mn-679893` | open | none | `.handoff/08-mn-679893-accept-model-keep-the-displayed-model-truthful-after-model.md` |
| 09 | `mn-15ba3d` | blocked | `mn-56f896` | `.handoff/09b02-mn-15ba3d-p1-sync-define-stable-bidirectional-cross-host-metadata-semantic.md` |
| 10 | `mn-9eb075` | blocked | `mn-15ba3d` | `.handoff/10b09-mn-9eb075-p1-sync-add-opt-in-sync-session-config-to-menu-and-attach-all.md` |
| 11 | `mn-3cdfa0` | blocked | `mn-56f896` | `.handoff/11b02-mn-3cdfa0-p0-recovery-write-automatic-generational-recovery-manifests.md` |
| 12 | `mn-e59548` | open | none | `.handoff/12-mn-e59548-p1-holyctl-expose-versioned-read-only-sessions-list-and-observe.md` |
| 13 | `mn-c674c4` | blocked | `mn-e59548` | `.handoff/13b12-mn-c674c4-p1-watch-add-cross-session-watch-with-provenance.md` |
| 14 | `mn-e49b22` | open | none | `.handoff/14-mn-e49b22-p0-control-prove-a-pane-is-safe-for-autonomous-input.md` |
| 15 | `mn-573ec9` | blocked | `mn-c3b48a`, `mn-c674c4`, `mn-e49b22` | `.handoff/15b14-mn-573ec9-p2-control-add-brokered-leases-human-preemption-quotas-and-audit.md` |
| 16 | `mn-610814` | blocked | `mn-573ec9` | `.handoff/16b15-mn-610814-p2-control-add-byte-verified-messages-and-runtime-safe-control-a.md` |
| 17 | `mn-9febbc` | open | none | `.handoff/17-mn-9febbc-meta-manna-board-durability-git-tracked-as-of-5e6ab5fb3-verify-s.md` |
| 18 | `mn-137c79` | open | none | `.handoff/18-mn-137c79-p1-ux-state-prompt-to-enable-authoritative-agent-indicators-on-l.md` |
| 19 | `mn-510a47` | open | none | `.handoff/19-mn-510a47-p2-ux-sidebar-header-gear-menu-for-holy-feature-toggles.md` |
| 20 | `mn-a11942` | open | none | `.handoff/20-mn-a11942-p2-ux-mirror-workspace-commands-into-the-macos-menu-bar.md` |
| 21 | `mn-7e8e0d` | open | none | `.handoff/21-mn-7e8e0d-p1-state-verify-committed-finish-latency-vs-the-2-second-unread-c.md` |
| 22 | `mn-cf5fb6` | open | none | `.handoff/22-mn-cf5fb6-p0-state-restore-stalled-looping-agent-alerts-via-working-lease-e.md` |
| 23 | `mn-737aa0` | open | none | `.handoff/23-mn-737aa0-p2-state-restore-notification-click-ownership-guard-without-brea.md` |
| 24 | `mn-00761e` | open | none | `.handoff/24-mn-00761e-p3-cleanup-agent-state-review-cleanups-shared-posixquote-dead-si.md` |
| 25 | `mn-a320e4` | open | none | `.handoff/25-mn-a320e4-p3-ux-heat-gauge-session-usage-intensity-over-rolling-24h-window.md` |
| 26 | `mn-55a186` | open | none | `.handoff/26-mn-55a186-p2-ux-hooks-remote-bridge-installer-should-recognize-a-host-s-ow.md` |
| 27 | `mn-a0406e` | open | none | `.handoff/27-mn-a0406e-p0-state-launch-time-focus-churn-marks-every-session-seen-used-a.md` |
| 28 | `mn-26259c` | blocked | `mn-c85876` | `.handoff/28b39-mn-26259c-p1-secondchair-c1-on-demand-focused-session-chat-panel-lifetime-c.md` |
| 29 | `mn-5016e9` | blocked | `mn-26259c` | `.handoff/29b28-mn-5016e9-p1-secondchair-c2-proposal-review-control-byte-safe-insertdraft-h.md` |
| 30 | `mn-c38172` | blocked | `mn-56f896`, `mn-26259c` | `.handoff/30b28-mn-c38172-p2-secondchair-c3-roster-aware-pull-q-a-ask-about-other-sessions.md` |
| 31 | `mn-70a8ac` | blocked | `mn-26259c`, `mn-e49b22`, `mn-610814` | `.handoff/31b28-mn-70a8ac-parked-secondchair-old-j4-autonomous-hands-superseded-by-human-e.md` |
| 32 | `mn-a40d06` | blocked | `mn-c38172` | `.handoff/32b30-mn-a40d06-p3-secondchair-optional-c4-ptt-tts-via-hardened-agent-do-voice-s.md` |
| 33 | `mn-fca1e5` | open | none | `.handoff/33-mn-fca1e5-p2-overseer-red-team-mitigations-attribution-redaction-alias-reg.md` |
| 34 | `mn-596e37` | blocked | `mn-5016e9`, `mn-c38172` | `.handoff/34b30-mn-596e37-parked-trust-program-human-directed-relay-machine-enter-separate.md` |
| 35 | `mn-d70c83` | open | none | `.handoff/35-mn-d70c83-p2-verify-selection-define-wheel-selection-semantics-under-tmux-m.md` |
| 36 | `mn-d35a9f` | open | none | `.handoff/36-mn-d35a9f-p2-core-port-and-benchmark-ghostty-renderer-state-fairness.md` |
| 37 | `mn-307da2` | open | none | `.handoff/37-mn-307da2-p1-notify-coalesce-notification-removal-and-make-cleanup-idempot.md` |
| 38 | `mn-490160` | open | none | `.handoff/38-mn-490160-p1-perf-state-decouple-animated-terminal-titles-from-session-ref.md` |
| 39 | `mn-c85876` | open | none | `.handoff/39-mn-c85876-p1-secondchair-c0-chair-protocol-fake-provider-vertical-slice.md` |
| 40 | `mn-2b3a11` | open | none | `.handoff/40-mn-2b3a11-p1-sync-always-on-cross-host-note-pin-sync-via-tmux-user-options.md` |
| 41 | `mn-c3a823` | open | none | `.handoff/41-mn-c3a823-p1-sync-remote-ward-sync-never-ran-automatically-dead-periodic-p.md` |
| 42 | `mn-f0b1cc` | open | none | `.handoff/42-mn-f0b1cc-p2-state-codex-surface-codex-hooks-not-approved-as-a-visible-deg.md` |
| 43 | `mn-54c1ae` | open | none | `.handoff/43-mn-54c1ae-pre-existing-test-failure-holyremoteagentstatebridgeservicetests.md` |
| 44 | `mn-0532e8` | open | none | `.handoff/44-mn-0532e8-load-flake-holyremotetmuxdiscoverytimeouttests-exitedparentwithi.md` |
| 45 | `mn-6f00cd` | blocked | `mn-3cdfa0` | `.handoff/45b11-mn-6f00cd-p2-recovery-recovery-backups-ui-sessions-recovery-backups-create.md` |
| 46 | `mn-f4d942` | open | none | `.handoff/46-mn-f4d942-p3-ux-inbox-collapsed-right-edge-rail-when-the-inbox-panel-is-cl.md` |
| 47 | `mn-61655a` | open | none | `.handoff/47-mn-61655a-p1-restore-ambiguous-picker-allow-restoring-both-matching-conver.md` |
| 48 | `mn-071d16` | open | none | `.handoff/48-mn-071d16-p2-notify-agent-state-notification-pipeline-re-removes-acknowled.md` |
| 49 | `mn-b864b4` | open | none | `.handoff/49-mn-b864b4-post-incident-gaps-clear-readopt-wipes-attention-metadata-no-re-k.md` |
| 50 | `mn-7a8cae` | open | none | `.handoff/50-mn-7a8cae-attention-one-record-roster-and-board-read-coord-holy-writes-its.md` |
| 51 | `mn-ac80c9` | open | none | `.handoff/51-mn-ac80c9-board-hygiene-reconcile-the-46-drift-findings-and-retire-superse.md` |
| 52 | `mn-456903` | open | none | `.handoff/52-mn-456903-p2-agent-state-installer-reports-blocked-on-erik-s-machine-so-la.md` |
| 53 | `mn-7681f4` | open | none | `.handoff/53-mn-7681f4-p1-security-restore-provider-supplied-resume-command-strings-run.md` |
| 54 | `mn-12801a` | open | none | `.handoff/54-mn-12801a-p1-roster-sync-sync-adopts-never-seen-holy-sessions-from-every-h.md` |
| 55 | `mn-b09383` | open | none | `.handoff/55-mn-b09383-p1-kernel-zone-watch-verdict-correlate-the-week-name-the-leaker-o.md` |
| 56 | `mn-cf5f48` | open | none | `.handoff/56-mn-cf5f48-p1-tmux-state-host-state-mirror-fails-during-detached-create-on-a.md` |
| 57 | `mn-137814` | open | none | `.handoff/57-mn-137814-p1-terminal-links-localhost-urls-in-remote-panes-cmd-click-open-o.md` |
| 58 | `mn-e9f9a9` | open | none | `.handoff/58-mn-e9f9a9-p0-security-automation-holy-ghostty-spawn-executes-attacker-supp.md` |
| 59 | `mn-3bb820` | open | none | `.handoff/59-mn-3bb820-p0-release-1-0-ceremony-gate-certified-serial-green-run-on-the-r.md` |
| 60 | `mn-3a4538` | open | none | `.handoff/60-mn-3a4538-p2-tests-ghosttyuitests-target-crashes-at-bootstrap-every-serial.md` |
| 61 | `mn-1b111a` | open | none | `.handoff/61-mn-1b111a-p1-tests-holyrosterinstantkilltests-kills-the-test-host-five-rel.md` |
| 62 | `mn-76e6f0` | open | none | `.handoff/62-mn-76e6f0-p2-tests-key-window-expectations-fail-in-a-non-frontmost-test-ho.md` |
| 63 | `mn-27d9fd` | open | none | `.handoff/63-mn-27d9fd-p1-sync-local-tmux-discovery-times-out-at-fleet-size-the-5-s-lit.md` |
| 64 | `mn-8a90ee` | open | none | `.handoff/64-mn-8a90ee-p1-roster-done-done-indicator-a-distinct-mark-when-the-agent-has.md` |
| 65 | `mn-7cb9f1` | blocked | `mn-a0406e` | `.handoff/65b27-mn-7cb9f1-p2-roster-green-dot-semantics-born-seen-attention-earned-only-by.md` |
| 66 | `mn-f4546f` | open | none | `.handoff/66-mn-f4546f-p1-installer-launch-the-installed-app-by-path-never-by-name.md` |
| 67 | `mn-ede22a` | open | none | `.handoff/67-mn-ede22a-p1-automation-roster-spawn-route-records-a-session-whose-surface.md` |
