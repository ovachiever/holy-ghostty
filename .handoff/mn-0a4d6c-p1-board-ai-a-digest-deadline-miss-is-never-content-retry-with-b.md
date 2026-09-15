---
workflow: 2
manna: mn-0a4d6c
track: mn-9a97cc
source: null
base_commit: b59c57b942591bc754483e57ec06124feca98439
scope: '[P1][BOARD][AI] A digest deadline miss is never content: retry with backoff, honest pending state, and a real deadline'
inputs: []
binding: sha256:ce97132176592d7d59c5741453f810aa125f7921504c280c237189d2b64fe276
---

# Handoff: [P1][BOARD][AI] A digest deadline miss is never content: retry with backoff, honest pending state, and a real deadline

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-0a4d6c
```

## Scope

[P1][BOARD][AI] A digest deadline miss is never content: retry with backoff, honest pending state, and a real deadline

## Inputs

- None declared.

## Work order

Erik 2026-09-14 (screenshot, mn-56f896 inspector): AI SUMMARY renders 'Holy fast model did not finish before the safety deadline.' — a timeout error occupying the summary surface as terminal state. Traced end to end: HolyMannaBoardDigest.complete() runs one claude --print per batch of up to 12 items (batchSize, HolyMannaBoardDigest.swift:63) under a 60-second deadline (bare literal at :586 for the OpenAI route and :625 for the CLI route — both violate the numbers-from-authority rule); a single slow run throws HolyMannaBoardClientError.timedOut whose errorDescription ('did not finish before the safety deadline', HolyMannaBoardClient.swift:41) flows through the job catch (HolyMannaBoardDigest.swift:534) into sink .failed, and HolyMannaBoardStore.applyWarmEvent (:1004) writes that message into digestFailures for ALL 12 items in the batch — the inspector then shows the error where the summary belongs until some later generation succeeds. Cold-start claude CLI plus a large post-gap board makes 60s routinely insufficient, and one miss poisons twelve rows. Fix (design, not a bigger number): (1) a deadline miss is RETRYABLE, never terminal — requeue the batch with escalating budget (e.g. once at 2x, then park until the next warm cycle), counting attempts per content hash so a genuinely wedged run stops retrying; (2) the UI never renders transport/timeout errors as summary text — timeout-class failures show a quiet 'summarizing…' pending state (the existing digest-loading affordance), while real refusals (usage guard, missing binary) keep their honest message; (3) replace both 60-second literals with a named constant derived from role and batch size, documented with its provenance, shared by the CLI and OpenAI routes; (4) split-batch salvage: on a second miss, halve the batch (6, then 3) so one slow item cannot hold hostage eleven others — mirrors the embeddings halving precedent in the archive lane. Tests: a timed-out batch requeues and its items show pending not error; a usage-guard refusal still shows its message; halving isolates a slow item; the constant is referenced from both routes. Acceptance: Erik opens the board after a burst of new items and never sees a deadline message in AI SUMMARY — summaries either appear or show pending until they do.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-0a4d6c`.
4. Commit with `Manna: mn-0a4d6c` and run `agent-do manna done mn-0a4d6c` only after the work is verified.
