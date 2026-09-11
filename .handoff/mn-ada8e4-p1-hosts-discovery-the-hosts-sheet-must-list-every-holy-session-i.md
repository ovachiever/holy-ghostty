---
workflow: 2
manna: mn-ada8e4
track: mn-eb7a80
source: Erik screenshot 2026-09-10 19:38 (badge 32, rows fewer, spinner stuck) + Studio ground truth 43 sessions
base_commit: c681f6a468251b3b262b4023e020d546de6cb5ba
scope: '[P1][HOSTS][DISCOVERY] The hosts sheet must list every holy session it counts: no classification-based drops, no partial-as-complete'
inputs:
- Erik screenshot 2026-09-10 19:38 (badge 32, rows fewer, spinner stuck) + Studio ground truth 43 sessions
binding: sha256:a0aee5f2fcd4838b59b131b7ec8d5356dd8a57658d0d60195429e6b8ca165dba
---

# Handoff: [P1][HOSTS][DISCOVERY] The hosts sheet must list every holy session it counts: no classification-based drops, no partial-as-complete

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-ada8e4
```

## Scope

[P1][HOSTS][DISCOVERY] The hosts sheet must list every holy session it counts: no classification-based drops, no partial-as-complete

## Inputs

- Erik screenshot 2026-09-10 19:38 (badge 32, rows fewer, spinner stuck) + Studio ground truth 43 sessions

## Work order

Erik 2026-09-10, MacBook: the Studio row's badge says 32 live sessions while the actual server runs 43, and entire groups are missing from the list (his six VSI workers among them) — sessions the classifier cannot type (bash-leader wrapper panes, see the sibling exec-dispatch item) are silently dropped from display, and a still-running discovery sweep renders partial results indistinguishable from complete ones. Fix: (1) COMPLETENESS LAW — every session on the host whose name carries Holy's prefixes (holy-shell-*, holy-worker-*, and adopted names) appears in the list; unknown runtime renders honestly in an 'unclassified' group with the session name and cwd rather than vanishing; the count badge equals the number of rows, always, or the discrepancy itself is displayed. (2) PARTIAL HONESTY — while the sweep runs, the list says 'showing N of M discovered so far'; a hung or timed-out sweep says so (the admission lane's typed diagnoses exist for this) instead of freezing a spinner over stale rows. Tests: fixture with unclassifiable sessions asserts they render; count==rows invariant; partial-sweep banner. Acceptance: MacBook hosts sheet shows all 43 Studio sessions with the six VSI workers present (grouped correctly once the exec fix lands, honestly unclassified before it).

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-ada8e4`.
4. Commit with `Manna: mn-ada8e4` and run `agent-do manna done mn-ada8e4` only after the work is verified.
