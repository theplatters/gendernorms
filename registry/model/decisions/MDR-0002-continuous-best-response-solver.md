---
id: MDR-0002
title: Continuous best-response solver
status: superseded
date: 2026-09-19
supersedes: ""
superseded_by: MDR-0017
---

## Context

NetLogo `choose-bundle` finds the household labour outcome by iterated best
response with a discrete fixed-step hill-climb: each partner steps own hours
by `current-delta = 0.0001` while it strictly improves own utility, partners
alternate, and the loop stops when the joint change is at most
`convergence_epsilon` (default 0.001), with `memory-change` guarding against
2-cycles (see the ODD section Labour best response and the pseudocode header
in `src/systems/household_bargaining.jl`). A literal step-by-step port would
be slow and would inherit the coarse grid and plateau behavior of the
original search.

## Decision

The port implements `choose-bundle` as continuous 1-D maximization inside
alternating best responses (`mutual_best_response` in
`src/systems/household_bargaining.jl` with `eps = 1.0e-3` and
`max_sweeps = 100`). The maximizer is the in-repo Brent search
`maximize_1d` in `src/resources/utility_functions.jl` (golden section with
parabolic interpolation, the maximization variant of the standard Brent
minimization with an absolute argument tolerance), reached through
`best_response_1d`, which searches own working time on `[0, 1]` with
`BEST_RESPONSE_TOL = 1.0e-4` (the NetLogo `current-delta`). This replaces
NetLogo's discrete fixed-step hill-climb (`current-delta = 0.0001`) and
the `Optim.Brent` call of the first port, and drops the `Optim`
dependency, whose only use it was. Per `MDR-0001`, this intentional
deviation is recorded here rather than made silently.

The best response is seeded at the current hours of the agent: the search
first probes the seed and its neighbours at the resolution
`BEST_RESPONSE_TOL`, and returns the seed when no probe improves on it
(the state in which the NetLogo climb stops). Otherwise it maximizes on
the window with half-width `BEST_RESPONSE_WINDOW = 5.0e-2` around the
seed, clipped to `[0, 1]`, and falls back to the full `[0, 1]` bracket
when the window maximizer lies on an interior window edge or the window
contains no feasible sample; the returned point is the best finite candidate
evaluated (seed, probes, window, full bracket). A best response with no feasible sample keeps the current hours
in `mutual_best_response`.

## Consequences

Superseded by `MDR-0017` (`MDR-0017` supersedes `MDR-0002`): eligible
utility regimes now solve the best response by the safeguarded
derivative root solve of `MDR-0017`, and the seeded window path of this
record remains in force verbatim as their fallback and as the solver of
every ineligible case (the `eps`/`max_sweeps` loop, the NaN-keeps-hours
rule, and the `BEST_RESPONSE_TOL`/`BEST_RESPONSE_WINDOW` semantics below
stay in force for that path). The historical consequences below describe
the fallback solver.

Convergence is smoother and typically faster, but results are not
bit-comparable to NetLogo: committed hours can differ at the scale of the
old grid and stopping tolerance. The seeded window reintroduces the path
anchoring of the NetLogo climb for the labour stage: a household whose
current hours are locally optimal stops there, and the global fallback is
what keeps a maximum outside the window reachable. This is deliberate;
the transfer stage keeps its unanchored search (`MDR-0005`). The ODD
section Labour best response still describes the discrete climber and is
therefore stale for the port; it should be updated to document the
continuous solver. The solver parameters are `BEST_RESPONSE_TOL`,
`BEST_RESPONSE_WINDOW`, the `eps`/`max_sweeps` pair, and the
non-finite-sample fallback; further tuning must come back here as
follow-up MDRs, not as silent edits.
- The labour loop binds each captured partner hour immutably per iteration
  so the best-response closures stay type-specialized and allocation-free;
  boxing the captures (the first implementation) cost around 256 bytes and
  around 36 percent of the per-solve time, and must not be reintroduced.

## References

- `odd_model_description.typ`, Labour best response
- `gender_model_shocks_preferences.nlogox`, `choose-bundle`
- `src/systems/household_bargaining.jl`
- `src/resources/utility_functions.jl`
