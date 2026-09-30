---
id: ADR-0020
title: Bounded production transfer driver and discovery validation mode
status: superseded
date: 2026-09-30
supersedes: ""
superseded_by: ADR-0021
---

## Context

`MDR-0015` authorizes a bounded anchor-local production transfer search
and retains the current `MDR-0014` discovery solver for offline comparison.
Both need the identical objective, status seeding, pointwise certificate,
and cached-hours commit rule in `src/systems/household_bargaining.jl`
(NetLogo `set-theta`, `calculate-payoff`; ODD section Transfer bargaining).
The discovery sample-set and certificate tests must remain meaningful;
changing their oracle to a different search would hide regressions.

## Decision

Add `_transfer_local_search!` alongside the unchanged `_transfer_search!`
discovery driver. The local driver reuses `TransferSearchScratch`,
`TransferObjectiveValue`, `_transfer_eval!`, `_transfer_sample!`, and
`_transfer_better`; it does not construct interval slabs or enumerate
the full-domain grid. Its bounded sample enumeration and prioritized,
iteration-limited refinements are governed by `MDR-0015`.

Both scratch-taking and standalone `bargain_transfer` methods accept
`search::Symbol=:local`, with only `:local` and `:discovery` valid. The
world loop `set_theta!` accepts the same optional keyword for validation
trajectories; runtime model configuration remains unchanged and invokes
the local default. Reject unknown modes and non-positive/non-finite
refinement tolerances rather than silently changing modes.

All objective preparation and commit logic stay shared in `bargain_transfer`.
Only driver selection differs. Reset scratch at the start of every call,
including the non-finite-outside fast path. Never retain parameters or
closures in scratch; ownership stays one scratch per greedy chunk task,
not per thread (`ADR-0017`). Resize initial storage hints for the local
budget: sampled-vector hint 128, cache hint 256; the offline discovery
path grows these buffers normally without imposing production caps on it.

Keep the existing discovery contract and interval-prefilter tests, now
explicitly selecting discovery for tests that compare that solver's
commits. Update the independent production cache replay to use the local
driver and add `test/test_transfer_local_search.jl` for the production
contract. Provide reproducible validation tooling in `benchmark/` rather
than relying on throwaway scripts outside the repository. No new package
source file, include-order change, dependency, or TOML field is required.

## Consequences

The full-domain scan remains available but is no longer an implicit cost
of every household-tick. Its unchanged output contract can be tested
independently; it is not a correctness oracle asserting global optimality.
Mode selection is explicit, with no automatic discovery fallback after
failed local probes or budget exhaustion. The production cost is bounded
in objective calls even on fail-open certificates and jagged objectives;
the labour solver keeps its separate existing iteration bounds.

Register new constants and helpers in `registry/code/architecture.md`,
model search parameters and process status in `registry/model/`, and
measurement evidence in `benchmark/anchor_local_validation.md`.
This extends `ADR-0016`/`ADR-0017`/`ADR-0019` without retiring their
evaluation record, task-owned storage, interval certificate, or CES
envelope. Verification is completed under `TASK-0020` and recorded in
`benchmark/anchor_local_validation.md`: discovery contract/certificate
tests remain green, the production cache replay is exact on 200 solver
fixtures, the explicit worst-case test reaches but never exceeds 216
records even at tolerance 1e-100, scratch reuse including the non-finite
fast path is stateless, and 1/8-thread results are deterministic.
The production kernel is about 10.5x faster on ws_500; preserved objective
semantics do not imply equivalent search outcomes on low conformism
(the material losses are recorded in `MDR-0015` and the validation report).
