---
workflow: 2
manna: mn-235e6d
track: mn-eb7a80
source: Closing doctrine ruling 2026-09-09; supersedes the acceptance gates formerly embedded in the closed items
base_commit: 2786bfa1695fd80320aea2999e2bc59ea864ffdf
scope: 'Field-check sitting: one pass over the shipped features, owner Erik'
inputs:
- Closing doctrine ruling 2026-09-09; supersedes the acceptance gates formerly embedded in the closed items
binding: sha256:3eac98439d973c29d2d1bf033b94f7f81fd310d81de5cf530294a1044b69b937
---

# Handoff: Field-check sitting: one pass over the shipped features, owner Erik

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-235e6d
```

## Scope

Field-check sitting: one pass over the shipped features, owner Erik

## Inputs

- Closing doctrine ruling 2026-09-09; supersedes the acceptance gates formerly embedded in the closed items

## Work order

The acceptance work formerly held hostage inside eleven build items, now one twenty-minute sitting (per the 2026-09-09 closing doctrine, dec-4db3fe — a failed check never reopens the old item; file a new one citing it). The pass: (1) ledger feel — drag board+archive column grips and both inspector dividers, resize the window narrow and back (mn-f044d0/mn-ac0b36); (2) Clear then Sync — window stays open, roster reconverges (mn-3a03e3); (3) glance the once-stuck codex rows — no eternal spinner, honest states (mn-d204ae); (4) ask the board a question with Enter, click a citation (mn-57866a); (5) one-click Claim & build on any READY item — worker boots to a real prompt, session note carries the mn id (mn-ec34cd + dispatch repair 2786bfa16); (6) rule on the pre-warm day — any 'writing…' sightings since Sep 4? none = verdict clean (mn-252f7a's field half); (7) next natural reboot — codex sessions restore, dots survive (mn-9a9728/mn-18be22 field half); (8) when on the MacBook — archive shows Studio sessions, one cross-host search, one remote restore (mn-b61389 field half); (9) cross-machine dots — seen on Studio shows seen on MacBook (mn-2c82a2 field half). Each finding that fails becomes a NEW item citing the old id.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-235e6d`.
4. Commit with `Manna: mn-235e6d` and run `agent-do manna done mn-235e6d` only after the work is verified.

## Continuation: field acceptance preparation, 2026-09-11 UTC

The work order assigns field observation to Erik. It specifies no new product
implementation. This continuation prepares that sitting; the item remains
`in_progress`. Field results recorded in this lane: **0 of 9**. No pass or
failure has been inferred from a closed build item, a compilation, or silence
from the owner.

### Entry verification

- First command: `agent-do manna claim mn-235e6d`, exit 0. Canonical owner:
  `codex-01a08e7bbd7e72c2`; claimed at `2026-09-11T03:21:22.843120Z`.
- `agent-do manna state --json`, filtered to this item, confirms the owner,
  `in_progress` status, prompt path, track, and supplied binding.
- Before editing, the complete document's calculated Manna binding, its
  frontmatter, the canonical row, and the user's expected binding all matched
  `sha256:21b498f8ca492e8bf0ebcd58ff6834aafc69bd7182a50ebbb12ea8930c078dc7`.
  The check used Manna's normalization in
  `agent-do/tools/agent-manna/src/workflow.rs::binding_material`: replace the
  single frontmatter binding value with `''`, then hash the complete document.
  The original file's ordinary SHA-256 was
  `b8a9b6d9772372f5d30e80a99b16cdba388bb535ce1d81613a7ceed641a436ee`.
- Checkout observed at `8c7d2368bfbec36decc9af791b1e63a3d9fb68a9`.
  This identifies the source checkout, not either Mac's installed build.
- Canonical state reports all eleven referenced build items as `done`.
  That records their lifecycle state only, not results for this field pass.
- No repository-root or `.handoff/AGENTS.md` exists. The parent workspace
  guide defers project work to this checkout; `.handoff/README.md` supplies
  the canonical handoff and sealing contract.
- Coord focus and path claims cover this handoff and only the `mn-235e6d`
  record in `.manna/issues.jsonl`. Five pre-existing public-document edits
  belong to another lane and are excluded from this change.

### Owner's results sheet

For each observation, record UTC time, host, installed Holy version/build,
actual result, and enough session/item identity to repeat the check. Mark a
check PASS or FAIL only from an observation. Leave missing evidence PENDING.

| # | Check and required observation | Source items | Result |
| --- | --- | --- | --- |
| 1 | Drag Board and Archive column grips and both inspector dividers. Resize the window narrow, then back. Record whether the dragged boundary stays where dropped and both ledgers still fit. | `mn-f044d0`, `mn-ac0b36` | PENDING |
| 2 | Clear, then Sync. Record that the window stays open and the roster reconverges. | `mn-3a03e3` | PENDING |
| 3 | Inspect the formerly stuck Codex rows. Compare the visible session activity with roster state; record whether any eternal spinner remains. | `mn-d204ae` | PENDING |
| 4 | Submit a Board question with Enter and click an answer citation. Record the question, cited item ID, and destination. | `mn-57866a` | PENDING |
| 5 | Choose a real READY item intended for work. Use its existing Claim & build confirmation. Record the item ID, a worker reaching a real prompt, and a roster note containing that full ID. | `mn-ec34cd`, dispatch repair `2786bfa16` | PENDING |
| 6 | Erik reports whether any Board or inspector “writing…” stalls have been seen since 2026-09-04. An explicit report of none gives the clean verdict; no reply supplies no evidence. | `mn-252f7a` | PENDING |
| 7 | At the next natural reboot, compare Codex restoration and seen/recency indicators before and after. Record restored conversations and whether the indicators survived. | `mn-9a9728`, `mn-18be22` | PENDING |
| 8 | From the MacBook, find Studio sessions in Archive, run one cross-host search, and restore one remote conversation. Record its source host and the restored session's host. | `mn-b61389` | PENDING |
| 9 | View a session on Studio, then inspect that same session on the MacBook. Record that its seen indicator agrees on both Macs. | `mn-2c82a2` | PENDING |

### Coordinated close

The local sitting covers checks 1 through 6. Check 7 waits for a natural reboot;
checks 8 and 9 require the MacBook and Studio. Record installed builds before
attributing an observation to shipped source. The preparation lane performs
no app launch, installation, screenshot, live session spawn, or forced reboot.
In particular, do not dispatch a worker merely to populate this results sheet
while the current no-launch lane is active.

Publish the pending pass and its ownership through Coord at close. Continue
with Erik's observations or a coordinated live acceptance window. An
unobserved check is remaining acceptance, not a product failure. Every observed
failure becomes a NEW Manna item citing the corresponding old item; leave the
old build item closed. Record the successor ID beside the failed observation.

Run `agent-do manna done mn-235e6d` only after all nine checks have observed
outcomes, each failure has its required successor, and Erik's field verdict
has been recorded. Preparation and a local commit do not close this item.

### Validation receipts

- Initial authenticated claim, canonical-state comparison, and independent
  binding calculation: PASS, exit 0.
- `scripts/test-holy-ghostty-build-contract.sh`: PASS, exit 0;
  output `Holy build contract tests passed.` This existing shell suite uses
  isolated build/installer fixtures. It is not an app compilation or a field
  acceptance result and did not install or launch Holy Ghostty.
- `git diff --check -- <this handoff> .manna/issues.jsonl`: PASS, exit 0.
- App-hosted tests compiled: **0**. App-hosted tests executed: **0**.
  No Swift or Zig implementation changed. The existing Xcode project sets
  `TEST_HOST` to Holy Ghostty; executing those tests launches the app.
- Remaining acceptance: all nine owner observations above. No field failure
  has been established, and no successor issue has been invented.
