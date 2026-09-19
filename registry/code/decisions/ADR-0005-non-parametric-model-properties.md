---
id: ADR-0005
title: Non-parametric ModelProperties resource
status: accepted
date: 2026-09-19
---

# ADR-0005: Non-parametric ModelProperties resource

## Context

Ark 0.5.1 keys world resources by their exact concrete type: `get_resource`
does `getindex(world._resources, res_type)`, so a resource stored as
`ModelProperties{NoNetwork}` can only be retrieved with the concrete type
`ModelProperties{NoNetwork}`. `ModelProperties` in
`src/resources/properties.jl` was declared parametric
(`ModelProperties{T<:NetworkSpec}` with `network::T`), while every access
point in `src/` (`initialize_household`, `get_agent`,
`generate_social_network`, and the norm perception system in
`src/systems/norm_perception.jl`) retrieves it with the bare name
`ModelProperties`. That lookup throws `KeyError`, so the setup path and the
norm perception system could not run; the test suite in `test/` exposed the
failure.

## Decision

Declare `ModelProperties` as a non-parametric struct whose `network` field
has the abstract type `NetworkSpec`:

    Base.@kwdef struct ModelProperties
      agents_per_gender::Int64 = 400
      std_dev::Float64 = 0.2
      initial_transfer::Float64 = 0.0
      network::NetworkSpec = WattsStrogatz()
    end

The concrete network specification is still stored in the field, so runtime
dispatch in `network_graph` and the `isa HomogeneousMixing` check in
`src/systems/norm_perception.jl` keep working.

## Consequences

- `Ark.get_resource(world, ModelProperties)` resolves for every network
  specification, unblocking `initialize_household`, `get_agent`,
  `generate_social_network`, and the norm perception system.
- The `network` field is abstractly typed, trading a small amount of type
  stability for a resource that can be looked up by its declared type; the
  field is read at setup and is not on a hot loop.
- No parameter default, model behaviour, or registry parameter mapping
  changes; `registry/model/parameters.md` stays valid.

## References

- `src/resources/properties.jl`
- `src/systems/initialisation.jl`
- `src/systems/norm_perception.jl`
- `registry/code/architecture.md`
