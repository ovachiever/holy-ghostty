---
workflow: 2
manna: mn-e35536
track: mn-eb7a80
source: null
base_commit: b5287393cce4689985e19ebf1cd20259056c4485
scope: Docs and hygiene current for the next release
inputs: []
binding: sha256:a55a2fa71eb151434896c708944062be2d3ddded2f35a92664f043cf0e82a591
---

# Handoff: Docs and hygiene current for the next release

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-e35536
```

## Scope

Docs and hygiene current for the next release

## Inputs

- None declared.

## Work order

Verify v0.50..HEAD against shipped code; consolidate Unreleased; refresh four public docs; scan release hygiene and private data; run required gates; commit exact owned paths with manna trailer. Preparation on main only. No push, tags, PR operations, installs, app launches, or screenshots.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-e35536`.
4. Commit with `Manna: mn-e35536` and run `agent-do manna done mn-e35536` only after the work is verified.
