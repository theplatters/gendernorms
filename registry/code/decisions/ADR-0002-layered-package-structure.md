---
id: ADR-0002
title: Layered package structure with explicit include order
status: superseded
date: 2026-09-19
supersedes: ""
superseded_by: ADR-0028
---

# ADR-0002: Layered package structure with explicit include order

## Context

The module root `src/GenderNorms.jl` includes files in a fixed order:
`src/components.jl`, `src/resources/utility_functions.jl`,
`src/systems/household_bargaining.jl`, `src/resources/social_network.jl`,
`src/resources/observers.jl`, `src/resources/properties.jl`, and
`src/systems/initialisation.jl`. The files naturally fall into data
definitions, shared utilities and configuration, and model dynamics.
Without a recorded rule, new files could land in the wrong place or
introduce cycles. This record builds on `ADR-0001`.

## Decision

Adopt the layering `components` -> `resources` -> `systems` with an
explicit include order in `src/GenderNorms.jl`.

- `src/components.jl` holds ECS component structs only.
- `src/resources/` holds configuration, utility functions, network
  construction, observers, and properties.
- `src/systems/` holds initialisation and model dynamics.
- `src/GenderNorms.jl` owns the include list; `src/main.jl` stays a
  standalone entry point outside the module.

## Consequences

- Dependency direction is downward only and include cycles are forbidden,
  as stated in `registry/code/architecture.md` and
  `registry/code/conventions.md`.
- Every new `.jl` file under `src/`, except `src/main.jl`, must be added
  to the include list in layer order and registered as a row in the
  file-map table in `registry/code/architecture.md`.
- The unwired `src/resources/shock.jl` stays documented as
  `Excluded from module:` until a later decision wires it up or removes
  it; no other file may be left unwired silently.
