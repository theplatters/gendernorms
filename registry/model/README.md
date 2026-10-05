# Model registry

Current search decision: `registry/model/decisions/MDR-0016-feasibility-guided-transfer-search.md`
supersedes `MDR-0015`; accepted with the performance and fixture evidence
of `TASK-0021`.

The model registry records what the NetLogo model does and how (or whether)
the Julia port in `src/` implements it. It is the model half of the single
source of truth described in `registry/README.md`.

## The three sources

- `odd_model_description.typ` -- the normative model specification. Per
  `MDR-0001`, this ODD-style description decides what counts as intended
  model behavior.
- `gender_model_shocks_preferences.nlogox` -- the reference implementation.
  Where the ODD is ambiguous, the NetLogo code as shipped is the tiebreaker
  (including its quirks, see `MDR-0003`).
- `src/` -- the Julia port (`GenderNorms` package). It must follow the ODD
  and the reference implementation; any intentional divergence needs a new
  MDR recorded first.

Relationship: the ODD says what the model means, the `.nlogox` file shows
what the model does line by line, and `src/` re-implements that behavior in
Julia. The tables below map the first two onto the third so gaps are visible
instead of silent.

## How to keep the registry in sync when porting

1. Read `odd_model_description.typ` fully and the relevant NetLogo procedure
   in `gender_model_shocks_preferences.nlogox` before writing port code.
2. If you port a new entity, parameter, or process, add or update its row in
   `registry/model/entities.md`, `registry/model/parameters.md`, or
   `registry/model/processes.md` in the same change.
3. If you find a NetLogo-vs-Julia gap, an unwired file, or an open question,
   record it in `registry/model/discrepancies.md`. Do not silently fix or
   hide it.
4. If you intentionally diverge from the ODD or reference (solver change,
   quirk fix, new default), write a new MDR under
   `registry/model/decisions/` first, then implement, then reflect the row
   updates back into the tables.
5. Cite the NetLogo procedure and ODD section for every ported behavior, and
   mark anything not implementable from the evidence as `unknown` or
   `not ported` rather than guessing.
6. Record follow-up work that is not implemented yet in
   `registry/tasks.md`, citing the table row or decision it comes from.

## Index

- `registry/model/entities.md` -- every ODD entity and state variable mapped
  to NetLogo and to Julia symbols, with port status.
- `registry/model/parameters.md` -- every ODD parameter default mapped to its
  Julia location and default, with discrepancy notes.
- `registry/model/processes.md` -- every NetLogo procedure mapped to its ODD
  section and Julia symbol(s), with port status.
- `registry/model/discrepancies.md` -- concrete discrepancies, unwired items,
  and open questions with evidence and suggested resolutions.
- `registry/model/decisions/MDR-0001-normative-model-specification.md` --
  the ODD is normative, the `.nlogox` is the reference, `src/` is the port.
- `registry/model/decisions/MDR-0002-continuous-best-response-solver.md` --
  the port solves `choose-bundle` by continuous maximization (superseded
  by `MDR-0017`; its seeded Brent path is the fallback solver there).
- `registry/model/decisions/MDR-0003-preserve-netlogo-quirks.md` -- NetLogo
  quirks are reference behavior until an MDR fixes one.
- `registry/model/decisions/MDR-0004-norm-perception-port.md` -- norm
  perception (`calculate-utility`) ported into `src/systems/norm_perception.jl`.
- `registry/model/decisions/MDR-0005-continuous-transfer-bargaining.md` --
  the port solves `set-theta` / `calculate-payoff` by continuous transfer
  bargaining (superseded by `MDR-0012`).
- `registry/model/decisions/MDR-0006-align-male-preference-mean.md` -- the
  male mean private preference is 0.45, matching the ODD.
- `registry/model/decisions/MDR-0007-port-statistics-core.md` -- the
  lightweight `update-statistics` core (lag copy plus men/women/gap means)
  in `src/systems/statistics.jl`.
- `registry/model/decisions/MDR-0008-remove-unused-global-stats.md` --
  the unused `GlobalStats` carrier is removed; histories, the stored
  transfer mean, run time, and the wage gap have no Julia carrier.
- `registry/model/decisions/MDR-0009-typed-shocks.md` -- typed shock
  resources with a component tag and quirk-preserving start and recovery.
- `registry/model/decisions/MDR-0010-go-tick-loop-scheduling.md` -- the
  `go` tick loop scheduled as the `step_model!` port (see `ADR-0012`;
  superseded by `MDR-0022`, which keeps the scheduling and swaps in the
  fused observer snapshot).
- `registry/model/decisions/MDR-0011-benchmark-methodology.md` --
  matched-configuration runtime comparison of the NetLogo and Julia
  implementations (see `ADR-0013`).
- `registry/model/decisions/MDR-0012-transfer-search-feasibility-discovery.md` --
  staged feasibility-discovery transfer search replacing the unseeded
  Brent search of `MDR-0005` (see `ADR-0016`; superseded by
  `MDR-0013`).
- `registry/model/decisions/MDR-0013-prepared-best-response-arithmetic.md` --
  prepared best-response objective and the validated-equivalent `CES`
  `beta == 0.5` sqrt/square material specialization, restating the
  preserved transfer semantics of `MDR-0012` (see `ADR-0018`;
  superseded by `MDR-0014`).
- `registry/model/decisions/MDR-0014-tiered-transfer-search-sample-set.md` --
  tiered Stage A sample set of the staged transfer search (fine 1e-4
  windows `+/- 0.002` around the anchors, 1e-3 coarse grid elsewhere),
  the named solver parameters of that set, and the narrowed discovery
  guarantee of the annulus coarsening (see `ADR-0019`; production search
  superseded by `MDR-0015`).
- `registry/model/decisions/MDR-0015-bounded-anchor-local-transfer-search.md` --
  bounded anchor-local production search with explicit sampling and
  refinement budgets, retaining `MDR-0014` discovery for validation
  (see `ADR-0020`; superseded by `MDR-0016`).
- `registry/model/decisions/MDR-0016-feasibility-guided-transfer-search.md` --
  feasibility-guided budgeted production transfer search: the sparse
  adaptive exploration ladder, guidance semantics (true gains at solved
  probes, certified bound gains at pruned probes, normalized by
  `max(abs(outside option), 1.0)`), the guidance branch-discontinuity
  finding, the 44-record budget, and the "best candidate found, not
  global optimum" claim (see `ADR-0021`).
- `registry/model/decisions/MDR-0017-safeguarded-derivative-best-responses.md` --
  safeguarded derivative labour best responses for eligible utility
  regimes with the seeded Brent fallback of `MDR-0002` (superseded by
  this record): the log-utility derivative formulas per spec, the
  applicability regime with its fail-open numerical gate, the solver
  algorithm, and the validated-equivalence protocol (see `ADR-0022`).
- `registry/model/decisions/MDR-0018-remove-unused-current-utility.md` --
  remove the unused stored utility component without changing the pure
  utility evaluation or bargaining solvers (superseded by `MDR-0019`,
  which reverses the prohibition only for the specified committed-bundle
  observer).
- `registry/model/decisions/MDR-0019-committed-utility-observers.md` --
  committed-bundle utility observations (`CommittedUtility` plus the
  `UtilityStats` observer): evaluation state and timing inside
  `set_theta!`, non-scratch semantics without quirk 11 staleness, and
  the gendered `utility_women`/`utility_men` metrics (see `ADR-0026`;
  supersedes `MDR-0018`).
- `registry/model/decisions/MDR-0020-preference-mean-observers.md` --
  pre-adaptation gendered preference means (`PreferenceStats`) as a new
  Julia-side diagnostic distinct from the unported
  `preference-difference` (see `ADR-0026`).
- `registry/model/decisions/MDR-0021-contemporaneous-transfer-observer.md` --
  contemporaneous transfer mean over women (`TransferStats`), the stored
  `global-mean-transfer` of NetLogo `update-statistics`, distinct from
  the lagged `norm_global_means` transfer (see `ADR-0026`; discharges
  the `TASK-0001` storage clause).
- `registry/model/decisions/MDR-0022-observer-snapshot-tick-scheduling.md` --
  tick scheduling with the fused `update_observer_stats!` snapshot at
  the single pre-adaptation observation point, restating `MDR-0010`'s
  guarantees and making the statistics/adaptation order observationally
  significant (see `ADR-0026`; supersedes `MDR-0010`).
