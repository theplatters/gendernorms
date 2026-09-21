---
id: ADR-0010
title: World-owned model properties
status: accepted
date: 2026-09-21
supersedes: ADR-0005
superseded_by: ""
---

# ADR-0010: World-owned model properties

## Context

Ark 0.5.1 keys world resources by their exact concrete type: a resource
stored as `ModelProperties{NoNetwork}` cannot be retrieved with the bare
name `ModelProperties`. `ADR-0005` therefore made every access point take
the concrete `NetworkSpec` as an argument and fetch
`ModelProperties{typeof(network)}`. The specification was threaded through
`initialize_household`, `get_agent`, `get_woman`, `get_men`,
`generate_social_network`, `calculate_norm_perception!`, and the household
bargaining loop; every caller repeated the `typeof` lookup, and a caller
that passed a specification whose type did not match the stored resource
got an opaque `KeyError`. The functions that actually dispatch on the
specification are two `network_graph` calls at setup and one
`network isa HomogeneousMixing` branch per system call; no per-agent path
reads the specification.

## Decision

Declare `ModelProperties` non-parametric and keep the specification as a
plain field, so that the world is its single carrier and every access point
resolves the resource with `Ark.get_resource(world, ModelProperties)`:

    Base.@kwdef struct ModelProperties
      agents_per_gender::Int64 = 400
      std_dev::Float64 = 0.2
      initial_transfer::Float64 = 0.0
      network::NetworkSpec = WattsStrogatz()
    end

`initialize_household`, `get_agent`, `get_woman`, `get_men`,
`generate_social_network`, `calculate_norm_perception!`, and `set_theta!`
take no specification argument; they read `properties.network` or the
concrete fields from the world's resource.

## Consequences

- No access point takes or reconstructs the specification type: the
  `network` arguments and the `typeof` lookups disappear, and a mismatched
  specification cannot be passed any more. Every system takes `(world, ...)`.
- One abstractly typed field returns: `network::NetworkSpec`. Its runtime
  cost is confined to the two `network_graph` dispatches at setup and one
  `isa HomogeneousMixing` check per system call; no per-agent path reads the
  field, so the type-stability argument that motivated `ADR-0005` does not
  apply to the call sites that exist today.
- Rejected alternatives: scanning `world._resources` keys for
  `T <: ModelProperties` reaches into Ark internals and is not constant
  cost; a parametric `SocialNetwork{T}` resource or a second
  specification-carrying resource cannot resolve under Ark's exact-type
  lookup either.
- `test/test_decision_invariants.jl` keeps this shape executable.
- This record supersedes `ADR-0005`; its type parameter and the
  specification arguments are removed from the code.

## References

- `src/resources/properties.jl`
- `src/systems/initialisation.jl`
- `src/systems/norm_perception.jl`
- `src/systems/household_bargaining.jl`
- `registry/code/decisions/ADR-0005-parametric-model-properties.md`
