# Live metric streaming of the dashboard runtime.
#
# `MetricBuffer` preallocates the per-tick columns of one run and
# publishes rows atomically; `LiveLogger` implements the
# `GenderNorms.RunLogger` hooks without ever blocking or doing I/O in
# the model loop, and `StreamWriter` polls the published rows from a
# separate task and encodes them into `rows` protocol messages. The
# runner calls the logger hooks on the run's thread only, so the buffer
# has a single writer and the atomic publication counter is its
# release-style barrier. The writer emits the `started` message from the
# logger's `RunInfo` before it ever streams rows (and holds rows back
# until `started` is on the wire), so `started` strictly precedes every
# `rows` message in the stream.

"""
    MetricBuffer

Preallocated metric rows of one run. Field `ticks` and the field
`columns` hold the row slots for the requested tick budget, field
`names` the sorted metric names (column order), and field `published`
the number of fully written rows. The runner writes row `n` completely
and then increments `published`, so readers see finished rows only and
published rows stay immutable.
"""
struct MetricBuffer
    ticks::Vector{Int}
    names::Vector{String}
    columns::Vector{Vector{Float64}}
    published::Threads.Atomic{Int}
end

"""
    MetricBuffer(names::AbstractVector{<:AbstractString}, capacity::Integer)::MetricBuffer

Construct a preallocated metric buffer. Takes the evaluated metric
names and the requested tick budget (the row capacity) and returns the
buffer with sorted names and zero-filled columns, publishing zero
rows. Throws `ArgumentError` on a negative capacity.
"""
function MetricBuffer(names::AbstractVector{<:AbstractString}, capacity::Integer)
    capacity >= 0 || throw(ArgumentError("capacity must be >= 0, got $capacity"))
    ordered = sort!(String[String(name) for name in names])
    columns = [zeros(Float64, Int(capacity)) for _ in ordered]
    return MetricBuffer(zeros(Int, Int(capacity)), ordered, columns, Threads.Atomic{Int}(0))
end

"""
    published_rows(buffer::MetricBuffer)::Int

Report how many rows of `buffer` are published. Takes the buffer and
returns its atomic publication counter.
"""
published_rows(buffer::MetricBuffer)::Int = buffer.published[]

"""
    LiveEvent

Abstract marker of the lifecycle events a `LiveLogger` forwards to its
consumers: `RunStartedEvent` and `RunFinishedEvent`.
"""
abstract type LiveEvent end

"""
    RunStartedEvent <: LiveEvent

Lifecycle event carrying the `GenderNorms.RunInfo` of a run that just
started. Field `info` holds the run description.
"""
struct RunStartedEvent <: LiveEvent
    info::GN.RunInfo
end

"""
    RunFinishedEvent <: LiveEvent

Lifecycle event carrying the `GenderNorms.RunResult` of a run that just
finished. Field `result` holds the in-memory run record.
"""
struct RunFinishedEvent <: LiveEvent
    result::GN.RunResult
end

"""
    LiveLogger

Live streaming logger of the dashboard, implementing the
`GenderNorms.RunLogger` hooks. Field `buffer` holds the preallocated
rows, field `lifecycle` the buffered channel of `LiveEvent`s consumed
by a `StreamWriter`, field `info` the `GenderNorms.RunInfo` captured at
run start, and field `finished` the `GenderNorms.RunResult` captured at
run end. `metrics_recorded!` writes one preallocated row and publishes
it atomically: no serialization, plotting, I/O, or waiting, so the
model loop is never blocked.
"""
mutable struct LiveLogger <: GN.RunLogger
    buffer::MetricBuffer
    lifecycle::Channel{Any}
    info::Union{Nothing, GN.RunInfo}
    finished::Union{Nothing, GN.RunResult}
end

"""
    LiveLogger(names::AbstractVector{<:AbstractString}, capacity::Integer)::LiveLogger

Construct a live streaming logger. Takes the evaluated metric names and
the requested tick budget and returns the logger with a fresh
`MetricBuffer` and an empty lifecycle channel of capacity 8.
"""
function LiveLogger(names::AbstractVector{<:AbstractString}, capacity::Integer)
    return LiveLogger(MetricBuffer(names, capacity), Channel{Any}(8), nothing, nothing)
end

"""
    GenderNorms.run_started!(logger::LiveLogger, info::GenderNorms.RunInfo)

Capture the start of a run in a live logger. Takes the logger and the
`RunInfo`, stores the info before any row can be published (so the
writer observes it through the row publication barrier), and forwards a
`RunStartedEvent` to the lifecycle channel. Returns nothing.
"""
function GN.run_started!(logger::LiveLogger, info::GN.RunInfo)
    logger.info = info
    put!(logger.lifecycle, RunStartedEvent(info))
    return nothing
end

"""
    GenderNorms.metrics_recorded!(logger::LiveLogger, tick::Int, values::Dict{String,Float64})

Publish one metric row without blocking the model loop. Takes the
logger, the tick count, and the metric values, writes the row into the
next preallocated buffer slot, and atomically increments the published
row count as the release-style publication barrier. Rows beyond the
requested tick budget are dropped. No serialization, plotting, I/O, or
waiting happens here. Returns nothing.
"""
function GN.metrics_recorded!(logger::LiveLogger, tick::Int, values::Dict{String, Float64})
    buffer = logger.buffer
    row = buffer.published[] + 1
    row <= length(buffer.ticks) || return nothing
    buffer.ticks[row] = tick
    for (i, name) in enumerate(buffer.names)
        buffer.columns[i][row] = get(values, name, NaN)
    end
    Threads.atomic_add!(buffer.published, 1)
    return nothing
end

"""
    GenderNorms.run_finished!(logger::LiveLogger, result::GenderNorms.RunResult)

Capture the end of a run in a live logger. Takes the logger and the
finished `RunResult`, stores the result, and forwards a
`RunFinishedEvent` to the lifecycle channel. Returns nothing.
"""
function GN.run_finished!(logger::LiveLogger, result::GN.RunResult)
    logger.finished = result
    put!(logger.lifecycle, RunFinishedEvent(result))
    return nothing
end

"""
    StreamWriter

Polling consumer of one `LiveLogger` writing JSONL protocol messages.
Field `io` receives the encoded lines, field `logger` the source, field
`cursor` the number of rows already written, field `batch_size` the
maximum rows per `rows` message, field `poll_interval` the polling
pause in seconds, field `lock` serializes writes to `io`, field
`stopped` is the atomic stop flag, field `started_sent` whether the
`started` message is already on the wire (rows never precede it), and
field `task` the polling task. The task polls on a separate thread, so
it progresses while the model thread runs `GenderNorms.run`.
"""
mutable struct StreamWriter
    io::IO
    logger::LiveLogger
    cursor::Int
    batch_size::Int
    poll_interval::Float64
    lock::ReentrantLock
    stopped::Threads.Atomic{Int}
    started_sent::Bool
    task::Union{Nothing, Task}
end

"""
    StreamWriter(io::IO, logger::LiveLogger; batch_size::Integer = 128, poll_interval::Real = 0.05)::StreamWriter

Construct a polling stream writer. Takes the output stream, the live
logger, the maximum rows per `rows` message, and the polling pause in
seconds. Returns the writer with cursor 0 and no task; call
`start_stream` to begin polling. Throws `ArgumentError` on a batch size
below 1 or a non-positive poll interval.
"""
function StreamWriter(
        io::IO,
        logger::LiveLogger;
        batch_size::Integer = 128,
        poll_interval::Real = 0.05,
    )
    batch_size >= 1 || throw(ArgumentError("batch_size must be >= 1, got $batch_size"))
    poll_interval > 0 || throw(ArgumentError("poll_interval must be > 0, got $poll_interval"))
    return StreamWriter(
        io,
        logger,
        0,
        Int(batch_size),
        Float64(poll_interval),
        ReentrantLock(),
        Threads.Atomic{Int}(0),
        false,
        nothing,
    )
end

"""
    write_message!(writer::StreamWriter, msg::AbstractDict)::Nothing

Write one encoded protocol message to the writer's stream. Takes the
writer and the message dictionary, encodes it with `encode_message`,
and writes the line under the writer lock. Returns nothing.
"""
function write_message!(writer::StreamWriter, msg::AbstractDict)
    lock(writer.lock) do
        write_message!(writer.io, msg)
    end
    return nothing
end

"""
    _emit_started!(writer::StreamWriter)::Bool

Emit the `started` message of a stream writer once, from the
`GenderNorms.RunInfo` its logger captured. Takes the writer and writes
the `started` message when the run has started and it is not yet on the
wire. Returns whether `started` is on the wire afterwards (false while
the run has not started yet). Helper of `stream_rows!` and
`_drain_lifecycle!`.
"""
function _emit_started!(writer::StreamWriter)::Bool
    writer.started_sent && return true
    info = writer.logger.info
    info === nothing && return false
    write_message!(
        writer,
        started_message(
            info.id,
            info.name,
            info.model_name,
            info.metric_names,
            Dates.format(info.started_at, Dates.ISODateTimeFormat),
            info.spec.runtime.ticks,
        ),
    )
    writer.started_sent = true
    return true
end

"""
    stream_rows!(writer::StreamWriter)::Int

Copy newly published metric rows into `rows` messages. Takes the writer
and copies every published row past the writer cursor into batches of at
most `batch_size` rows (fresh vectors, never aliased to the buffer),
encoding each batch with `encode_message`. The `started` message is
emitted before the first row batch (rows are held back until it is on
the wire), so `started` always precedes every `rows` message. Returns
the number of rows written.
"""
function stream_rows!(writer::StreamWriter)::Int
    buffer = writer.logger.buffer
    available = buffer.published[] - writer.cursor
    available <= 0 && return 0
    _emit_started!(writer) || return 0
    written = 0
    while true
        available = buffer.published[] - writer.cursor
        available <= 0 && break
        count = min(available, writer.batch_size)
        first = writer.cursor + 1
        last = writer.cursor + count
        metrics = Dict{String, Vector{Float64}}(
            name => buffer.columns[i][first:last] for (i, name) in enumerate(buffer.names)
        )
        write_message!(writer, rows_message(buffer.ticks[first:last], metrics))
        writer.cursor = last
        written += count
    end
    return written
end

"""
    _drain_lifecycle!(writer::StreamWriter)

Drain the lifecycle events of a stream writer's logger. Takes the
writer, consumes every currently queued `LiveEvent`, and emits the
`started` message (once, via `_emit_started!`) for a
`RunStartedEvent`. Returns nothing. Helper of `_stream_loop` and
`finish_stream!`.
"""
function _drain_lifecycle!(writer::StreamWriter)
    lifecycle = writer.logger.lifecycle
    while isready(lifecycle)
        event = take!(lifecycle)
        event isa RunStartedEvent && _emit_started!(writer)
    end
    return nothing
end

"""
    _stream_loop(writer::StreamWriter)

Run the polling loop of a `StreamWriter`. Drains the lifecycle channel,
copies newly published rows, and repeats until the writer is stopped,
sleeping `poll_interval` between polls. Returns nothing. Helper of
`start_stream`.
"""
function _stream_loop(writer::StreamWriter)
    while true
        _drain_lifecycle!(writer)
        stream_rows!(writer)
        writer.stopped[] == 1 && break
        sleep(writer.poll_interval)
    end
    return nothing
end

"""
    start_stream(writer::StreamWriter)::Task

Start the polling task of a stream writer. Takes the writer and spawns
its `_stream_loop` on the interactive thread pool when one exists (so
it progresses while the model thread runs), otherwise on the default
pool. Stores the task in the writer and returns it.
"""
function start_stream(writer::StreamWriter)::Task
    task = if Threads.nthreads(:interactive) > 0
        Threads.@spawn :interactive _stream_loop(writer)
    else
        Threads.@spawn _stream_loop(writer)
    end
    writer.task = task
    return task
end

"""
    finish_stream!(writer::StreamWriter)::Int

Stop a stream writer and drain all published rows. Takes the writer,
sets its stop flag, waits for the polling task, and copies any rows
published since the last poll, flushing a pending `started` message
first so terminal messages never precede it. Call it after
`GenderNorms.run` returns and before writing terminal protocol
messages. Returns the number of rows written by the final drain.
"""
function finish_stream!(writer::StreamWriter)::Int
    writer.stopped[] = 1
    if writer.task !== nothing
        wait(writer.task)
    end
    _drain_lifecycle!(writer)
    return stream_rows!(writer)
end
