---
id: ADR-0007
title: Extract household components in choose_bundles
status: accepted
date: 2026-09-20
supersedes: ADR-0006
---

# ADR-0007: Extract household components in choose_bundles

## Context

`ADR-0006` made `AgentPayoffParams` a transient input of
`individual_utility`, but the world reads ended up inside
`mutual_best_response`: it fetched the two partners' components with
`Ark.get_components` and built the bundles through the `agent_payoff_params`
builder. `ADR-0001` requires systems to access entity state through
`Ark.Query`, and the household loop that gathers the components needed for
the Nash bargaining was `choose_bundles`. It iterated women with their
`Wage`, `WorkingTime`, `TransferToWoman`, `Conformism`, `PreferencePrivate`,
and `Spouse` columns, read the spouse's components, and constructed the two
`AgentPayoffParams` at the solver call. Deleting that layer moved component
access into the solver and removed the household loop from the code.

## Decision

Restore `choose_bundles(world, config, network)` in
`src/systems/household_bargaining.jl` as the Query-based extraction layer of
the household bargaining:

- It iterates women with `Ark.Query` over `Wage`, `WorkingTime`,
  `TransferToWoman`, `Conformism`, `PreferencePrivate`, and `Spouse`, reads
  the spouse's components, computes both partners' perceived norms with
  `norm_means`, and builds the two `AgentPayoffParams` at the
  `mutual_best_response` call.
- `mutual_best_response(hw_init, hm_init, theta, pw, pm, config)` is a pure
  solver again: no Ark access, and the bundles are its parameter objects.
- `agent_payoff_params` is removed. Its component reads move into
  `choose_bundles`, and its vertex lookup is inlined there as well.
- The bundles stay transient: built and consumed inside `choose_bundles`,
  never returned or stored. The future transfer stage runs inside
  `choose_bundles` and reuses the bundles across theta evaluations.

## Consequences

- Household component access is columnar and centralised in
  `choose_bundles`; `mutual_best_response` can be tested with hand-built
  bundles.
- This supersedes the `ADR-0006` rule that no function other than
  `individual_utility` may accept a bundle. `AgentPayoffParams` is now the
  parameter object of the chain `choose_bundles` -> `mutual_best_response`
  -> `individual_utility`; the no-builder, no-storage, and no-return parts
  of `ADR-0006` stay in force.
- Norm perception keeps its on-demand means from `MDR-0004`; nothing about
  the stored norm components changes.
- `choose_bundles` is not scheduled in a `go` loop yet and the transfer
  stage (`set-theta` / `calculate-payoff`) is still unported (see
  `registry/model/processes.md` and `registry/model/discrepancies.md`).

## References

- `src/systems/household_bargaining.jl`
- `src/systems/norm_perception.jl`
- `registry/code/decisions/ADR-0001-ark-ecs.md`
- `registry/model/decisions/MDR-0002-continuous-best-response-solver.md`
- `registry/model/decisions/MDR-0004-norm-perception-port.md`
