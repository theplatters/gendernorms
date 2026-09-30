---
id: MDR-0005
title: Continuous transfer bargaining
status: superseded
date: 2026-09-20
supersedes: ""
superseded_by: MDR-0012
---

## Context

NetLogo `set-theta` and `calculate-payoff` in
`gender_model_shocks_preferences.nlogox` implement the transfer stage of the
household bargaining (ODD section Transfer bargaining (`set-theta`,
`calculate-payoff`)). Per household, `set-theta` first solves `choose-bundle`
at `transfer-to-woman = 0` and evaluates `calculate-utility` for both partners
at that bundle with zero transfer; those values are the outside options. It
then searches `transfer-to-woman` for the transfer that maximizes the Nash
product of the two utility gains over the outside options, requires both
gains to be non-negative (`calculate-payoff` returns `-1` otherwise), and
commits the best transfer and the `choose-bundle` hours at that transfer to
both spouses.

The search is a discrete two-sided hill-climb with step `delta-theta = 0.001`,
started at `current-transfer-to-woman`, stopped at the first non-improvement
in each direction, with `best-payoff` and `best-theta` initialised to `0`.
ODD Known implementation quirks item 3 records that the status quo is
therefore never evaluated and the household falls back to zero transfer when
no candidate improves; item 5 records the `precision ... 8` plateaus of
`calculate-payoff`.

The transfer stage was unported: `registry/model/processes.md` listed
`set-theta` and `calculate-payoff` as not ported, the household loop in
`src/systems/household_bargaining.jl` (now `set_theta!`) ran the labour stage
only, and `registry/model/discrepancies.md` tracked the unused `Theta`
component and the missing transfer stage. `MDR-0002` replaced the discrete
labour climb of `choose-bundle` with continuous 1-D maximization and deferred
the transfer stage to a follow-up MDR; `MDR-0003` requires every NetLogo quirk
kept or fixed to be recorded explicitly; `ADR-0007` fixes the structure: the
transfer stage runs inside the household loop and reuses the transient
`AgentPayoffParams` across transfer evaluations. `TASK-0002` was the
implementation task.

## Decision

Port `set-theta` and `calculate-payoff` as a continuous transfer stage inside
the household loop `set_theta!` in `src/systems/household_bargaining.jl`,
with the pure helpers `bargain_transfer` (search), `equilibrium_payoff`,
`outside_options`, and `nash_product` (payoff), reusing
`mutual_best_response` and `individual_utility`:

- Outside options: solve `mutual_best_response(hw, hm, 0.0, pw, pm, config)`
  once per household and evaluate `individual_utility` for both partners at
  that bundle with zero transfer, as the first lines of `set-theta` do.
- Payoff: the Nash product of the two gains over the outside options when
  both gains are non-negative, treated as `-Inf` otherwise. This replaces the
  `-1` sentinel of `calculate-payoff`; it does not change the labour-stage
  infeasibility penalty, which stays tracked by `TASK-0009`.
- Search: a continuous 1-D maximization of the Nash product over `[-1, 1]`
  with the in-repo Brent search `maximize_1d` in `bargain_transfer`
  (absolute argument tolerance, see the bullet below), replacing both the
  discrete two-sided climb of the reference and the outward scan with
  `delta_theta` steps, three-step window, and pocket refinement of the
  first port. The status quo is evaluated first (fixing ODD quirk 3), and
  the reference's path anchoring at the current transfer is dropped. Every
  inner solve starts from the status-quo labour equilibrium. The interval
  is sampled directly, so a feasible band that the sample points do not
  reach is not found and the household keeps the status quo; that is the
  recorded cost of dropping the local walk, the fallback keeps the outcome
  safe (never worse than the status quo), and the extreme corner (a wage
  ratio near 40 with `alpha = 0.9`) is characterized by a test.
- Fallback: if the maximizer is not finite or does not beat the status-quo
  payoff, the household keeps its current transfer and the labour equilibrium
  at that transfer instead of resetting to zero transfer (the rest of ODD
  quirk 3).
- Commit: re-solve `mutual_best_response` at the chosen transfer, as
  `set-theta` re-runs `choose-bundle` at `best-theta`, and write the chosen
  transfer and the hours to both spouses' `TransferToWoman.current` and
  `WorkingTime.current`; the loop writes the woman through the `Ark.Query`
  column views and the man through `Ark.set_components!`, because he is not
  in the women's query, and returns nothing.
- The transfer stays bounded to `[-1, 1]`. The search tolerance is the
  absolute argument tolerance `TRANSFER_TOL = 1.0e-3`, the resolution of
  the reference's `delta-theta` grid. Both bracket endpoints are evaluated
  as candidates, so a corner optimum is returned exactly. The `rel_tol = 1.0e-8` and
  `abs_tol = 1.0e-10` of the first port are dropped: they are four orders
  finer than the reference grid and the `precision ... 8` payoffs, at
  roughly forty objective evaluations per household, each a full labour
  solve. Both bounds and the tolerance are solver parameters recorded
  here; changing them requires a follow-up MDR.
- The `precision ... 8` rounding and the fixed `delta-theta` grid are dropped
  with the discrete climb, so ODD quirk 5 becomes moot.
- The `Theta` component is not used, because the transfer already lives in
  `TransferToWoman.current`; the implementation removes the unused component
  and updates `registry/model/entities.md` and
  `registry/model/discrepancies.md` instead of wiring a duplicate.

## Consequences

The transfer stage becomes continuous: a household runs one in-repo Brent
maximization with roughly 13 to 17 objective evaluations per tick (13 at the
wage-gap interior optimum, 17 when no finite maximizer is found) instead of the
NetLogo grid walk, while the non-cooperative household equilibrium and the
one-instrument bargaining structure are unchanged. Results are no longer
bit-comparable to NetLogo: the transfer can differ at the scale of the old
`delta-theta = 0.001` grid, the status-quo fallback replaces the
zero-transfer default of ODD quirk 3, and the `precision` plateaus of quirk 5
disappear. `TASK-0002` is implemented:
`registry/model/processes.md` lists `set-theta` and `calculate-payoff` as
ported with this record, `registry/model/discrepancies.md` dropped the
resolved transfer-stage rows, `registry/code/architecture.md` notes that
`set_theta!` runs both stages, and tests cover the outside option, a positive
and a negative interior optimum, an infeasible status quo, the fallback, the
narrow feasible band that the maximizer does not reach, and the committed
bundle matching the equilibrium at the committed transfer. The ODD section Transfer bargaining still describes the discrete
search and becomes stale for the port, as its Labour best response section
did for `MDR-0002`.

## References

- `odd_model_description.typ`, Transfer bargaining (`set-theta`, `calculate-payoff`), Known implementation quirks
- `gender_model_shocks_preferences.nlogox`, `set-theta`, `calculate-payoff`
- `src/systems/household_bargaining.jl`
- `src/resources/utility_functions.jl`
- `MDR-0002`, `MDR-0003`, `ADR-0007`, `TASK-0002`
