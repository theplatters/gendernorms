---
id: ADR-0006
title: Construct AgentPayoffParams only at utility calls
status: superseded
date: 2026-09-20
superseded_by: ADR-0007
---

# ADR-0006: Construct AgentPayoffParams only at utility calls

## Context

`AgentPayoffParams` in `src/resources/utility_functions.jl` bundles the
per-agent inputs of `individual_utility`: own and spouse wage, material
preference, conformism, the three perceived norms, and sex. It is not model
state and has no meaning outside a single utility evaluation, yet it had
leaked into function interfaces. `mutual_best_response` in
`src/systems/household_bargaining.jl` accepted two prebuilt bundles as
parameters, `agent_payoff_params` in `src/systems/norm_perception.jl`
returned one to its callers, and the `choose_bundles` stub constructed one
that it never used. Callers therefore decided when agent state was
snapshotted, and a bundle built for one evaluation could travel into
another.

## Decision

Treat `AgentPayoffParams` strictly as a transient argument bundle:

- `individual_utility` keeps the bundle as its parameter; it is the only
  function that consumes one.
- `agent_payoff_params` remains the builder that reads the world and the
  perceived norms and returns the bundle. It may do so only for the
  `individual_utility` call made in the same scope; the bundle is never
  stored or forwarded by another function.
- A function that evaluates utility builds the bundles locally, immediately
  before the `individual_utility` call, from its own inputs.
  `mutual_best_response(world, woman, man, theta, config, network)` reads
  both partners' current working times as the solver start and builds the
  two bundles with `agent_payoff_params` in its own scope.
- No other function accepts an `AgentPayoffParams` parameter or returns one.
- The broken `choose_bundles` stub is removed. The `choose-bundle` port
  lives in `mutual_best_response` and will be scheduled together with the
  `go` loop and the transfer stage, per `registry/model/processes.md`.

## Consequences

- Bundle construction and consumption stay in one scope, so utility
  evaluations cannot reuse a stale snapshot.
- `mutual_best_response` is no longer a pure numeric solver over
  caller-supplied bundles: it depends on the world, the household entities,
  and the concrete network specification to read agent state.
- The solver start is the agents' current working time, matching NetLogo
  `choose-bundle`; the solver algorithm and tolerances of `MDR-0002` are
  unchanged.
- `agent_payoff_params` still returns a bundle, but only for the utility
  call made in the same scope; the unit test that inspects its fields
  remains valid.
- `choose_bundles` disappears from `src/`,
  `registry/code/architecture.md`, and `registry/model/processes.md`, and
  the latent runtime error recorded in
  `registry/model/discrepancies.md` is resolved by removal.

## References

- `src/resources/utility_functions.jl`
- `src/systems/household_bargaining.jl`
- `src/systems/norm_perception.jl`
- `registry/model/decisions/MDR-0002-continuous-best-response-solver.md`
- `registry/model/decisions/MDR-0004-norm-perception-port.md`
