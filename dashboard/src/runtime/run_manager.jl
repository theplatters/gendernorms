# Run manager of the dashboard runtime.
#
# `RunManager` owns the FIFO job queue (one executing run globally),
# spawns and supervises worker processes, streams their protocol
# messages into live run paths, cancels queued and active jobs,
# promotes staged run records, and exposes presentation-safe snapshots.
# Supervision is failure-safe end to end: corrupt protocol streams
# terminate their worker with bounded escalation, spawn and finalization
# errors end the job as `JOB_WORKER_FAILED`, and the executing slot is
# always cleared so the queue always advances. A worker process runs
# `julia --project=<dashboard> --threads=<n>,1 bin/run_worker.jl` with
# the job options on `argv` and the spec dict on stdin; the model runs
# on the default thread pool and the stream writer on the interactive
# pool.

"""
    DASHBOARD_ROOT

Root directory of the dashboard project, resolved from this file. The
run manager spawns workers with this project and `bin/run_worker.jl`,
so the worker loads the dashboard runtime directly.
"""
const DASHBOARD_ROOT = normpath(joinpath(@__DIR__, "..", ".."))

"""
    DEFAULT_MAX_QUEUE

Default maximum number of queued dashboard jobs in a `RunManager`:
16. `enqueue!` throws `ArgumentError` when the queue is full.
"""
const DEFAULT_MAX_QUEUE = 16

"""
    CANCEL_KILL_GRACE

Seconds a cancelled worker process is given to exit after `SIGTERM`
before it is escalated to `SIGKILL`: 2.0.
"""
const CANCEL_KILL_GRACE = 2.0

"""
    TERMINAL_EXIT_GRACE

Seconds a worker process is given to exit on its own after its terminal
protocol message before the manager escalates to `SIGKILL`: 2.0. The
terminal message has been received completely at that point, so the
kill is pure teardown and never changes the recorded outcome; it bounds
how long a worker that hangs during teardown can stall finalization,
cancellation, and shutdown.
"""
const TERMINAL_EXIT_GRACE = 2.0

"""
    default_worker_threads()::Int

Default worker thread count of a `RunManager`. Takes no arguments and
returns `max(1, min(8, Sys.CPU_THREADS - 1))`, leaving one CPU for the
server process.
"""
default_worker_threads()::Int = max(1, min(8, Sys.CPU_THREADS - 1))

"""
    ManagerJob

Internal job record of a `RunManager`. Field `job_id` is the
dashboard-owned job UUID, field `spec` the enqueued
`GenderNorms.RunSpec`, field `spec_dict` its transport echo, field
`record` whether the run is recorded, field `state` the dashboard
`JobState`, field `outcome` the terminal state chosen by the worker's
terminal message (applied by `_finish_job!`, so a terminal `state`
always implies a finished worker and a promoted record), field `path`
the live `RunPath`, field `staging_dir` the job staging directory,
field `process` the worker process, field `reader` the protocol reader
task, field `err_task` the stderr capture task, and the protocol stream
tracking fields `handshake_seen`, `started_seen`, `started_run_id`,
`terminal_seen`, and `metric_names` (the identities and lifecycle of the
decoded stream, checked by `_handle_message!`; `started_seen` is tracked
separately from the run id because an empty run id is itself corrupt).
All fields are guarded by the owning manager's lock except `process`,
`reader`, and `err_task`, which are written once at spawn.
"""
mutable struct ManagerJob
    job_id::UUIDs.UUID
    spec::GN.RunSpec
    spec_dict::Dict{String, Any}
    record::Bool
    state::JobState
    outcome::Union{Nothing, JobState}
    path::RunPath
    staging_dir::String
    process::Union{Nothing, Base.Process}
    reader::Union{Nothing, Task}
    err_task::Union{Nothing, Task}
    handshake_seen::Bool
    started_seen::Bool
    started_run_id::String
    terminal_seen::Bool
    metric_names::Vector{String}
end

"""
    RunManager

Supervisor of dashboard runs. Field `runs_root` is the record root,
field `staging_root` the parent of the per-job staging directories,
field `worker_threads` the model thread count of worker processes,
field `max_queue` the maximum queued jobs, field `project` the
dashboard project workers are spawned with, field `julia` the Julia
executable, field `worker_script` the worker entry script, field `lock`
guards the mutable state below, field `jobs` the job records by UUID,
field `order` the submission order, field `queue` the FIFO of queued
jobs, field `active` the single executing job, field `paths` the run
paths by run id (live and loaded records), field `records` the cached
`RecordIndex`, field `record_cache` the shared `RecordCache`, and field
`closed` whether the manager is shut down.
"""
mutable struct RunManager
    runs_root::String
    staging_root::String
    worker_threads::Int
    max_queue::Int
    project::String
    julia::String
    worker_script::String
    lock::ReentrantLock
    jobs::Dict{UUIDs.UUID, ManagerJob}
    order::Vector{UUIDs.UUID}
    queue::Vector{ManagerJob}
    active::Union{Nothing, ManagerJob}
    paths::Dict{String, RunPath}
    records::RecordIndex
    record_cache::RecordCache
    closed::Bool
end

"""
    RunManager(; runs_root, worker_threads = default_worker_threads(), max_queue = DEFAULT_MAX_QUEUE, staging_root = joinpath(runs_root, ".dashboard-staging"), project = DASHBOARD_ROOT, julia = Base.julia_cmd().exec[1], worker_script = joinpath(project, "bin", "run_worker.jl"))

Construct a run manager. Takes the record root and the optional worker
thread count (1 to `Sys.CPU_THREADS - 1` model threads per worker),
queue capacity, staging root, dashboard project, Julia executable, and
worker script (overridable for tests). Throws `ArgumentError` on a
non-positive thread count or queue capacity. Returns the manager.
"""
function RunManager(;
        runs_root::AbstractString,
        worker_threads::Integer = default_worker_threads(),
        max_queue::Integer = DEFAULT_MAX_QUEUE,
        staging_root::AbstractString = joinpath(runs_root, ".dashboard-staging"),
        project::AbstractString = DASHBOARD_ROOT,
        julia::AbstractString = Base.julia_cmd().exec[1],
        worker_script::AbstractString = joinpath(project, "bin", "run_worker.jl"),
    )
    worker_threads >= 1 || throw(ArgumentError("worker_threads must be >= 1, got $worker_threads"))
    max_queue >= 1 || throw(ArgumentError("max_queue must be >= 1, got $max_queue"))
    return RunManager(
        String(runs_root),
        String(staging_root),
        Int(worker_threads),
        Int(max_queue),
        String(project),
        String(julia),
        String(worker_script),
        ReentrantLock(),
        Dict{UUIDs.UUID, ManagerJob}(),
        UUIDs.UUID[],
        ManagerJob[],
        nothing,
        Dict{String, RunPath}(),
        RecordIndex(String(runs_root), Dates.now(), RunPath[], Dict{String, Vector{String}}()),
        RecordCache(),
        false,
    )
end

"""
    _parse_time(text::AbstractString)

Parse one ISO-8601 timestamp of a protocol message. Takes the message
string and returns the `Dates.DateTime`, or `nothing` when the text is
not parseable. Helper of the message handlers.
"""
function _parse_time(text::AbstractString)
    return try
        Dates.DateTime(text)
    catch
        nothing
    end
end

"""
    _terminate_process!(process::Base.Process)

Terminate one worker process with bounded escalation. Takes the process,
sends `SIGTERM`, and escalates to `SIGKILL` after `CANCEL_KILL_GRACE`
seconds when the process is still alive. Never throws (a process that
already exited is left alone). Returns nothing. Helper of `cancel!`,
`_spawn_worker!`, and `_read_worker_output`.
"""
function _terminate_process!(process::Base.Process)
    try
        process_exited(process) || kill(process)
        @async begin
            sleep(CANCEL_KILL_GRACE)
            process_exited(process) || kill(process, Base.SIGKILL)
        end
    catch
        # A dead or unkillable process is already out of the way.
    end
    return nothing
end

"""
    _reap_worker!(process::Base.Process)

Reap one worker process with a bounded teardown. Takes the process and
waits up to `TERMINAL_EXIT_GRACE` for its exit, escalating to `SIGKILL`
after the grace and then reaping, so a worker that hangs with its
stdout closed can never block finalization indefinitely. The kill is
pure teardown: the outcome is decided by the protocol stream, never by
process exit. Returns nothing. Helper of `_finish_job!`.
"""
function _reap_worker!(process::Base.Process)
    try
        timedwait(() -> process_exited(process), TERMINAL_EXIT_GRACE; pollint = 0.01) == :ok ||
            kill(process, Base.SIGKILL)
        wait(process)
    catch
        # A process that cannot be reaped is already dead to the manager.
    end
    return nothing
end

"""
    _spawn_worker!(manager::RunManager, job::ManagerJob)

Start the worker process of one job. Takes the manager (lock held) and
the starting job, creates the staging directory for recorded runs, and
spawns `julia --project=<project> --threads=<n>,1 bin/run_worker.jl`
with the job options on `argv` and the spec dict on stdin. The protocol
reader and stderr capture tasks start only after the job input is
written, so a failed spawn can never leave a half-supervised worker.
Throws on any I/O failure after terminating and reaping whatever was
already created and closing every pipe. Returns nothing.
"""
function _spawn_worker!(manager::RunManager, job::ManagerJob)
    cmd = `$(manager.julia) --startup-file=no --project=$(manager.project) --threads=$(manager.worker_threads),1 $(manager.worker_script) --job-id=$(string(job.job_id)) --staging-dir=$(job.staging_dir) --record=$(job.record)`
    input = Pipe()
    output = Pipe()
    errors = Pipe()
    process = nothing
    try
        job.record && mkpath(job.staging_dir)
        process = run(pipeline(ignorestatus(cmd); stdin = input, stdout = output, stderr = errors); wait = false)
        close(input.out)
        close(output.in)
        close(errors.in)
        write(input, JSON.json(job.spec_dict))
        close(input)
        job.process = process
        job.err_task = @async read(errors, String)
        job.reader = @async _read_worker_output(manager, job, output)
    catch
        if process !== nothing
            try
                process_exited(process) || kill(process, Base.SIGKILL)
            catch
                # The escalation below reaps whatever state it is in.
            end
            try
                wait(process)
            catch
                # Reaping is best effort; the job is aborted either way.
            end
        end
        for pipe in (input, output, errors)
            try
                close(pipe)
            catch
                # A pipe that was never linked cannot be closed; it is dropped.
            end
        end
        rethrow()
    end
    return nothing
end

"""
    _abort_start!(manager::RunManager, job::ManagerJob, failure)

Finalize a job whose worker could not be spawned. Takes the manager
(lock held), the job, and the spawn failure; any process or pipe the
failed spawn left behind is already cleaned up by `_spawn_worker!`. The
job becomes `JOB_WORKER_FAILED` with the failure text, its staging
directory is cleaned, and the active slot is cleared. Returns nothing.
Helper of `_start_next!`.
"""
function _abort_start!(manager::RunManager, job::ManagerJob, failure)
    job.state = JOB_WORKER_FAILED
    job.path.state = JOB_WORKER_FAILED
    job.path.error = "[spawn] $(sprint(showerror, failure))"
    job.path.finished_at === nothing && (job.path.finished_at = Dates.now())
    _cleanup_job_dir!(job)
    manager.active === job && (manager.active = nothing)
    return nothing
end

"""
    _start_next!(manager::RunManager)

Start the next queued job when no run executes. Takes the manager
(lock held) and pops the FIFO head into the executing slot, spawning
its worker. A failed spawn finalizes that job with `_abort_start!` and
tries the next queued job, so spawn failures can never strand the
executing slot. Does nothing while a run executes, while the queue is
empty, or after shutdown. Returns nothing.
"""
function _start_next!(manager::RunManager)
    while !manager.closed && manager.active === nothing && !isempty(manager.queue)
        job = popfirst!(manager.queue)
        job.state = JOB_STARTING
        job.path.state = JOB_STARTING
        manager.active = job
        failure = try
            _spawn_worker!(manager, job)
            nothing
        catch caught
            caught
        end
        failure === nothing && return nothing
        _abort_start!(manager, job, failure)
    end
    return nothing
end

"""
    _apply_started!(manager::RunManager, job::ManagerJob, msg::Dict{String,Any})

Apply a `started` message to a job. Takes the manager (lock held), the
job, and the decoded message, registers the run id in `manager.paths`,
initializes the declared metric series, and moves the job to
`JOB_RUNNING`. Returns nothing.
"""
function _apply_started!(manager::RunManager, job::ManagerJob, msg::Dict{String, Any})
    job.state == JOB_CANCELLING && return nothing
    path = job.path
    path.run_id = msg["run_id"]
    path.name = msg["name"]
    path.started_at = _parse_time(msg["started_at"])
    path.ticks_requested = msg["ticks_requested"]
    for name in msg["metric_names"]
        get!(path.metrics, name, Float64[])
    end
    job.state = JOB_RUNNING
    path.state = JOB_RUNNING
    manager.paths[path.run_id] = path
    return nothing
end

"""
    _apply_rows!(job::ManagerJob, msg::Dict{String,Any})

Apply a `rows` message to a job. Takes the job (lock held) and the
decoded message and appends the tick rows to the live run path,
keeping the received metrics of a cancelling run. Returns nothing.
"""
function _apply_rows!(job::ManagerJob, msg::Dict{String, Any})
    path = job.path
    append!(path.ticks, msg["ticks"])
    for (name, values) in msg["metrics"]
        append!(get!(path.metrics, name, Float64[]), values)
    end
    path.ticks_executed = length(path.ticks)
    return nothing
end

"""
    _check_stream_message!(job::ManagerJob, msg::Dict{String,Any})

Validate one decoded message against the job's protocol stream state.
Takes the job (lock held) and the decoded message and throws
`ProtocolError` when the stream is corrupt: any message after a
terminal message or before the `handshake`, a duplicate `handshake` or
`started`, a `handshake` job id that is not this job's id, a `started`
run id that is not a nonempty UUID, `rows` before `started`, with metric
names other than the started ones, or with tick counts that are not
strictly increasing past the previously received ones, a `finished`
before `started`, with a run id other than the started one, or with a
`ticks_executed` other than the received row count, and a `cancelled`
run id inconsistent with the started run. Returns nothing. Helper of
`_handle_message!`.
"""
function _check_stream_message!(job::ManagerJob, msg::Dict{String, Any})
    kind = msg["type"]
    job.terminal_seen &&
        throw(ProtocolError(["[message] \"$kind\" received after a terminal message"]))
    if kind == "handshake"
        job.handshake_seen && throw(ProtocolError(["[handshake] duplicate handshake message"]))
        msg["job_id"] == string(job.job_id) || throw(
            ProtocolError(
                [
                    "[handshake] job id $(repr(msg["job_id"])) does not match job $(repr(string(job.job_id)))",
                ]
            )
        )
        return nothing
    end
    job.handshake_seen || throw(ProtocolError(["[message] \"$kind\" received before the handshake"]))
    if kind == "started"
        job.started_seen && throw(ProtocolError(["[started] duplicate started message"]))
        run_id = msg["run_id"]
        (isempty(run_id) || tryparse(UUIDs.UUID, run_id) === nothing) && throw(
            ProtocolError(
                [
                    "[started] run id must be a nonempty UUID, got $(repr(run_id))",
                ]
            )
        )
    elseif kind == "rows"
        job.started_seen || throw(ProtocolError(["[rows] received before the started message"]))
        ticks = msg["ticks"]
        for i in 2:length(ticks)
            ticks[i - 1] < ticks[i] || throw(
                ProtocolError(
                    [
                        "[rows] ticks must be strictly increasing, got $(repr(ticks))",
                    ]
                )
            )
        end
        if !isempty(ticks)
            previous = job.path.ticks
            (isempty(previous) || previous[end] < ticks[1]) || throw(
                ProtocolError(
                    [
                        "[rows] tick $(ticks[1]) does not continue after tick $(previous[end])",
                    ]
                )
            )
            declared = Set(job.metric_names)
            received = Set(String[String(name) for name in keys(msg["metrics"])])
            received == declared || throw(
                ProtocolError(
                    [
                        "[rows] metric names $(join(sort!(collect(received)), ", ")) do not match the " *
                            "started metric names $(join(sort!(collect(declared)), ", "))",
                    ]
                )
            )
        end
    elseif kind == "finished"
        job.started_seen || throw(ProtocolError(["[finished] received before the started message"]))
        msg["run_id"] == job.started_run_id || throw(
            ProtocolError(
                [
                    "[finished] run id $(repr(msg["run_id"])) does not match the started run id " *
                        "$(repr(job.started_run_id))",
                ]
            )
        )
        msg["ticks_executed"] == length(job.path.ticks) || throw(
            ProtocolError(
                [
                    "[finished] ticks_executed is $(msg["ticks_executed"]) but " *
                        "$(length(job.path.ticks)) rows were received",
                ]
            )
        )
    elseif kind == "cancelled"
        expected = job.started_seen ? job.started_run_id : ""
        msg["run_id"] == expected || throw(
            ProtocolError(
                [
                    "[cancelled] run id $(repr(msg["run_id"])) does not match the started run id " *
                        "$(repr(expected))",
                ]
            )
        )
    end
    return nothing
end

"""
    _arm_terminal_teardown!(job::ManagerJob)

Bound the teardown of a worker that sent its terminal protocol message.
Takes the job and, when a worker process exists, schedules the
`TERMINAL_EXIT_GRACE` kill. The stream is completely received at that
point, so the `SIGKILL` is pure teardown: the recorded outcome and
record promotion are unaffected, but a worker that hangs during
teardown can no longer stall finalization, cancellation, or shutdown.
Returns nothing. Helper of `_handle_message!`.
"""
function _arm_terminal_teardown!(job::ManagerJob)
    process = job.process
    process === nothing && return nothing
    @async begin
        sleep(TERMINAL_EXIT_GRACE)
        try
            process_exited(process) || kill(process, Base.SIGKILL)
        catch
            # The worker already exited; nothing left to tear down.
        end
    end
    return nothing
end

"""
    _handle_message!(manager::RunManager, job::ManagerJob, msg::Dict{String,Any})

Apply one decoded protocol message to a job. Takes the manager (lock
held), the job, and the decoded message. `_check_stream_message!`
validates the stream identities and lifecycle first (a corrupt stream
throws `ProtocolError` and fails the job). Terminal messages record
their outcome in `ManagerJob.outcome` and their error text and
timestamps on the run path and arm the bounded terminal teardown, but
the job state changes only in `_finish_job!`; messages are ignored while
the job is cancelling (cancellation wins and the record is never
promoted). Returns nothing.
"""
function _handle_message!(manager::RunManager, job::ManagerJob, msg::Dict{String, Any})
    kind = msg["type"]
    lock(manager.lock) do
        _check_stream_message!(job, msg)
        if kind == "handshake"
            job.handshake_seen = true
        elseif kind == "started"
            job.started_seen = true
            job.started_run_id = msg["run_id"]
            job.metric_names = copy(msg["metric_names"])
            _apply_started!(manager, job, msg)
        elseif kind == "rows"
            _apply_rows!(job, msg)
        elseif kind == "cancelled"
            job.terminal_seen = true
            _arm_terminal_teardown!(job)
            if job.state != JOB_CANCELLING && job.outcome === nothing
                job.outcome = JOB_CANCELLED
            end
        elseif kind == "finished"
            job.terminal_seen = true
            _arm_terminal_teardown!(job)
            (job.state == JOB_CANCELLING || job.outcome !== nothing) && return nothing
            job.outcome = msg["outcome"] == "success" ? JOB_COMPLETED : JOB_MODEL_FAILED
            job.path.ticks_executed = msg["ticks_executed"]
            job.path.error = msg["error"]
            job.path.finished_at = _parse_time(msg["finished_at"])
        elseif kind == "failed"
            job.terminal_seen = true
            _arm_terminal_teardown!(job)
            (job.state == JOB_CANCELLING || job.outcome !== nothing) && return nothing
            job.outcome = JOB_WORKER_FAILED
            stage = msg["stage"]
            job.path.error = isempty(stage) ? msg["error"] : "[$stage] $(msg["error"])"
        end
        return nothing
    end
    return nothing
end

"""
    _promote_job!(manager::RunManager, job::ManagerJob)

Promote the staged record of a finished job. Takes the manager (lock
held) and the job. Runs only for recorded jobs that completed or
recorded a model failure; the staged run directory is validated and
promoted with `promote_record!`. On success the promoted `run.toml`
path becomes `record_path`. On failure the problem lines (or the caught
I/O error) are appended to the run path diagnostics and the job becomes
`JOB_WORKER_FAILED`, since a recorded job that cannot deliver its
record failed its infrastructure contract. Returns nothing.
"""
function _promote_job!(manager::RunManager, job::ManagerJob)
    job.record || return nothing
    job.state in (JOB_COMPLETED, JOB_MODEL_FAILED) || return nothing
    isempty(job.path.run_id) && return nothing
    result = try
        promote_record!(
            joinpath(job.staging_dir, job.path.run_id),
            manager.runs_root;
            diagnostics = job.path.diagnostics,
        )
    catch err
        ["[record] promotion failed: $(sprint(showerror, err))"]
    end
    if result isa String
        job.path.record_path = result
    else
        append!(job.path.diagnostics, result)
        job.state = JOB_WORKER_FAILED
        text = "record promotion failed"
        isempty(job.path.error) || (text = job.path.error * "; " * text)
        job.path.error = text
    end
    return nothing
end

"""
    _cleanup_job_dir!(job::ManagerJob)

Remove the empty staging directory of a job. Takes the finished job
and removes its staging directory when it holds no run record; staged
records that were never promoted stay in staging as evidence and are
invisible to `scan_records`. Returns nothing.
"""
function _cleanup_job_dir!(job::ManagerJob)
    try
        if isdir(job.staging_dir) && isempty(readdir(job.staging_dir))
            rm(job.staging_dir)
        end
    catch
        # A leftover staging directory is never worth failing the job.
    end
    return nothing
end

"""
    _finish_job!(manager::RunManager, job::ManagerJob, failure)

Finalize a job whose worker exited. Takes the manager, the job, and
the protocol or I/O failure of the reader (or `nothing`). Reaps the
worker process with the bounded `_reap_worker!` teardown and collects
its stderr, then under the lock
maps a cancellation onto `JOB_CANCELLED`, maps a protocol failure onto
`JOB_WORKER_FAILED` with the failure text (a corrupt stream outranks
any recorded terminal message and blocks record promotion), applies
the outcome recorded by the worker's terminal message, and maps missing
terminal messages onto `JOB_WORKER_FAILED` with the stderr tail. The
staged record is promoted for completed and model-failed runs, the
staging directory is cleaned, and the next queued job starts. Every
step is exception-safe: an unexpected finalization error also ends the
job as `JOB_WORKER_FAILED`, and the active slot is always cleared and
the queue always advances. Returns nothing.
"""
function _finish_job!(manager::RunManager, job::ManagerJob, failure)
    process = job.process
    process === nothing || _reap_worker!(process)
    stderr_text = ""
    if job.err_task !== nothing
        stderr_text = try
            fetch(job.err_task)
        catch
            ""
        end
    end
    lock(manager.lock) do
        try
            if job.state == JOB_CANCELLING
                job.state = JOB_CANCELLED
            elseif failure !== nothing
                job.state = JOB_WORKER_FAILED
                job.path.error = "[protocol] $(sprint(showerror, failure))"
            elseif job.outcome !== nothing
                job.state = job.outcome
            else
                job.state = JOB_WORKER_FAILED
                text = "worker exited without a terminal protocol message"
                tail = strip(stderr_text)
                isempty(tail) || (text *= ": " * tail)
                job.path.error = text
            end
            _promote_job!(manager, job)
        catch caught
            job.state = JOB_WORKER_FAILED
            job.path.error = "[finalize] $(sprint(showerror, caught))"
        finally
            job.path.state = job.state
            if job.path.finished_at === nothing
                job.path.finished_at = Dates.now()
            end
            _cleanup_job_dir!(job)
            manager.active === job && (manager.active = nothing)
            _start_next!(manager)
        end
    end
    return nothing
end

"""
    _terminate_worker!(job::ManagerJob, output::IO)

Terminate the worker of a corrupt protocol stream. Takes the job and
the worker stdout the reader still holds: closes the stdout pipe (so a
worker that keeps writing gets an immediate I/O error instead of
blocking forever on a full pipe) and terminates the process with the
bounded `_terminate_process!` escalation. Returns nothing. Helper of
`_read_worker_output`.
"""
function _terminate_worker!(job::ManagerJob, output::IO)
    try
        close(output)
    catch
        # The pipe may already be closed; the process kill below suffices.
    end
    process = job.process
    process === nothing || _terminate_process!(process)
    return nothing
end

"""
    _read_worker_output(manager::RunManager, job::ManagerJob, output::IO)

Read and apply the protocol stream of one worker. Takes the manager,
the job, and the worker stdout, decodes each JSONL message with
`decode_message`, and applies it with `_handle_message!`. A decode,
I/O, or stream-invariant failure ends the stream and terminates the
worker with `_terminate_worker!` so a writing worker can never deadlock
the queue on a full pipe; the failure is passed to `_finish_job!`, which
also runs on clean EOF and after every error path. Returns nothing.
Helper of `_spawn_worker!`.
"""
function _read_worker_output(manager::RunManager, job::ManagerJob, output::IO)
    failure = nothing
    try
        while !eof(output)
            line = readline(output)
            isempty(strip(line)) && continue
            msg = try
                decode_message(line)
            catch caught
                failure = caught
                break
            end
            _handle_message!(manager, job, msg)
        end
    catch caught
        failure = caught
    end
    try
        failure === nothing || _terminate_worker!(job, output)
    catch
        # Termination is best effort; finalization below never skips.
    end
    _finish_job!(manager, job, failure)
    return nothing
end

"""
    enqueue!(manager::RunManager, spec::GenderNorms.RunSpec; record::Bool = true)::UUIDs.UUID

Enqueue one run for execution. Takes the manager and the validated
spec, with `record` selecting the dashboard-managed TOML recording
(submitted logging outputs are replaced by the job staging policy).
Returns the dashboard job UUID. Throws `ArgumentError` when the
manager is shut down or the queue holds `max_queue` jobs; the job runs
next in FIFO order when it reaches the head of the queue.
"""
function enqueue!(manager::RunManager, spec::GN.RunSpec; record::Bool = true)::UUIDs.UUID
    return lock(manager.lock) do
        manager.closed && throw(ArgumentError("run manager is shut down"))
        length(manager.queue) >= manager.max_queue &&
            throw(ArgumentError("run queue is full (maximum $(manager.max_queue))"))
        job_id = UUIDs.uuid4()
        job = ManagerJob(
            job_id,
            spec,
            GN.spec_to_dict(spec),
            record,
            JOB_QUEUED,
            nothing,
            RunPath(
                name = spec.name,
                seed = spec.seed,
                source = :live,
                state = JOB_QUEUED,
                ticks_requested = spec.runtime.ticks,
            ),
            joinpath(manager.staging_root, string(job_id)),
            nothing,
            nothing,
            nothing,
            false,
            false,
            "",
            false,
            String[],
        )
        manager.jobs[job_id] = job
        push!(manager.order, job_id)
        push!(manager.queue, job)
        manager.paths[string(job_id)] = job.path
        _start_next!(manager)
        job_id
    end
end

"""
    cancel!(manager::RunManager, job_id::UUIDs.UUID)::Bool

Cancel one dashboard job. Takes the manager and the job UUID. A
queued job is removed from the queue and cancelled immediately; an
executing job moves to `JOB_CANCELLING`, its worker process is
terminated with `SIGTERM`, and after `CANCEL_KILL_GRACE` seconds it is
escalated to `SIGKILL`. A job whose terminal message is already
accepted keeps its recorded outcome (no reclassification) while its
lingering worker process is terminated as pure teardown, so a worker
that hangs after its terminal message can always be cancelled. Received
metrics stay on the run path as a visibly cancelled incomplete run, and
cancelled runs are never promoted. Returns true when the job existed
and is not terminal.
"""
function cancel!(manager::RunManager, job_id::UUIDs.UUID)::Bool
    return lock(manager.lock) do
        job = get(manager.jobs, job_id, nothing)
        job === nothing && return false
        is_terminal_state(job.state) && return false
        job.state == JOB_CANCELLING && return true
        if job.outcome !== nothing
            # The terminal message was accepted; only the worker teardown is
            # left. Terminate a lingering worker without reclassifying the
            # recorded outcome.
            process = job.process
            process === nothing || _terminate_process!(process)
            return true
        end
        if job.state == JOB_QUEUED
            job.state = JOB_CANCELLED
            job.path.state = JOB_CANCELLED
            job.path.finished_at = Dates.now()
            filter!(candidate -> candidate !== job, manager.queue)
            return true
        end
        job.state = JOB_CANCELLING
        job.path.state = JOB_CANCELLING
        process = job.process
        process === nothing || _terminate_process!(process)
        return true
    end
end

"""
    job_summaries(manager::RunManager)::Vector{JobSummary}

Summarize every dashboard job. Takes the manager and returns one
`JobSummary` per submitted job in submission order, with the queue
position of queued jobs (0 otherwise) and the received-row progress.
"""
function job_summaries(manager::RunManager)::Vector{JobSummary}
    return lock(manager.lock) do
        positions = Dict{UUIDs.UUID, Int}(job.job_id => i for (i, job) in enumerate(manager.queue))
        summaries = JobSummary[]
        for job_id in manager.order
            job = manager.jobs[job_id]
            rows = length(job.path.ticks)
            progress =
                job.path.ticks_requested > 0 ? min(1.0, rows / job.path.ticks_requested) : 0.0
            push!(
                summaries,
                JobSummary(
                    job.job_id,
                    job.path.run_id,
                    job.path.name,
                    job.state,
                    get(positions, job.job_id, 0),
                    progress,
                ),
            )
        end
        return summaries
    end
end

"""
    refresh_records!(manager::RunManager)::RecordIndex

Rescan the record catalog. Takes the manager and rescans
`runs_root` with the shared `RecordCache`, storing the result.
Returns the `RecordIndex`.
"""
function refresh_records!(manager::RunManager)::RecordIndex
    return lock(manager.lock) do
        manager.records = scan_records(manager.runs_root, manager.record_cache)
        return manager.records
    end
end

"""
    load_record!(manager::RunManager, run_id::AbstractString)::RunPath

Load one recorded run into the manager's run store. Takes the manager
and the run UUID and reads `runs_root/<run_id>/run.toml` with the
shared `RecordCache`. Replacing an already stored path bumps its data
`revision`, so presentation caches republish even when the new data has
the same shape. Returns an independent copy of the `RunPath`; throws
`ArgumentError` when no record exists or its id disagrees with the
requested one. After loading, `path_snapshot` works for the run.
"""
function load_record!(manager::RunManager, run_id::AbstractString)::RunPath
    return lock(manager.lock) do
        id = String(run_id)
        record_file = joinpath(manager.runs_root, id, "run.toml")
        isfile(record_file) || throw(ArgumentError("no record for run \"$id\" under $(manager.runs_root)"))
        path = read_record(record_file, manager.record_cache)
        path.run_id == id ||
            throw(ArgumentError("record at \"$record_file\" has id \"$(path.run_id)\", expected \"$id\""))
        previous = get(manager.paths, path.run_id, nothing)
        previous === nothing || (path.revision = previous.revision + 1)
        manager.paths[path.run_id] = path
        return copy_path(path)
    end
end

"""
    path_snapshot(manager::RunManager, run_id::AbstractString; visible_rows::Integer = typemax(Int), max_points::Integer = 4000)::PathSnapshot

Copy the chart data of one run for presentation. Takes the manager and
the run id (or the dashboard job id of a live job, which resolves to
the same run path), the number of rows the caller currently shows, and
the maximum number of points to return. The first `visible_rows` rows
are copied (clamped to the received rows) and downsampled uniformly to
at most `max_points` points; metric columns whose length disagrees with
the received rows are excluded so one bad column can never hide the
rest of the run, and the result never aliases internal buffers.
Throws `ArgumentError` on an unknown run id, a negative `visible_rows`,
or a `max_points` below 1. Returns the `PathSnapshot`.
"""
function path_snapshot(
        manager::RunManager,
        run_id::AbstractString;
        visible_rows::Integer = typemax(Int),
        max_points::Integer = 4000,
    )::PathSnapshot
    visible_rows >= 0 || throw(ArgumentError("visible_rows must be >= 0, got $visible_rows"))
    max_points >= 1 || throw(ArgumentError("max_points must be >= 1, got $max_points"))
    return lock(manager.lock) do
        path = get(manager.paths, String(run_id), nothing)
        path === nothing && throw(ArgumentError("unknown run id \"$(run_id)\""))
        rows_total = length(path.ticks)
        visible = min(Int(visible_rows), rows_total)
        indices = downsample_indices(visible, max_points)
        ticks = Int[path.ticks[i] for i in indices]
        aligned = Dict{String, Vector{Float64}}(
            name => values for (name, values) in path.metrics if length(values) == rows_total
        )
        metrics = Dict{String, Vector{Float64}}(
            name => Float64[values[i] for i in indices] for (name, values) in aligned
        )
        return PathSnapshot(
            path.run_id,
            path.name,
            path.source,
            path.state,
            path.ticks_requested,
            path.ticks_executed,
            rows_total,
            visible,
            ticks,
            metrics,
            sort!(collect(keys(aligned))),
            path.error,
            copy(path.diagnostics),
            path.revision,
        )
    end
end

"""
    shutdown!(manager::RunManager)

Shut a run manager down. Takes the manager, marks it closed (later
`enqueue!` calls throw), cancels every non-terminal job (terminating
every still-live worker regardless of its recorded outcome), and waits
for the executing job's protocol reader, which exits within the bounded
worker teardown. Returns nothing.
"""
function shutdown!(manager::RunManager)
    job_ids = lock(manager.lock) do
        manager.closed = true
        copy(manager.order)
    end
    for job_id in job_ids
        cancel!(manager, job_id)
    end
    reader = lock(manager.lock) do
        manager.active === nothing ? nothing : manager.active.reader
    end
    reader === nothing || wait(reader)
    return nothing
end
