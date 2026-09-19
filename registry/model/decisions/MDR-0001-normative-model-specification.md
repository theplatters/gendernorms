---
id: MDR-0001
title: Normative model specification
status: accepted
date: 2026-09-19
---

## Context

The repository holds three descriptions of the same agent-based model that can
drift apart: an ODD-style specification in `odd_model_description.typ`, the
NetLogo reference implementation in
`gender_model_shocks_preferences.nlogox`, and the Julia port in `src/`
(package `GenderNorms`). Without an explicit precedence rule, agents and
humans cannot tell whether a NetLogo quirk or a Julia deviation is intended
behavior or a bug.

## Decision

`odd_model_description.typ` is the normative model specification.
`gender_model_shocks_preferences.nlogox` is the reference implementation and
the tiebreaker where the ODD is ambiguous. The Julia package under `src/` is
the port and must follow both. Any intentional divergence from the ODD or the
reference must be recorded as a new MDR first and reflected back into the ODD
so the two never drift silently.

## Consequences

Agents must consult the ODD before changing model behavior, and the NetLogo
procedure for ported logic. The ODD and the registry must be kept in sync:
new entities, parameters, or processes are registered in
`registry/model/entities.md`, `registry/model/parameters.md`, or
`registry/model/processes.md`, and known gaps go to
`registry/model/discrepancies.md`. Examples of divergences recorded under
this rule are `MDR-0002` and `MDR-0003`.

## References

- `odd_model_description.typ`
- `gender_model_shocks_preferences.nlogox`
- `src/GenderNorms.jl`
