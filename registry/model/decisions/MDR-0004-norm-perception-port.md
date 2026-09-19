---
id: MDR-0004
title: Port norm perception from calculate-utility
status: accepted
date: 2026-09-19
---

## Context

NetLogo `calculate-utility` in `gender_model_shocks_preferences.nlogox`
computes three perceived norms from lagged (`old-*`) values before
evaluating utility: the mean `old-working-time` of the agent's same-sex
`link-neighbors`, the mean `old-transfer-to-woman` of those neighbours,
and the mean `old-working-time` of the deduplicated spouses of those
neighbours. Isolated agents fall back to their own lag, or to the global
means (`global-mean-working-time-women/men`, `global-mean-transfer`)
under `network-structure = "homogenous mixing"`. The ODD section Norm
perception (`calculate-utility`) specifies this, and the ODD entity table
lists `norm-parameter` and `perception-norm-division-of-labor` as stored
`turtles-own` variables; ODD quirk 11 notes the stored values reflect the
last `calculate-utility` call, including counterfactual evaluations, not
necessarily the committed bundle. Until now nothing in `src/` computed
neighbour means (see the last row of
`registry/model/discrepancies.md`), so `individual_utility` in
`src/resources/utility_functions.jl` could only receive placeholder norms
via the `N_h`, `N_theta`, `N_h_spouse` fields of `AgentPayoffParams`.

## Decision

Port the norm perception part of `calculate-utility` as a dedicated
system in `src/systems/norm_perception.jl` with `norm_global_means`,
`norm_means`, `norm_penalty`, `calculate_norm_perception!`, and
`agent_payoff_params`, storing exactly the two ODD-specified
`turtles-own` variables as the new components `NormParameter` and
`PerceptionNormDivisionOfLabor` in `src/components.jl` (initialised to
`0.0` in `get_agent`, the NetLogo numeric default). The transfer and
spouse percepts stay procedure locals, as in the ODD. Because
`generate(::HomogeneousMixing, ...)` returns an empty graph, the
global-mean branch applies to all agents under homogenous mixing, and
because `update-statistics` is not ported, the global means are computed
on demand from `old-*` values in `norm_global_means` (equal to the lagged
means NetLogo reads during `calculate-utility`). The system stores the
penalty computed from the committed current state; counterfactual
overwriting inside the labour solver (ODD quirk 11) is deferred until
`choose-bundle` is wired. `agent_payoff_params` bridges the percepts into
`AgentPayoffParams` so `individual_utility` receives network-based norms;
`src/systems/household_bargaining.jl` is left untouched.

## Consequences

`calculate_norm_perception!` gives every agent stored, inspectable norms
matching NetLogo semantics for linked, isolated, and homogenous-mixing
cases. `NormParameter` holds the committed-state penalty rather than the
last-counterfactual value of ODD quirk 11; this deviation is accepted
until the solver wiring reintroduces counterfactual calls. Follow-up work:
wire `agent_payoff_params` into `choose-bundles` (the `set-theta` /
`calculate-payoff` transfer stage), then revisit whether quirk 11
behaviour must be replicated.
