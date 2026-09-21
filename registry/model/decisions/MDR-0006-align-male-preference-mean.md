---
id: MDR-0006
title: Align male preference mean with the ODD
status: accepted
date: 2026-09-21
---

## Context

The ODD Parameters table (`odd_model_description.typ`, Parameters,
experiments, and output) states the default
`preference-private-mean-male = 0.45`, and the reference implementation
`gender_model_shocks_preferences.nlogox` ships the same value: the
`preference-private-mean-male` slider declares `default="0.45"` (its
BehaviorSpace value sets include 0.45 as well). The Julia port instead set
`MeanPreference.men` in `src/resources/properties.jl` to 0.44, a silent
one-hundredth divergence from both sources. Per `MDR-0001` the ODD is
normative and the `.nlogox` file is the tiebreaker, so neither source
supports 0.44. `registry/model/discrepancies.md` tracked the gap and
`TASK-0009` listed it for a decision before experiments are ported; the
status-quo test fixtures in `test/test_household_bargaining.jl` carried the
same 0.44 as the man's `alpha`.

## Decision

Adopt 0.45 as the male mean private preference everywhere: set
`MeanPreference.men = 0.45` in `src/resources/properties.jl`, use
`alpha = 0.45` for the man in the two status-quo fixtures of
`test/test_household_bargaining.jl`, and record the Julia default as 0.45 in
`registry/model/parameters.md`. The resolved row is removed from
`registry/model/discrepancies.md`, and `TASK-0009` keeps only its two
remaining open questions (the infeasibility penalty and `rho` vs `lambda`).
The female default 0.48 is untouched.

## Consequences

Initial male private preferences are drawn with the documented mean, so the
port matches the reference distribution and the ODD, and the parameter row
becomes `ported` without a discrepancy note. Runs that relied on the old
0.44 shift by the scale of that mean change. No ODD edit is needed because
the ODD already states 0.45; this record closes the divergence on the Julia
side rather than introducing a deviation from the specification.

## References

- `odd_model_description.typ`, Parameters, experiments, and output
- `gender_model_shocks_preferences.nlogox`, `preference-private-mean-male` slider
- `src/resources/properties.jl`
- `test/test_household_bargaining.jl`
- `MDR-0001`, `TASK-0009`
