---
id: MDR-0019
title: Committed-bundle utility observations with a UtilityStats observer
status: accepted
date: 2026-10-05
supersedes: MDR-0018
superseded_by: ""
---

## Context

NetLogo `choose-bundle` stores `current-utility` as the mutable scratch
of its discrete labour hill-climb, and BehaviorSpace reports that stored
value as a per-experiment diagnostic (`mean [current-utility] of women`);
the ODD sections Entities, state variables, and scales, Labour best
response, and Parameters, experiments, and output describe this scratch
and diagnostic state (ODD quirk 11 records that the reported value is
the last counterfactual evaluation, not the committed bundle).
`MDR-0018` removed the unused zero-initialized `CurrentUtility`
placeholder from the Julia port and its Decision prohibited replacement
storage unconditionally: "Do not introduce a replacement stored utility
carrier or add utility computation to the tick loop." That removal was
correct, since the placeholder was never populated or consumed.
Separately, the `MDR-0018` Consequences sentence "Any future utility
observer must specify its evaluation state and timing rather than
revive the zero-valued placeholder" states the requirement this
successor record satisfies.

The run pipeline now provides per-tick metric consumers
(`model_metrics` -> `logging.metrics` -> `runs/*/run.toml` ->
dashboard, `ADR-0012`, `ADR-0025`, `ADR-0026`), so a specified utility
observer has a consumer and a defined observation point. Making utility
observable per tick is a model-behavior decision about evaluation state
and timing and needs an MDR.

## Decision

Add a committed-bundle utility observer, reversing the `MDR-0018`
prohibition ONLY for this specified, populated, and consumed observer,
not for arbitrary utility scratch:

- New immutable component `CommittedUtility` with field `value::Float64`
  in `src/components.jl`. It is deliberately NOT named `CurrentUtility`:
  the decision invariant `!isdefined(GN, :CurrentUtility)` stays true.
  The docstring cites NetLogo `current-utility`, the ODD sections, and
  this record.
- Evaluation state and timing: for every household, `set_theta!`
  evaluates, immediately after `bargain_transfer` returns with the
  committed bundle `(theta, hw, hm)`, the two levels
  `U_w = individual_utility(hw, hm, theta, pw, config)` and
  `U_m = individual_utility(hm, hw, theta, pm, config)` from the tick's
  already-prepared payoff parameters `pw`/`pm` via `individual_utility`
  (single source of truth with the labour solver, `MDR-0013`). The
  values are utility LEVELS at the committed bundle (not gains and not
  Nash payoffs), evaluated with pre-adaptation preferences and the
  tick's perceived norms. They are evaluated on every commit path,
  including status-quo retention and `bargain_transfer`'s non-finite
  fallback, and non-finite results propagate unchanged into the
  observer (no clamping, no zero-filling, no dropping of agents).
- These are clean committed-bundle observations, deliberately NOT a
  reproduction of NetLogo's mutable `choose-bundle` scratch: the quirk
  11 staleness (reported `current-utility` reflecting the last
  counterfactual evaluation) is not reproduced, and the reference's
  stored scratch semantics stay not ported. `utility_women` matches the
  reference's female-mean diagnostic intent; `utility_men` is an
  explicitly recorded Julia extension.
- New mutable resource `UtilityStats(men, women)` in
  `src/resources/observers.jl`, the per-sex means of the stored values
  (one observer group per resource, the `MDR-0008` rule). All new
  agents and resources initialize to `NaN` = "not yet observed"; setup
  runs no bargaining and stores no zero fakes. `CommittedUtility` is
  registered on every agent at setup before the first step.
- The aggregates are computed by the fused observer snapshot
  `update_observer_stats!` at the tick's single observation point
  (`MDR-0022`), and exposed as the `utility_men` / `utility_women`
  run-pipeline metrics (`ADR-0026`).

## Consequences

`CommittedUtility` becomes per-agent state written by `set_theta!`'s
existing commit step (disjoint per household) and read only by the
observer snapshot; no solver, objective, or search code changes. The
reference implementation and the ODD NetLogo descriptions stay factual
and unchanged; the ODD gains a Julia-port note for the observer.
`registry/model/entities.md` maps the committed diagnostic to
`CommittedUtility` with non-scratch semantics and keeps the raw
`current-utility` scratch as not ported. The decision invariants keep
`!isdefined(GN, :CurrentUtility)` and pin the new committed-observer
contract instead of the old "no stored utility" rule. Utility
observation is bitwise reproducible across thread counts because the
writes are disjoint and the aggregation is serial (`ADR-0026`).
