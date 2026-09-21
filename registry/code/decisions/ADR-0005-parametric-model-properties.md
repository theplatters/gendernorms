---
id: ADR-0005
title: Parametric ModelProperties resource
status: superseded
date: 2026-09-20
superseded_by: ADR-0010
---

# ADR-0005: Parametric ModelProperties resource

## Context

Ark 0.5.1 keys world resources by their exact concrete type: `get_resource`
does `getindex(world._resources, res_type)`, so a resource stored as
`ModelProperties{NoNetwork}` can only be retrieved with the concrete type
`ModelProperties{NoNetwork}`. `ModelProperties` in
`src/resources/properties.jl` was declared non-parametric with an abstract
`network::NetworkSpec` field so that the bare-name lookup
`Ark.get_resource(world, ModelProperties)` resolves at every access point.
That places an abstract type inside a struct: field reads lose type
stability and the concrete network specification is erased from the field
type, even though `network_graph` and the `isa HomogeneousMixing` check in
`src/systems/norm_perception.jl` dispatch on it.

## Decision

Declare `ModelProperties` as a parametric struct whose `network` field has
the concrete type parameter `T`, so no field is abstractly typed:

    Base.@kwdef struct ModelProperties{T<:NetworkSpec}
      agents_per_gender::Int64 = 400
      std_dev::Float64 = 0.2
      initial_transfer::Float64 = 0.0
      network::T = WattsStrogatz()
    end

The concrete network specification is carried in the type parameter, so
field access and runtime dispatch in `network_graph` and the
`isa HomogeneousMixing` check in `src/systems/norm_perception.jl` are fully
type stable. The systems that need the properties take the concrete
specification as an argument and fetch `ModelProperties{T}` from the world
with `T = typeof(network)`, instead of the bare `ModelProperties` name.

## Consequences

- No field is abstractly typed: the concrete network specification lives in
  the type parameter, so field reads and the dispatch in `network_graph`
  and the `isa HomogeneousMixing` check stay type stable.
- `Ark.get_resource(world, ModelProperties)` does not resolve, because Ark
  keys resources by exact type; every access point takes the concrete
  specification and retrieves `ModelProperties{T}` instead.
- No parameter default, model behaviour, or registry parameter mapping
  changes; `registry/model/parameters.md` stays valid.

## References

- `src/resources/properties.jl`
- `src/systems/initialisation.jl`
- `src/systems/norm_perception.jl`
- `registry/code/architecture.md`
