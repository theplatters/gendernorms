---
id: ADR-0001
title: Use Ark.jl entity-component-system for agent state
status: accepted
date: 2026-09-19
---

# ADR-0001: Use Ark.jl entity-component-system for agent state

## Context

The Julia port needs a home for per-agent state (gender, working time,
wages, preferences, conformism, spouse links) and for the processes that
act on it. The existing code in `src/components.jl` declares plain
structs such as `WorkingTime`, `Wage`, `PreferencePrivate`, `Conformism`,
`Spouse`, and `CurrentUtility`, while `src/systems/initialisation.jl`
and `src/systems/household_bargaining.jl` operate on an Ark world with
`Ark.new_entity!`, `Ark.Query`, `Ark.get_resource`, and related calls.
A decision is needed on whether this Ark.jl entity-component-system
pattern is the sanctioned approach.

## Decision

Use Ark.jl entity-component-system for agent state and systems.
Agent attributes live in `src/components.jl` as plain immutable structs
used as ECS components. Behaviour lives in `src/systems/` and queries
state via `Ark.Query`. Shared configuration and aggregate state live
as resources (see `ADR-0002`).

## Consequences

- Components stay plain structs with no behaviour; logic goes into
  systems and `src/resources/` helpers, which keeps the layering clean.
- Adding a new agent attribute means adding a component struct in
  `src/components.jl` plus the systems code that reads or writes it.
- The codebase depends on Ark.jl idioms (`Ark.World`, `Ark.Entity`,
  `Ark.Query`); contributors must follow those idioms consistently.
- Alternatives such as mutable agent structs or global dictionaries
  are rejected because they would break the layering recorded in
  `registry/code/architecture.md`.
