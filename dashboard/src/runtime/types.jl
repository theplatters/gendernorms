# Job and run state types of the dashboard runtime.
#
# `JobState` is the dashboard-side lifecycle of one queued, running, or
# recorded run; `RunPath` is the uniform representation of a live or
# recorded run; `JobSummary`, `PathSnapshot`, and `RecordIndex` are the
# presentation-safe views the UI layer consumes. All views carry
# independent copies of the metric data, never internal buffers.

"""
    JobState

Dashboard state of one job and its run path. Normal execution follows
`JOB_QUEUED -> JOB_STARTING -> JOB_RUNNING -> JOB_COMPLETED |
JOB_MODEL_FAILED | JOB_WORKER_FAILED`; cancellation follows
`JOB_QUEUED | JOB_RUNNING -> JOB_CANCELLING -> JOB_CANCELLED`.
`is_terminal_state` reports the terminal states.
"""
@enum JobState::UInt8 begin
    JOB_QUEUED
    JOB_STARTING
    JOB_RUNNING
    JOB_COMPLETED
    JOB_MODEL_FAILED
    JOB_WORKER_FAILED
    JOB_CANCELLING
    JOB_CANCELLED
end

"""
    is_terminal_state(state::JobState)::Bool

Report whether `state` is terminal. Takes a dashboard state and returns
true exactly for `JOB_COMPLETED`, `JOB_MODEL_FAILED`,
`JOB_WORKER_FAILED`, and `JOB_CANCELLED`, which never change again.
"""
function is_terminal_state(state::JobState)::Bool
    return state in (JOB_COMPLETED, JOB_MODEL_FAILED, JOB_WORKER_FAILED, JOB_CANCELLED)
end

"""
    RunPath

Uniform representation of one live or recorded run. Field `run_id` is
the core-generated run UUID string (empty until a live run starts),
field `name` the run label, field `seed` the run seed, field `source`
either `:live` or `:recorded`, field `state` the dashboard `JobState`,
fields `started_at` and `finished_at` the run timestamps or `nothing`,
field `ticks_requested` the tick budget, field `ticks_executed` the
completed tick count, field `error` the failure text (empty on
success), field `ticks` the recorded tick counts, field `metrics` the
per-metric value series aligned with `ticks`, field `spec` the optional
validated `GenderNorms.RunSpec` (nothing when the specification is
missing or invalid), field `spec_problems` the specification
diagnostics, field `diagnostics` the record-structure diagnostics, field
`record_path` the `run.toml` location (empty when unrecorded), and field
`revision` the data revision (bumped whenever the run manager replaces
the path's data, so stale chart caches can tell identical shapes
apart). Cloning a run requires `spec`; visualization works without it.
"""
mutable struct RunPath
    run_id::String
    name::String
    seed::Int
    source::Symbol
    state::JobState
    started_at::Union{Nothing, Dates.DateTime}
    finished_at::Union{Nothing, Dates.DateTime}
    ticks_requested::Int
    ticks_executed::Int
    error::String
    ticks::Vector{Int}
    metrics::Dict{String, Vector{Float64}}
    spec::Union{Nothing, GN.RunSpec}
    spec_problems::Vector{String}
    diagnostics::Vector{String}
    record_path::String
    revision::Int
end

"""
    RunPath(; keywords...)

Construct a `RunPath` with defaulted fields. Every `RunPath` field is
accepted as a keyword with the empty or zero default stated in the
`RunPath` docstring. Returns the constructed run path.
"""
function RunPath(;
        run_id::AbstractString = "",
        name::AbstractString = "",
        seed::Integer = 0,
        source::Symbol = :live,
        state::JobState = JOB_QUEUED,
        started_at::Union{Nothing, Dates.DateTime} = nothing,
        finished_at::Union{Nothing, Dates.DateTime} = nothing,
        ticks_requested::Integer = 0,
        ticks_executed::Integer = 0,
        error::AbstractString = "",
        ticks::Vector{Int} = Int[],
        metrics::Dict{String, Vector{Float64}} = Dict{String, Vector{Float64}}(),
        spec::Union{Nothing, GN.RunSpec} = nothing,
        spec_problems::Vector{String} = String[],
        diagnostics::Vector{String} = String[],
        record_path::AbstractString = "",
        revision::Integer = 0,
    )
    return RunPath(
        String(run_id),
        String(name),
        Int(seed),
        source,
        state,
        started_at,
        finished_at,
        Int(ticks_requested),
        Int(ticks_executed),
        String(error),
        ticks,
        metrics,
        spec,
        spec_problems,
        diagnostics,
        String(record_path),
        Int(revision),
    )
end

"""
    copy_path(path::RunPath)::RunPath

Copy one run path deeply. Takes the run path and returns a new
`RunPath` whose tick and metric vectors are fresh copies, so callers
can mutate the result without touching the original.
"""
function copy_path(path::RunPath)::RunPath
    metrics = Dict{String, Vector{Float64}}(name => copy(values) for (name, values) in path.metrics)
    return RunPath(
        run_id = path.run_id,
        name = path.name,
        seed = path.seed,
        source = path.source,
        state = path.state,
        started_at = path.started_at,
        finished_at = path.finished_at,
        ticks_requested = path.ticks_requested,
        ticks_executed = path.ticks_executed,
        error = path.error,
        ticks = copy(path.ticks),
        metrics = metrics,
        spec = path.spec,
        spec_problems = copy(path.spec_problems),
        diagnostics = copy(path.diagnostics),
        record_path = path.record_path,
        revision = path.revision,
    )
end

"""
    JobSummary

Presentation-safe summary of one dashboard job. Field `job_id` is the
dashboard-owned job UUID, field `run_id` the core-generated run UUID
string (empty until the run starts), field `name` the run label, field
`state` the dashboard `JobState`, field `queue_position` the 1-based
position in the queue (0 when the job is not queued), and field
`progress` the fraction of received tick rows in `[0, 1]`.
"""
struct JobSummary
    job_id::UUIDs.UUID
    run_id::String
    name::String
    state::JobState
    queue_position::Int
    progress::Float64
end

"""
    PathSnapshot

Presentation-safe independent copy of one run path for the UI. Field
`run_id` identifies the run, field `name` the run label, field `source`
either `:live` or `:recorded`, field `state` the dashboard `JobState`,
field `ticks_requested` the tick budget, field `ticks_executed` the
completed tick count, field `rows_total` the number of received tick
rows, field `visible_rows` the number of rows the caller currently
shows (clamped to `rows_total`), fields `ticks` and `metrics` the
copied and possibly downsampled chart data (at most `max_points` rows,
never aliased to internal buffers), field `metric_names` the sorted
metric names, field `error` the failure text, field `diagnostics` the
record-structure diagnostics, and field `revision` the data revision of
the underlying run path (bumped whenever the run manager replaces the
path's data, so republishing can tell identical shapes apart).
"""
struct PathSnapshot
    run_id::String
    name::String
    source::Symbol
    state::JobState
    ticks_requested::Int
    ticks_executed::Int
    rows_total::Int
    visible_rows::Int
    ticks::Vector{Int}
    metrics::Dict{String, Vector{Float64}}
    metric_names::Vector{String}
    error::String
    diagnostics::Vector{String}
    revision::Int
end

"""
    RecordIndex

Catalog of discovered run records under one record root. Field `root`
is the scanned directory, field `scanned_at` the scan timestamp, field
`records` the discovered `RunPath` entries (one per `runs/<id>/run.toml`
in scan order), and field `problems` the scan-level diagnostics keyed
by path (record-level diagnostics live in `RunPath.diagnostics` and
`RunPath.spec_problems`).
"""
struct RecordIndex
    root::String
    scanned_at::Dates.DateTime
    records::Vector{RunPath}
    problems::Dict{String, Vector{String}}
end

"""
    downsample_indices(n::Integer, max_points::Integer)::Vector{Int}

Compute uniform sample indices over `1:n`. Takes the row count and the
maximum number of points and returns the strictly increasing indices,
always keeping the first and last row. Returns `collect(1:n)` when
`n <= max_points`.
"""
function downsample_indices(n::Integer, max_points::Integer)::Vector{Int}
    n <= 0 && return Int[]
    max_points <= 0 && throw(ArgumentError("max_points must be >= 1, got $max_points"))
    n <= max_points && return collect(1:Int(n))
    indices = unique(round.(Int, range(1, Int(n); length = Int(max_points))))
    return indices
end
