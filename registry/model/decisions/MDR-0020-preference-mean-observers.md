---
id: MDR-0020
title: Pre-adaptation gendered preference means with a PreferenceStats observer
status: accepted
date: 2026-10-05
supersedes: ""
superseded_by: ""
---

## Context

NetLogo has no global for the mean private preference: it only plots
`mean [preference-difference] of women` and `mean
[preference-difference] of men` per sex (the `preference-difference`
diagnostic of `update-preferences`, ODD section Endogenous preference
adaptation), and that series stays not ported (see
`registry/model/entities.md`). Per-tick preference means are therefore
a new Julia-side diagnostic, an intentional extension recorded here
rather than invented silently.

Preference adaptation (`update_preferences`, NetLogo
`update-preferences`) rewrites `PreferencePrivate.current` at the end
of every tick, so the mean is timing-dependent: observing it before the
adaptation reports the preferences the tick's bargaining actually used,
observing it after reports the adapted state.

## Decision

Add the mutable resource `PreferenceStats(men, women)` in
`src/resources/observers.jl`, the per-sex means of
`PreferencePrivate.current` (one observer group per resource, the
`MDR-0008` rule), and expose them as the `preference_men` /
`preference_women` run-pipeline metrics (range `[0, 1]`).

- Observation timing: the means are observed PRE-adaptation, at the
  tick's single observer snapshot after bargaining and shocks and
  before `update_preferences` runs (`MDR-0022`), so the logged value is
  the preference state the tick's committed bundles were bargained
  under.
- The metric is new Julia-side observation behavior with no NetLogo
  global; `preference-difference` stays not ported and is not conflated
  with these means.
- The resource initializes to `NaN` = "not yet observed" at setup, like
  every new observer of this package (`MDR-0019`, `MDR-0021`).

## Consequences

The fused observer snapshot `update_observer_stats!` accumulates the
two sums in its serial gender reductions (`MDR-0022`); the statistic
adapts nothing and changes no dynamics. The statistics/adaptation tick
ordering becomes observationally significant (see `MDR-0022`): moving
the snapshot after `update_preferences` would silently change the
logged series. `registry/model/entities.md` and
`registry/model/processes.md` register the new observer and
distinguish it from the unported `preference-difference`;
`registry/model/parameters.md` distinguishes the initialization means
(`preference-private-mean-*`) from these observed means (no parameter
or default changes).
