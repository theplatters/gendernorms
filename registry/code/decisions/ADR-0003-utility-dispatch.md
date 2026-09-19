---
id: ADR-0003
title: Utility specifications as dispatched subtypes
status: accepted
date: 2026-09-19
---

# ADR-0003: Utility specifications as dispatched subtypes

## Context

The file `src/resources/utility_functions.jl` defines an abstract type
`UtilitySpec` with the concrete subtypes `Additive`, `CES`,
`Multiplicative`, and `MultiplicativeWeighted`, plus a `UtilityConfig`
struct holding the weights `w_self`, `w_partner`, and `w_transfer`.
Payoff logic dispatches `material` on the spec subtype and routes
`individual_utility` through `config.func`. A decision is needed on
whether this dispatch-based design is the sanctioned extension pattern.

## Decision

Represent utility specifications as `UtilitySpec` subtypes and dispatch
`material` and `individual_utility` on them, with `UtilityConfig`
holding the weights. The semantic reference is the ODD section
"Material utility and conformity multiplier"; the NetLogo
`calculate-utility` logic is ported into
`src/resources/utility_functions.jl`.

## Consequences

- Adding a utility form means adding a new `UtilitySpec` subtype plus
  its `material` method, not editing conditional branches.
- Weighting behaviour stays in `UtilityConfig`, so experiments vary
  configuration rather than code paths.
- All utility changes that alter model behaviour additionally require
  an MDR in `registry/model/`, per `registry/code/conventions.md`.
- The special-case branch for `MultiplicativeWeighted` inside
  `individual_utility` is accepted as-is; any cleanup must preserve
  behaviour or record an MDR.
