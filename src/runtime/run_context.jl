# Per-run mutable state of the execution pipeline (see `ADR-0012`).
#
# `RunContext` is the world-owned resource carrying everything the
# runner needs beyond the model state: run identity, specification,
# model binding, metric functions, logging backends, and the seeded
# RNG stream shared by setup and future stochastic steps.

"""
    RunContext

World-owned resource carrying the mutable state of one run (see
`ADR-0012`). Field `id` is the fresh run UUID string, field `spec`
the validated specification, field `model` the resolved model type,
field `model_config` the validated model configuration, field
`metric_functions` the configured metric name to function mapping,
field `loggers` the logging backends, field `rng` the seeded
stream of the whole run (setup draws from it in `setup_world` and
future stochastic steps draw from it via
`Ark.get_resource(world, RunContext).rng`), and field `executed` whether `run` has already
consumed the world: `run` sets it before executing, so a second
`run` call throws `ArgumentError` and a failed or interrupted run
also consumes the world. Non-parametric so Ark keys it by exact
concrete type (see `ADR-0010`).
"""
mutable struct RunContext
    id::String
    spec::RunSpec
    model::DataType
    model_config::Any
    metric_functions::Dict{String,Function}
    loggers::Vector{RunLogger}
    rng::Random.AbstractRNG
    executed::Bool
end
