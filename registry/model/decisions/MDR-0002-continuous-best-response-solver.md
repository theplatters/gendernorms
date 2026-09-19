---
id: MDR-0002
title: Continuous best-response solver
status: accepted
date: 2026-09-19
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

The port implements `choose-bundle` as continuous 1-D maximization
(`Optim.maximize` with Brent in `best_response_1d` in
`src/resources/utility_functions.jl`) inside alternating best responses
(`mutual_best_response` in `src/systems/household_bargaining.jl` with
`eps = 1.0e-3` and `max_sweeps = 100`). This replaces NetLogo's discrete
fixed-step hill-climb (`current-delta = 0.0001`) while keeping the same
alternating structure and stopping tolerance. Per `MDR-0001`, this
intentional deviation is recorded here rather than made silently.

## Consequences

Convergence is smoother and typically faster, but results are not
bit-comparable to NetLogo: committed hours can differ at the scale of the old
grid and stopping tolerance. The ODD section Labour best response still
describes the discrete climber and is therefore stale for the port; it should
be updated to document the continuous solver. Solver tuning (tolerances,
sweep cap, infeasibility handling in `individual_utility`) must come back
here as follow-up MDRs, not as silent edits.

## References

- `odd_model_description.typ`, Labour best response
- `gender_model_shocks_preferences.nlogox`, `choose-bundle`
- `src/systems/household_bargaining.jl`
- `src/resources/utility_functions.jl`
