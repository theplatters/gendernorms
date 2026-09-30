---
id: ADR-0021
title: Seeded Brent feasibility-guided production driver
status: accepted
date: 2026-09-30
supersedes: ADR-0020
superseded_by: ""
---

## Context

`MDR-0016` replaces the production probe schedule of `MDR-0015` (NetLogo
`set-theta`, `calculate-payoff`; ODD Transfer bargaining). The objective
chain, certificates, discovery driver, and task-owned scratch must remain
shared, and the driver must fit the record budget of 44 with the
allocation and timing of the in-tree pre-change reference level.

## Decision

`_transfer_local_search!` implements the sparse adaptive schedule of
`MDR-0016` in place: anchors and the `TRANSFER_EXPLORE_OFFSETS` ladder
with one shared ladder when the anchors overlap
(`TRANSFER_ANCHOR_OVERLAP`), conditional `TRANSFER_ADAPTIVE_OFFSET`
probes driven by the sampled guidance values, thresholded one-peak
guidance refinement and one strictly-improving-payoff refinement
(`TRANSFER_GUIDANCE_REFINEMENTS`, `TRANSFER_MAX_REFINEMENTS`,
`TRANSFER_REFINE_MAX_ITER`), and selection over every finite cached
record under the unchanged `_transfer_better` order. Stage C brackets are
rebuilt from actual cached records and skipped entirely when no cached
finite payoff strictly beats the status quo. The dense-doubling ladder
drafted during tuning is historical context recorded in `MDR-0016`.

Structural pieces:

- `_brent_maximize` gained an explicit initial-point variant; the
  original golden-section variant and non-finite-as-worst handling are
  unchanged and `maximize_1d` keeps both of its entry points.
- `TransferObjectiveValue` carries separate `guidance_w`/`guidance_m`
  gains so certified records never masquerade as solved gains; the
  five-argument constructor uses solved gains as guidance for discovery
  and tests. The gains `_transfer_gains` computes once feed both
  `_nash_from_gains` (unchanged payoff) and the guidance.
- Production Stage A appends only new records through one `get` lookup in
  the shared `_transfer_eval!` cache hit path; objective calls, keys,
  records, and discovery's complete sampled sequence and slab prefilter
  are unchanged.
- Scratch storage is reused across the households of a
  `Threads.@threads :greedy` chunk (`_reset_scratch!`); capacity hints
  are `TRANSFER_CACHE_CAPACITY`/`TRANSFER_SAMPLE_CAPACITY` = 32 records
  and samples (typical calls need 15 records), rather than the 256/128
  hints sized for the superseded 216-record search. `Dict` `empty!`
  retains storage; the non-shrinking size hint cannot retain household
  parameters or closures and does not affect probe order.
- Normalization scales are per-call keyword arguments of
  `_transfer_local_search!`, never retained in scratch.

## Consequences

No include, dependency, public API, world chunking, or thread-indexed
state changes. Probe sequences are deterministic and thread-count
independent. The iteration caps bound distinct records at
`TRANSFER_SEARCH_MAX_EVALS` without manufacturing infeasible sentinels on
exhaustion. Acceptance evidence, fixture payoffs, and the contract-test
rewrite live in `MDR-0016`; `TASK-0021` tracks the work item.
