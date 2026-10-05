# Logging sinks of the run execution pipeline (see `ADR-0012`).
#
# Backends implement the `RunLogger` hooks `run_started!`,
# `metrics_recorded!`, and `run_finished!`, which default to no-ops so
# the core loop never changes when backends are added. New backends
# add `validate_output_spec`/`build_logger` methods dispatching on
# `Val{Symbol(type)}` plus a `LOG_OUTPUT_TYPES` entry. `TomlLogger`
# writes one `run.toml` record per run.

"""
    RunLogger

Abstract sink interface of the run logging backends (see `ADR-0012`).
Backends subtype it and override only the hooks they need; the
runner calls `run_started!` once, `metrics_recorded!` after every
executed tick, and `run_finished!` once with the `RunResult`.
"""
abstract type RunLogger end

"""
    run_started!(logger::RunLogger, info::RunInfo)

Notify a logging backend that a run began (see `ADR-0012`). Takes the
logger and the `RunInfo` description. The generic fallback is a
no-op; backends override it. Returns nothing.
"""
function run_started!(logger::RunLogger, info::RunInfo)
    return nothing
end

"""
    metrics_recorded!(logger::RunLogger, tick::Int, values::Dict{String,Float64})

Notify a logging backend of one executed tick (see `ADR-0012`).
Takes the logger, the tick count, and the evaluated metric values.
The generic fallback is a no-op; backends override it. Returns
nothing.
"""
function metrics_recorded!(logger::RunLogger, tick::Int, values::Dict{String, Float64})
    return nothing
end

"""
    run_finished!(logger::RunLogger, result::RunResult)

Notify a logging backend that a run finished (see `ADR-0012`). Takes
the logger and the finished `RunResult`. The generic fallback is a
no-op; backends override it. Returns nothing.
"""
function run_finished!(logger::RunLogger, result::RunResult)
    return nothing
end

"""
    LOG_OUTPUT_TYPES

Registered logging output backend names of the run specification
(see `ADR-0012`). Each entry dispatches one `validate_output_spec`
and one `build_logger` method on `Val{Symbol(type)}`. New backends
extend the tuple alongside their methods.
"""
const LOG_OUTPUT_TYPES = ("toml",)

"""
    validate_output_spec(output::OutputSpec, path::String)::Vector{String}

Validate the arguments of one logging output backend (see
`ADR-0012`). Takes the `OutputSpec` and the key path of its
`[[logging.outputs]]` entry (for example `"[logging.outputs[2]]"`)
used in the problem lines, and dispatches on
`Val{Symbol(output.type)}`. Returns the problem lines, which
`parse_spec` merges into the aggregated `RunSpecError`.
"""
function validate_output_spec(output::OutputSpec, path::String)::Vector{String}
    return validate_output_spec(output, Val(Symbol(output.type)), path)
end

function validate_output_spec(output::OutputSpec, ::Val, path::String)::Vector{String}
    return [
        "$path unknown output type \"$(output.type)\" (known: $(join(LOG_OUTPUT_TYPES, ", ")))",
    ]
end

function validate_output_spec(output::OutputSpec, ::Val{:toml}, path::String)::Vector{String}
    problems = _key_problems(output.args, ("directory",), path[2:(end - 1)])
    if haskey(output.args, "directory") && !(output.args["directory"] isa String)
        push!(
            problems,
            "$path output \"directory\" must be a string, got $(repr(output.args["directory"]))",
        )
    end
    return problems
end

"""
    build_logger(output::OutputSpec)::RunLogger

Build the logging backend selected by one specification output (see
`ADR-0012`). Takes the validated `OutputSpec` and dispatches on
`Val{Symbol(output.type)}`. Returns the constructed `RunLogger`.
"""
function build_logger(output::OutputSpec)::RunLogger
    return build_logger(output, Val(Symbol(output.type)))
end

function build_logger(output::OutputSpec, ::Val)
    throw(ArgumentError("unknown output type \"$(output.type)\""))
end

function build_logger(output::OutputSpec, ::Val{:toml})::RunLogger
    return TomlLogger(get(output.args, "directory", "runs"))
end

"""
    TomlLogger <: RunLogger

File logging backend writing one TOML record per run (see `ADR-0012`).
Field `directory` is the record root and field `rows` the buffered
`(tick, values)` metric rows. The buffer starts empty and
`run_finished!` writes `<directory>/<run-id>/run.toml`, then clears
it.
"""
mutable struct TomlLogger <: RunLogger
    directory::String
    rows::Vector{Tuple{Int, Dict{String, Float64}}}
end

"""
    TomlLogger(directory::AbstractString = "runs")

Construct a TOML file logging backend (see `ADR-0012`). Takes the
record root directory and returns the logger with an empty buffer.
"""
function TomlLogger(directory::AbstractString = "runs")
    return TomlLogger(string(directory), Tuple{Int, Dict{String, Float64}}[])
end

function metrics_recorded!(logger::TomlLogger, tick::Int, values::Dict{String, Float64})
    push!(logger.rows, (tick, copy(values)))
    return nothing
end

function run_finished!(logger::TomlLogger, result::RunResult)
    _write_run_record(logger, result)
    empty!(logger.rows)
    return nothing
end

"""
    _write_run_record(logger::TomlLogger, result::RunResult)

Write the TOML record of a finished run (see `ADR-0012`). Takes the
logger and the `RunResult`, creates
`<directory>/<result.id>/run.toml` with `mkpath`, and writes the
`[run]`, `[spec]`, and `[metrics]` tables: run identity, model name,
status, seed, ISO-8601 timestamps, ticks executed, failure error,
the `spec_to_dict` echo of the specification, and the per-tick
metric series from the buffered rows. Returns nothing.
"""
function _write_run_record(logger::TomlLogger, result::RunResult)
    path = joinpath(logger.directory, result.id, "run.toml")
    mkpath(dirname(path))
    status = result.status == RUN_SUCCESS ? "success" : "failure"
    run_table = Dict{String, Any}(
        "id" => result.id,
        "name" => result.name,
        "model" => result.model_name,
        "status" => status,
        "seed" => result.spec.seed,
        "started_at" => Dates.format(result.started_at, Dates.ISODateTimeFormat),
        "finished_at" => Dates.format(result.finished_at, Dates.ISODateTimeFormat),
        "ticks_executed" => result.ticks_executed,
    )
    if result.error !== nothing
        run_table["error"] = "$(typeof(result.error)): $(sprint(showerror, result.error))"
    end
    metric_table = Dict{String, Any}("tick" => [tick for (tick, _) in logger.rows])
    for name in result.spec.logging.metrics
        metric_table[name] = [values[name] for (_, values) in logger.rows if haskey(values, name)]
    end
    record = Dict{String, Any}(
        "run" => run_table,
        "spec" => spec_to_dict(result.spec),
        "metrics" => metric_table,
    )
    open(path, "w") do io
        TOML.print(io, record)
    end
    return nothing
end
