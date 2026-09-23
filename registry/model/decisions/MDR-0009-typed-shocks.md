---
id: MDR-0009
title: Port Shocks with typed resources and a component tag
status: accepted
date: 2026-09-21
supersedes: ""
superseded_by: ""
---

## Context

NetLogo `start-shock` and `end-shock` in
`gender_model_shocks_preferences.nlogox` implement the ODD section Shocks
(`start-shock`, `end-shock`). The `go` procedure fires `start-shock` once
when `ticks = shock-start` and `end-shock` on every later tick
(`ticks > shock-start`), with gradual exponential recovery toward the
pre-shock baselines at rate `shock-depreciation`. The `setup` procedure
draws the wage-shock targets once with `n-of
(number-agents-each-type * perc-affected-* / 100)` per sex into
`directly-affected-men` and `directly-affected-women` (ODD Initialization
item 10). The ODD section Endogenous preference adaptation and wage growth
specifies the concurrent `update-preferences` pull toward own working time
(weight `lambda`) and the gap-closing `update-wages` process, which the
NetLogo `go` loop never calls.

The Julia stub `src/resources/shock.jl` is unwired: it declares
`ShockConfig` with the undefined `ShockType` and `SHOCK_NO`, stores the
`perc_*` setup draws as fields, and is not included in
`src/GenderNorms.jl` (see `registry/model/discrepancies.md`). The
`preference-private-pre` baseline has no Julia field, and `Wage.old`
exists but is not wired as the `wage-pre` shock baseline (see
`registry/model/entities.md`). The reference keeps four quirks this port
must preserve under `MDR-0003`: the preference shock shifts all turtles
globally while the wage shock hits the directly-affected sets only (ODD
Known implementation quirks item 9), the wage cut keeps a factor of 0.6,
the preference shift floors at zero with `max(0, ...)`, and recovery
rewrites only values still below their baseline so there is no overshoot.

## Decision

Port Shocks (`start-shock`, `end-shock`) into `src/resources/shock.jl`
and `src/systems/shocks.jl` as follows:

- Shock mode is resource presence, not a chooser string or enum: the
  concrete resources `WageShock` (fields `start`, `depreciation`) and
  `PreferenceShock` (fields `start`, `depreciation`, `delta_men`,
  `delta_woman`) each carry their own schedule. No `ShockType`, no
  `SHOCK_NO`, no `ShockConfig`. `WageGrowth` (field `rate`) carries the
  `wage-growth-rate` parameter. The `perc-affected-*` draws are only
  `select_affected!` setup arguments and are never stored; `lambda`
  stays out of the shock files.
- Baselines live on the agents: `Wage.old` is the `wage-pre` memory and
  the extended two-field `PreferencePrivate(current, pre)` carries the
  `preference-private-pre` memory. The affected sets become the empty
  tag component `DirectlyAffected`, added at setup to the drawn agents
  (NetLogo `directly-affected-*` agentsets, ODD Initialization item 10).
- `select_affected!` (setup only) counts per sex with the NetLogo
  `n-of` semantics (`floor` of `n * perc / 100`: a fractional size is
  rounded down, so `4.5` becomes `4`), draws with a partial Fisher-Yates
  shuffle, and tags with `Ark.add_components!`. It validates the
  percents to `[0, 100]` and throws `ArgumentError` when a positive
  share is requested from an empty breed (`n-of 0` of an empty set is
  empty, not an error). The tags are not cleared, so the draw is
  one-shot per world: a re-setup must build a new world.
- `start_shock!` preserves the quirks: the preference shock saves the
  baseline for all turtles, then applies `current = max(0, current -
  delta_sex)` globally with per-sex deltas; the wage shock saves
  `Wage.old = Wage.current` for all turtles, then applies `current =
  0.6 * old` (named constant `WAGE_CUT`) only to tagged agents.
- `recover_shock!` applies `current += depreciation * (baseline -
  current)` only while `current` is below its baseline, for wages and
  preferences alike, so closed gaps stay closed.
- `update_shocks!` checks `Ark.has_resource` for each shock type and
  dispatches `tick == start` to `start_shock!` and `tick > start` to
  `recover_shock!`; with both resources present both run, wage first,
  then preference. Neither resource present is the `"no"` no-op.
- `update_wages!` ports `update-wages` (gender wage means, daily rate
  `(1 + rate)^(1/365) - 1`, scale all women only when the gap and the
  rate are positive) but stays unscheduled because NetLogo `go` never
  calls it.

## Consequences

- `TASK-0003` closes with this change. `TASK-0005` stays open for
  scheduling `update_wages!`; `TASK-0004` is unaffected; `TASK-0007`
  absorbs the wiring of `select_affected!` into the setup sequence,
  which nothing calls yet (the draw is one-shot per world).
- The shock-propagation and household-type observer agentsets remain
  unported; only the functional affected-target part lands here (see
  `registry/model/entities.md`). Histories and subgroup means stay
  under `TASK-0001`.
- The tick path (`start_shock!`, `recover_shock!`, `update_shocks!`)
  allocates nothing and uses `Ark.Query` with `@inbounds` index loops;
  only the setup-only `select_affected!` may allocate.
- `update_preferences` in `src/systems/preferences.jl` preserves the
  new `pre` field when it adapts `current`, so shock recovery and
  preference adaptation keep pulling toward their distinct targets as
  in the reference.

## References

- `gender_model_shocks_preferences.nlogox`: `setup`, `go`,
  `start-shock`, `end-shock`, `update-wages`
- ODD sections Shocks (`start-shock`, `end-shock`), Endogenous
  preference adaptation and wage growth, Initialization item 10
- `src/resources/shock.jl`, `src/systems/shocks.jl`
- `MDR-0003`, `registry/code/decisions/ADR-0011`
