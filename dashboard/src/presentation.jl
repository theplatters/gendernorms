# Presentation cursor and publish throttling of the dashboard UI layer.
#
# Execution and presentation are separate cursors: a run executes at full
# speed in its worker while the page reveals the buffered rows at a
# paced rate, so a fast run animates in about `REVEAL_FRAMES` frames
# without ever slowing the model. `PublishGate` throttles chart
# publishes to one per `PUBLISH_INTERVAL` per page and only when the
# visible data changed. This file is pure Julia on top of
# `DashboardRuntime` and holds no web or plot types.

"""
    REVEAL_FRAMES

Approximate number of presentation frames a full run animates in: 20.
Each UI update reveals at most `max(1, ceil(ticks / REVEAL_FRAMES))`
newly executed rows (see `reveal_quota`), so a 500-tick run plays back
in about 20 frames over `REVEAL_FRAMES * PUBLISH_INTERVAL` seconds.
"""
const REVEAL_FRAMES = 20

"""
    PUBLISH_INTERVAL

Minimum seconds between two chart publishes of one page: 0.1. The
presentation task polls the run manager at the same cadence.
"""
const PUBLISH_INTERVAL = 0.1

"""
    reveal_quota(ticks_requested::Integer)::Int

Rows one UI update may reveal at most. Takes the tick budget of the run
and returns `max(1, ceil(ticks_requested / REVEAL_FRAMES))`, so a run
animates in about `REVEAL_FRAMES` frames regardless of its length.
"""
function reveal_quota(ticks_requested::Integer)::Int
    ticks = max(0, Int(ticks_requested))
    return max(1, ceil(Int, ticks / REVEAL_FRAMES))
end

"""
    PresentationCursor

Presentation cursor of one run on one page. Field `run_key` is the
session-stable run identity, field `visible_rows` the number of received
rows the charts currently reveal, and field `replay` whether the run is
in replay mode (cursor restarted at zero). Execution progress is not
tracked here: `advance_cursor!` takes the available row count on every
update.
"""
mutable struct PresentationCursor
    run_key::String
    visible_rows::Int
    replay::Bool
end

"""
    PresentationCursor(run_key; rows = 0, replay = false)

Construct a presentation cursor. Takes the run key and the optional
initially visible row count and replay flag. Recorded runs start with
`rows` at the received row count (complete paths initially); live runs
start at 0 and reveal over time. Returns the cursor.
"""
function PresentationCursor(
    run_key::AbstractString;
    rows::Integer = 0,
    replay::Bool = false,
)
    return PresentationCursor(String(run_key), max(0, Int(rows)), replay)
end

"""
    advance_cursor!(cursor::PresentationCursor, rows_available::Integer, ticks_requested::Integer; snap::Bool = false)::Int

Advance one presentation cursor. Takes the cursor, the executed row
count, and the tick budget. Without `snap`, at most `reveal_quota`
newly executed rows are revealed; with `snap` (the "Jump to latest"
control) the cursor jumps to the newest row. Returns the new visible row
count, clamped to `rows_available`.
"""
function advance_cursor!(
    cursor::PresentationCursor,
    rows_available::Integer,
    ticks_requested::Integer;
    snap::Bool = false,
)
    available = max(0, Int(rows_available))
    target = snap ? available : min(available, cursor.visible_rows + reveal_quota(ticks_requested))
    cursor.visible_rows = target
    return target
end

"""
    is_lagging(cursor::PresentationCursor, rows_available::Integer)::Bool

Report whether the presentation lags execution. Takes the cursor and
the executed row count and returns true while the cursor reveals fewer
rows than are buffered.
"""
function is_lagging(cursor::PresentationCursor, rows_available::Integer)::Bool
    return cursor.visible_rows < max(0, Int(rows_available))
end

"""
    start_replay!(cursor::PresentationCursor)::Int

Restart one run in replay mode. Takes the cursor, resets it to zero
visible rows, and marks it as replaying, so the buffered rows are
revealed again at the paced rate. Returns the new visible row count.
"""
function start_replay!(cursor::PresentationCursor)::Int
    cursor.visible_rows = 0
    cursor.replay = true
    return cursor.visible_rows
end

"""
    state_label(state::DashboardRuntime.JobState)::String

Human-readable label of one dashboard state. Takes the state and
returns `"queued"`, `"starting"`, `"running"`, `"cancelling"`,
`"completed"`, `"model failed"`, `"worker failed"`, or `"cancelled"`.
"""
function state_label(state::DR.JobState)::String
    state == DR.JOB_QUEUED && return "queued"
    state == DR.JOB_STARTING && return "starting"
    state == DR.JOB_RUNNING && return "running"
    state == DR.JOB_CANCELLING && return "cancelling"
    state == DR.JOB_COMPLETED && return "completed"
    state == DR.JOB_MODEL_FAILED && return "model failed"
    state == DR.JOB_WORKER_FAILED && return "worker failed"
    return "cancelled"
end

"""
    status_label(state::DashboardRuntime.JobState, lagging::Bool)::String

Presentation status line of one run. Takes the dashboard state and
whether the presentation cursor lags the buffered rows, and returns
`"replaying buffered metrics"` while lagging (the cursor is still
revealing rows the model has already produced), `"running"` for a live
run whose cursor caught up, and the `state_label` otherwise.
"""
function status_label(state::DR.JobState, lagging::Bool)::String
    lagging && return "replaying buffered metrics"
    (state == DR.JOB_STARTING || state == DR.JOB_RUNNING) && return "running"
    return state_label(state)
end

"""
    PublishGate

Chart publish throttle of one page. Field `interval` is the minimum
seconds between two publishes, field `last_publish` the time of the last
publish (`-Inf` before the first), and field `last_signature` the data
signature of the last publish. `can_publish!` publishes at most once per
interval and only when the visible data changed.
"""
mutable struct PublishGate
    interval::Float64
    last_publish::Float64
    last_signature::UInt64
end

"""
    PublishGate(; interval = PUBLISH_INTERVAL)

Construct a publish gate. Takes the optional minimum seconds between
publishes and returns the gate with no prior publish.
"""
function PublishGate(; interval::Real = PUBLISH_INTERVAL)
    return PublishGate(Float64(interval), -Inf, zero(UInt64))
end

"""
    can_publish!(gate::PublishGate, signature::UInt64, now::Real; force::Bool = false)::Bool

Decide whether the charts may be published. Takes the gate, the
signature of the currently visible data, and the current time. Returns
true at most once per `interval` seconds and only when the signature
changed since the last publish (or `force` is set), and records the
publish time and signature on success; otherwise returns false without
touching the gate, so a pending change publishes in a later window.
"""
function can_publish!(
    gate::PublishGate,
    signature::UInt64,
    now::Real;
    force::Bool = false,
)
    now - gate.last_publish < gate.interval && return false
    (!force && signature == gate.last_signature) && return false
    gate.last_publish = Float64(now)
    gate.last_signature = signature
    return true
end
