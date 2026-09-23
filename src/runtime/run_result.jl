# Run outcome records of the execution pipeline (see `ADR-0012`).
#
# `RunInfo` describes a run at start for the logger hooks; `RunResult`
# is the in-memory record the runner collects, with a `RunStatus`
# distinguishing success from recorded failure.

"""
    RunStatus

Outcome status of a finished run (see `ADR-0012`). Either
`RUN_SUCCESS` when every tick completed or `RUN_FAILURE` when a step
or metric error stopped the run; the error is then recorded in
`RunResult.error` and never reported as success.
"""
@enum RunStatus::UInt8 RUN_SUCCESS RUN_FAILURE

"""
    RunInfo

Run description passed to `run_started!` when a run begins (see
`ADR-0012`). Field `id` is the fresh run UUID string, field `name`
the run label, field `model_name` the registered model name, field
`spec` the validated specification, field `config` the
`config_to_dict` echo of the resolved model configuration, field
`metric_names` the evaluated metric names, and field `started_at` the
run start timestamp.
"""
struct RunInfo
    id::String
    name::String
    model_name::String
    spec::RunSpec
    config::Dict{String,Any}
    metric_names::Vector{String}
    started_at::Dates.DateTime
end

"""
    RunResult

In-memory record of a finished run collected by the runner (see
`ADR-0012`). Field `id` is the fresh run UUID string, field `name`
the run label, field `spec` the validated specification, field
`model_name` the registered model name, field `config` the
`config_to_dict` echo of the resolved model configuration, field
`status` the `RunStatus` outcome, fields `started_at` and
`finished_at` the run timestamps, field `ticks_executed` the number
of completed ticks, field `error` the recorded failure or `nothing`
on success, field `ticks` the executed tick counts, and field
`metrics` the per-metric value series.
"""
struct RunResult
    id::String
    name::String
    spec::RunSpec
    model_name::String
    config::Dict{String,Any}
    status::RunStatus
    started_at::Dates.DateTime
    finished_at::Dates.DateTime
    ticks_executed::Int
    error::Union{Nothing,Exception}
    ticks::Vector{Int}
    metrics::Dict{String,Vector{Float64}}
end

"""
    is_success(result::RunResult)::Bool

Report whether a run completed every tick (see `ADR-0012`). Takes the
`RunResult` and returns true exactly when its `status` is
`RUN_SUCCESS`. Returns the status comparison.
"""
is_success(result::RunResult)::Bool = result.status == RUN_SUCCESS
