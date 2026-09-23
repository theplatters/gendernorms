# Model binding interface of the run execution pipeline (see `ADR-0012`).
#
# The pipeline core (`RunSpec`, `create_world`, `run`, `RunResult`,
# `RunLogger`) is model-agnostic: every model-specific decision is a hook
# dispatched on the model type. A binding defines a subtype of
# `AbstractModel`, implements the six hooks below, and registers the
# subtype in `MODEL_REGISTRY` under the `model.name` string used by the
# run specification.

"""
    AbstractModel

Dispatch root of the model bindings (see `ADR-0012`). A binding is a
subtype implementing the six model hooks `model_name`,
`parse_model_config`, `setup_world`, `step_model!`, `model_metrics`,
and `config_to_dict`, registered in `MODEL_REGISTRY` under its
specification name.
"""
abstract type AbstractModel end

"""
    MODEL_REGISTRY

Mapping from the run specification `model.name` string to the model
type implementing the `AbstractModel` hooks (see `ADR-0012`). Bindings
register themselves with `MODEL_REGISTRY["name"] = ModelType`;
`resolve_model` looks the type up during specification parsing and
world creation.
"""
const MODEL_REGISTRY = Dict{String,Type{<:AbstractModel}}()

"""
    resolve_model(name::AbstractString) -> Type{<:AbstractModel}

Look up the model type registered under `name` in `MODEL_REGISTRY`
(see `ADR-0012`). Returns the model type. Throws `ArgumentError`
listing the registered names sorted on an unregistered name.
"""
function resolve_model(name::AbstractString)
    key = string(name)
    haskey(MODEL_REGISTRY, key) && return MODEL_REGISTRY[key]
    known = join(sort(collect(keys(MODEL_REGISTRY))), ", ")
    throw(ArgumentError("unknown model name \"$key\"; registered models: $known"))
end

"""
    model_name(::Type{M})::String where {M<:AbstractModel}

Specification name of the model binding (see `ADR-0012`). Returns the
`model.name` string the binding is registered under in
`MODEL_REGISTRY`. The generic fallback throws `ArgumentError`; every
binding overrides it.
"""
function model_name(::Type{M})::String where {M<:AbstractModel}
    throw(ArgumentError("$M does not implement model_name"))
end

"""
    parse_model_config(::Type{M}, raw::Dict{String,Any}) where {M<:AbstractModel}

Validate the model-specific keys of the `[model]` specification table
(see `ADR-0012`). Takes the model type and the raw `[model]` keys
without `name`. Returns the validated model-specific configuration.
Throws `RunSpecError` aggregating one problem line per invalid key,
with paths prefixed `[model`, on invalid input. The generic fallback
throws `ArgumentError`; every binding overrides it.
"""
function parse_model_config(::Type{M}, raw::Dict{String,Any}) where {M<:AbstractModel}
    throw(ArgumentError("$M does not implement parse_model_config"))
end

"""
    setup_world(::Type{M}, config, rng)::Ark.World where {M<:AbstractModel}

Construct and fully initialize a runnable world for the model binding
(see `ADR-0012`). Named after the NetLogo `setup` phase. Takes the
model type, the validated configuration from `parse_model_config`,
and the seeded run RNG, and returns the initialized `Ark.World`. The
generic fallback throws `ArgumentError`; every binding overrides it.
"""
function setup_world(::Type{M}, config, rng)::Ark.World where {M<:AbstractModel}
    throw(ArgumentError("$M does not implement setup_world"))
end

"""
    step_model!(::Type{M}, world, config, tick::Int) where {M<:AbstractModel}

Execute one tick of the model binding (see `ADR-0012`). Takes the
model type, the world, the validated configuration, and the tick
count, which counts like the NetLogo `ticks` reporter at `go` entry:
the first call sees 0. Returns nothing. The generic fallback throws
`ArgumentError`; every binding overrides it.
"""
function step_model!(::Type{M}, world, config, tick::Int) where {M<:AbstractModel}
    throw(ArgumentError("$M does not implement step_model!"))
end

"""
    model_metrics(::Type{M})::Dict{String,Function} where {M<:AbstractModel}

Per-tick metric functions of the model binding (see `ADR-0012`).
Returns a mapping from metric name to a function of the world
returning a `Real`. The runner evaluates the configured subset after
every tick. The generic fallback throws `ArgumentError`; every
binding overrides it.
"""
function model_metrics(::Type{M})::Dict{String,Function} where {M<:AbstractModel}
    throw(ArgumentError("$M does not implement model_metrics"))
end

"""
    config_to_dict(::Type{M}, config)::Dict{String,Any} where {M<:AbstractModel}

TOML-compatible echo of the resolved model configuration (see
`ADR-0012`). Takes the model type and the validated configuration and
returns a plain dictionary whose keys are accepted back by
`parse_model_config`, so the run record can recover the
configuration. The generic fallback throws `ArgumentError`; every
binding overrides it.
"""
function config_to_dict(::Type{M}, config)::Dict{String,Any} where {M<:AbstractModel}
    throw(ArgumentError("$M does not implement config_to_dict"))
end
