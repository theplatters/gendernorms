---
id: ADR-0007
title: Extract household components in set_theta!
status: accepted
date: 2026-09-20
supersedes: ADR-0006
---

# ADR-0007: Extract household components in set_theta!

## Context

`ADR-0006` made `AgentPayoffParams` a transient input of
`individual_utility`, but the world reads ended up inside
`mutual_best_response`: it fetched the two partners' components with
`Ark.get_components` and built the bundles through the `agent_payoff_params`
builder. `ADR-0001` requires systems to access entity state through
`Ark.Query`, and the household loop that gathers the components needed for
the Nash bargaining was `choose_bundles`, renamed `set_theta!` when the
transfer stage landed. It iterated women with their
`Wage`, `WorkingTime`, `TransferToWoman`, `Conformism`, `PreferencePrivate`,
and `Spouse` columns, read the spouse's components, and constructed the two
`AgentPayoffParams` at the solver call. Deleting that layer moved component
access into the solver and removed the household loop from the code.

## Decision

Restore `set_theta!(world, config)` in
`src/systems/household_bargaining.jl` as the Query-based extraction layer of
the household bargaining:

- It iterates women with `Ark.Query` over `Wage`, `WorkingTime`,
  `TransferToWoman`, `Conformism`, `PreferencePrivate`, and `Spouse`, reads
  the spouse's components, computes both partners' perceived norms with
  `norm_means`, and builds the two `AgentPayoffParams` at the solver call
  through the `payoff_params` helper.
- `mutual_best_response(hw_init, hm_init, theta, pw, pm, config)` is a pure
  solver again: no Ark access, and the bundles are its parameter objects.
  The transfer search is the pure `bargain_transfer`, assembled from
  `outside_options`, `equilibrium_payoff`, and `nash_product`.
- `agent_payoff_params` is removed. Its component reads move into
  `set_theta!`, and its vertex lookup is replaced by one
  `Dict{Ark.Entity,Int}` per gender built at the top of the loop.
- The bundles stay transient: built and consumed inside `set_theta!`,
  never returned or stored. `set_theta!` returns `nothing`; the bargained
  state is committed to the components.
- The woman's committed values are written through the `Ark.Query` column
  views. The man is not in the women's query, so his components are written
  with `Ark.set_components!`.

## Consequences

- Household component access is columnar and centralised in
  `set_theta!`; `mutual_best_response` can be tested with hand-built
  bundles.
- This supersedes the `ADR-0006` rule that no function other than
  `individual_utility` may accept a bundle. `AgentPayoffParams` is now the
  parameter object of the chain `set_theta!` -> `mutual_best_response`
  -> `individual_utility`; the no-builder, no-storage, and no-return parts
  of `ADR-0006` stay in force.
- Norm perception keeps its on-demand means from `MDR-0004`; nothing about
  the stored norm components changes.
- `set_theta!` is not scheduled in a `go` loop yet; it runs the labour and
  transfer stages since `MDR-0005` (see `registry/model/processes.md` and
  `registry/model/discrepancies.md`).

## References

- `src/systems/household_bargaining.jl`
- `src/systems/norm_perception.jl`
- `registry/code/decisions/ADR-0001-ark-ecs.md`
- `registry/model/decisions/MDR-0002-continuous-best-response-solver.md`
- `registry/model/decisions/MDR-0004-norm-perception-port.md`
