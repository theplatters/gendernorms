# Dummy model binding proving the run pipeline core is model-agnostic
# (see `ADR-0012`). Implements all six `AbstractModel` hooks with a
# one-dimensional state, registers as `"dummy"` in `MODEL_REGISTRY`,
# and provides a `RecordingLogger`, a `ThrowingMetricsLogger` whose
# `metrics_recorded!` hook throws, plus a valid raw specification
# builder shared by the `test_run_*.jl` suites.

using Ark
using GenderNorms
using Random
using Test

const GN = GenderNorms

struct DummyState
    value::Float64
end

struct DummyConfig
    fail_at::Int
    scale::Float64
end

struct DummyModel <: GN.AbstractModel end

function GN.model_name(::Type{DummyModel})::String
    return "dummy"
end

function GN.parse_model_config(::Type{DummyModel}, raw::Dict{String, Any})
    problems = String[]
    append!(problems, GN._key_problems(raw, ("fail_at", "scale"), "model"))
    fail_at = -1
    if haskey(raw, "fail_at")
        if raw["fail_at"] isa Bool || !(raw["fail_at"] isa Integer)
            push!(problems, "[model.fail_at] must be an integer, got $(repr(raw["fail_at"]))")
        else
            fail_at = Int(raw["fail_at"])
        end
    end
    scale = 1.0
    if haskey(raw, "scale")
        if raw["scale"] isa Bool || !(raw["scale"] isa Number)
            push!(problems, "[model.scale] must be a number, got $(repr(raw["scale"]))")
        else
            scale = Float64(raw["scale"])
        end
    end
    isempty(problems) || throw(GN.RunSpecError(problems))
    return DummyConfig(fail_at, scale)
end

function GN.setup_world(::Type{DummyModel}, config::DummyConfig, rng)::Ark.World
    world = Ark.World(DummyState)
    Ark.add_resource!(world, DummyState(config.scale * rand(rng)))
    return world
end

function GN.step_model!(::Type{DummyModel}, world, config::DummyConfig, tick::Int)
    tick == config.fail_at && throw(ErrorException("dummy failure at tick $tick"))
    context = Ark.get_resource(world, GN.RunContext)
    state = Ark.get_resource(world, DummyState)
    Ark.set_resource!(world, DummyState(state.value + config.scale * rand(context.rng)))
    return nothing
end

function GN.model_metrics(::Type{DummyModel})::Dict{String, Function}
    return Dict{String, Function}("value" => world -> Ark.get_resource(world, DummyState).value)
end

function GN.config_to_dict(::Type{DummyModel}, config::DummyConfig)::Dict{String, Any}
    return Dict{String, Any}("fail_at" => config.fail_at, "scale" => config.scale)
end

GN.MODEL_REGISTRY["dummy"] = DummyModel

mutable struct RecordingLogger <: GN.RunLogger
    started::Vector{GN.RunInfo}
    recorded::Vector{Tuple{Int, Dict{String, Float64}}}
    finished::Vector{GN.RunResult}
end

RecordingLogger() = RecordingLogger(GN.RunInfo[], Tuple{Int, Dict{String, Float64}}[], GN.RunResult[])

function GN.run_started!(logger::RecordingLogger, info::GN.RunInfo)
    push!(logger.started, info)
    return nothing
end

function GN.metrics_recorded!(
        logger::RecordingLogger,
        tick::Int,
        values::Dict{String, Float64},
    )
    push!(logger.recorded, (tick, copy(values)))
    return nothing
end

function GN.run_finished!(logger::RecordingLogger, result::GN.RunResult)
    push!(logger.finished, result)
    return nothing
end

struct ThrowingMetricsLogger <: GN.RunLogger end

function GN.metrics_recorded!(
        ::ThrowingMetricsLogger,
        ::Int,
        ::Dict{String, Float64},
    )
    throw(ErrorException("logger hook failure"))
end

function make_dummy_raw(;
        name = "dummy-run",
        seed = 1,
        ticks = 3,
        fail_at = -1,
        scale = 1.0,
        metrics = nothing,
        outputs = nothing,
    )
    model = Dict{String, Any}("name" => "dummy", "fail_at" => fail_at, "scale" => scale)
    logging = Dict{String, Any}()
    metrics !== nothing && (logging["metrics"] = metrics)
    outputs !== nothing && (logging["outputs"] = outputs)
    return Dict{String, Any}(
        "run" => Dict{String, Any}("name" => name, "seed" => seed),
        "model" => model,
        "runtime" => Dict{String, Any}("ticks" => ticks),
        "logging" => logging,
    )
end
