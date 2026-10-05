# Reactive Stipple model of the dashboard page.
#
# `DashboardModel` holds the configuration form (all knobs as reactive
# fields, strings throughout so the server-side parsing of
# `DashboardRuntime.build_spec_dict` stays the single coercion point),
# the job table and run log views, the plot tab strip and per-plot line
# tickboxes, the single visible chart, and the status and problem
# displays. One model instance is created per page load; `page_ready`
# attaches the run manager and starts the per-page presentation task,
# which alone writes the reactive view fields (tables, plot tabs, line
# tickboxes, and the chart). Handlers validate and enqueue, cancel,
# load records, clone configurations, and manage run and plot
# selections; they never execute model ticks.

"""
    MAX_SELECTED_RUNS

Maximum number of runs whose lines can be plotted at once: 8. Selecting
another run is refused with a status message until one is deselected.
"""
const MAX_SELECTED_RUNS = 8

"""
    MAX_PLOTS

Maximum number of plots one page session holds at once: 8. Creating
another plot is refused with a status message until one is deleted; the
last remaining plot cannot be deleted.
"""
const MAX_PLOTS = 8

"""
    RECORDS_REFRESH_INTERVAL

Seconds between two record-catalog change checks of the presentation
task: 2.0. Each check hashes the record set with
`DashboardRuntime.catalog_signature` (names, sizes, and timestamps
only) and rescans the catalog only when the set changed or a job just
reached a terminal outcome and promoted its record, so a running page
picks up completed runs within seconds without hammering the disk.
"""
const RECORDS_REFRESH_INTERVAL = 2.0

"""
    FORM_STRING_KEYS

Flat form keys carried by the reactive string fields of `DashboardModel`
(see `DashboardRuntime.build_spec_dict`). Blank values omit the key from
the submitted form. The `metrics` and `record_directory` keys are
handled separately.
"""
const FORM_STRING_KEYS = (
    "name",
    "seed",
    "ticks",
    "agents_per_gender",
    "std_dev",
    "initial_transfer",
    "initial_lambda",
    "network_type",
    "network_p",
    "network_neighbors_per_side",
    "network_rewiring",
    "network_m",
    "network_trait",
    "utility_type",
    "utility_w_self",
    "utility_w_partner",
    "utility_w_transfer",
    "utility_beta",
    "paid_time_men",
    "paid_time_women",
    "mean_wage_men",
    "mean_wage_women",
    "mean_preference_men",
    "mean_preference_women",
    "initial_conformism_men",
    "initial_conformism_women",
)

"""
    NETWORK_TYPE_OPTIONS

Options of the network type dropdown: the `network_type` keys of
`DashboardRuntime.NETWORK_PARAMS`, sorted.
"""
const NETWORK_TYPE_OPTIONS = sort!(collect(keys(DR.NETWORK_PARAMS)))

"""
    UTILITY_TYPE_OPTIONS

Options of the utility type dropdown: the `utility_type` keys of
`DashboardRuntime.UTILITY_PARAMS`, sorted.
"""
const UTILITY_TYPE_OPTIONS = sort!(collect(keys(DR.UTILITY_PARAMS)))

# Per-page reactive model. `@app` generates `abstract type DashboardModel
# <: ReactiveModel` with the concrete `DashboardModel!` and its fields:
# form knobs and views are `@in`/`@out` reactives, `manager` and
# `session` are `@private` (never synced to the browser).
@app DashboardModel begin
    @in name::String = "dashboard-run"
    @in seed::String = "0"
    @in ticks::String = "50"
    @in agents_per_gender::String = "50"
    @in metrics::Vector{String} = copy(KNOWN_METRICS)

    @in network_type::String = "watts_strogatz"
    @in network_p::String = ""
    @in network_neighbors_per_side::String = ""
    @in network_rewiring::String = ""
    @in network_m::String = ""
    @in network_trait::String = ""

    @in utility_type::String = "ces"
    @in utility_w_self::String = ""
    @in utility_w_partner::String = ""
    @in utility_w_transfer::String = ""
    @in utility_beta::String = ""

    @in std_dev::String = ""
    @in initial_transfer::String = ""
    @in initial_lambda::String = ""
    @in paid_time_men::String = ""
    @in paid_time_women::String = ""
    @in mean_wage_men::String = ""
    @in mean_wage_women::String = ""
    @in mean_preference_men::String = ""
    @in mean_preference_women::String = ""
    @in initial_conformism_men::String = ""
    @in initial_conformism_women::String = ""

    @in record_run::Bool = true

    @out problems::Vector{String} = String[]
    @out status_line::String = "ready"
    @out job_rows::Vector{Dict{String, Any}} = Dict{String, Any}[]
    @out run_rows::Vector{Dict{String, Any}} = Dict{String, Any}[]
    @out selected_runs::Vector{String} = String[]
    @out plot_tabs::Vector{Dict{String, Any}} = Dict{String, Any}[]
    @out line_groups::Vector{Dict{String, Any}} = Dict{String, Any}[]
    @out display_reduced::Bool = false
    @out data_warnings::Vector{String} = String[]
    @out axis_label::String = ""
    @out active_plot::PlotlyBase.Plot = empty_plot()

    @private manager::Any = nothing
    @private session::Any = nothing
end

"""
    JOB_SPECS

Validated `GenderNorms.RunSpec` of every submitted job, keyed by the
dashboard job UUID string. Filled by the submit handler and used for the
seed in run labels and for cloning the configuration of live runs (the
live `RunPath` carries no spec). Entries are small and follow the job
records of the run manager.
"""
const JOB_SPECS = Dict{String, GN.RunSpec}()

"""
    JOB_SPECS_LOCK

Guard of `JOB_SPECS`, shared by all page sessions of one server.
"""
const JOB_SPECS_LOCK = ReentrantLock()

"""
    register_job_spec!(job_id::UUIDs.UUID, spec::GenderNorms.RunSpec)

Record the spec of one submitted job. Takes the dashboard job UUID and
the validated spec and stores it in `JOB_SPECS`. Returns nothing.
"""
function register_job_spec!(job_id::UUIDs.UUID, spec::GN.RunSpec)
    lock(JOB_SPECS_LOCK) do
        JOB_SPECS[string(job_id)] = spec
    end
    return nothing
end

"""
    job_spec(key::AbstractString)

Look up the spec of one live run. Takes the dashboard job UUID string
and returns the registered `GenderNorms.RunSpec`, or `nothing` when the
key is unknown.
"""
function job_spec(key::AbstractString)
    return lock(JOB_SPECS_LOCK) do
        get(JOB_SPECS, String(key), nothing)
    end
end

"""
    PlotState

Selection state of one dashboard plot. Field `id` is the stable plot
number (the tab label is `"Plot <id>"`), field `lines` the selected line
keys of this plot (see `line_key`). Every plot owns its selection:
changing one plot's tickboxes never touches another plot. The line keys
of a deselected run are dropped from every plot (see
`drop_run_lines!`).
"""
struct PlotState
    id::Int
    lines::Vector{String}
end

"""
    PlotState(id::Integer)

Construct one plot state. Takes the stable plot number and returns the
state with an empty line selection.
"""
PlotState(id::Integer) = PlotState(Int(id), String[])

"""
    SessionState

Per-page presentation state. Field `model` is the page's
`DashboardModel`, field `manager` the shared `RunManager`, field
`palette` the session-stable line colors, field `cursors` the
presentation cursors by run key (one cursor per run, shared by all
plots that show the run), field `gate` the chart publish throttle,
field `records` the cached record catalog, field `records_signature`
the `DashboardRuntime.catalog_signature` of the last record rescan,
field `records_checked_at` the time of the last record change check,
field `terminal_jobs` the count of terminal jobs at the last check (a
growth means a job just finished and promoted its record), field `plots`
the `PlotState` entries (at least one), field `active_plot_id` the id of
the single visible plot, field `next_plot_id` the id of the next created
plot, field `snap` whether the next update snaps every cursor to the
newest row ("Jump to latest"), field `client_ready` whether the client
has been sent the full view state since it last (re)subscribed:
`handle_client_resync!` clears it on every channel (re)subscription and
`update_page!` sets it only after the full publish succeeded, so a sync
consumed inside a throttle window stays pending, field `closed`
detaches the presentation task (set on browser disconnect and on
shutdown; runs are never cancelled here), and field `task` the
presentation task.
"""
mutable struct SessionState
    model::DashboardModel
    manager::DR.RunManager
    palette::LinePalette
    cursors::Dict{String, PresentationCursor}
    gate::PublishGate
    records::DR.RecordIndex
    records_signature::UInt64
    records_checked_at::Float64
    terminal_jobs::Int
    plots::Vector{PlotState}
    active_plot_id::Int
    next_plot_id::Int
    snap::Bool
    client_ready::Bool
    closed::Bool
    task::Union{Nothing, Task}
end

"""
    SessionState(model::DashboardModel, manager::DashboardRuntime.RunManager)

Construct the per-page session state. Takes the page model and the run
manager and returns the state with an empty palette, no cursors, a
fresh publish gate, an empty record catalog (preloaded with the
signature and terminal-job count of the current record root and job
list, so the first presentation update rescans nothing), and one empty
plot (`PlotState` id 1) as the active plot.
"""
function SessionState(model::DashboardModel, manager::DR.RunManager)
    records = DR.RecordIndex(String(manager.runs_root), Dates.now(), DR.RunPath[], Dict{String, Vector{String}}())
    return SessionState(
        model,
        manager,
        LinePalette(),
        Dict{String, PresentationCursor}(),
        PublishGate(),
        records,
        DR.catalog_signature(String(manager.runs_root)),
        time(),
        count(summary -> DR.is_terminal_state(summary.state), DR.job_summaries(manager)),
        [PlotState(1)],
        1,
        2,
        false,
        false,
        false,
        nothing,
    )
end

"""
    SESSIONS

Live `SessionState` of every page load, guarded by `SESSIONS_LOCK`.
Used to detach every presentation task on server shutdown; browser
disconnect detaches a single session via the `finalize` event.
"""
const SESSIONS = SessionState[]

"""
    SESSIONS_LOCK

Guard of `SESSIONS`.
"""
const SESSIONS_LOCK = ReentrantLock()

"""
    register_session!(session::SessionState)

Register one page session. Takes the session and appends it to
`SESSIONS`. Returns nothing.
"""
function register_session!(session::SessionState)
    lock(SESSIONS_LOCK) do
        push!(SESSIONS, session)
    end
    return nothing
end

"""
    unregister_session!(session::SessionState)

Unregister one page session. Takes the session and removes it from
`SESSIONS`. Returns nothing.
"""
function unregister_session!(session::SessionState)
    lock(SESSIONS_LOCK) do
        filter!(candidate -> candidate !== session, SESSIONS)
    end
    return nothing
end

"""
    form_from_model(model::DashboardModel)::Dict{String,Any}

Build the flat submission form of one page. Takes the model and returns
the form dictionary of `DashboardRuntime.build_spec_dict`: the string
knobs of `FORM_STRING_KEYS` verbatim (blank values are omitted there),
the `metrics` selection, and `record_directory` set to the dashboard
staging policy exactly when the recording checkbox is on.
"""
function form_from_model(model::DashboardModel)::Dict{String, Any}
    form = Dict{String, Any}()
    for key in FORM_STRING_KEYS
        form[key] = String(getproperty(model, Symbol(key))[])
    end
    form["metrics"] = String[String(entry) for entry in model.metrics[]]
    model.record_run[] && (form["record_directory"] = String(DR.DEFAULT_RECORD_DIRECTORY))
    return form
end

"""
    apply_form!(model::DashboardModel, form::AbstractDict)

Fill one page form from a flat form dictionary. Takes the model and the
form (e.g. `DashboardRuntime.default_form` or `clone_form`) and sets
every knob of `FORM_STRING_KEYS` (missing or blank keys become the empty
string), the `metrics` selection, and the recording checkbox (on when
the form carries `record_directory`). Returns nothing.
"""
function apply_form!(model::DashboardModel, form::AbstractDict)
    for key in FORM_STRING_KEYS
        value = get(form, key, "")
        getproperty(model, Symbol(key))[] = value === nothing ? "" : string(value)
    end
    metrics = get(form, "metrics", String[])
    model.metrics[] = String[String(entry) for entry in metrics]
    model.record_run[] = haskey(form, "record_directory")
    return nothing
end

"""
    _event_field(event, name::AbstractString)::String

Read one string field of a UI event payload. Takes the decoded event
dictionary and the field name and returns the value, or the empty string
when the payload is missing or has no such field.
"""
function _event_field(event, name::AbstractString)::String
    event isa AbstractDict || return ""
    value = get(event, name, nothing)
    value === nothing && return ""
    return string(value)
end

"""
    _event_bool(event, name::AbstractString)::Union{Bool,Nothing}

Read one boolean field of a UI event payload. Takes the decoded event
dictionary and the field name and returns the boolean, accepting JSON
booleans and their `"true"`/`"false"` string spellings, or `nothing`
when the payload is missing the field or carries no boolean. Used for
the absolute desired state of a tickbox event (see
`handle_toggle_line!`).
"""
function _event_bool(event, name::AbstractString)::Union{Bool, Nothing}
    event isa AbstractDict || return nothing
    value = get(event, name, nothing)
    value isa Bool && return value
    value isa AbstractString || return nothing
    text = lowercase(strip(String(value)))
    text == "true" && return true
    text == "false" && return false
    return nothing
end

"""
    _valid_record_id(id::AbstractString)::Bool

Report whether a run key addresses a record safely. Takes the key and
returns true only for a plain directory name (no path separators, no
`"."`/`".."`), so record loading and cloning can never reach outside
the record root.
"""
function _valid_record_id(id::AbstractString)::Bool
    text = String(id)
    (isempty(text) || text == "." || text == "..") && return false
    return !occursin('/', text) && !occursin('\\', text)
end

"""
    _session_of(model::DashboardModel)

Take one page model and return its `SessionState`, or `nothing` when the
page has no session yet.
"""
function _session_of(model::DashboardModel)
    session = model.session[]
    return session isa SessionState ? session : nothing
end

"""
    _manager_of(model::DashboardModel)

Take one page model and return its `DashboardRuntime.RunManager`, or
`nothing` when the page has no manager attached.
"""
function _manager_of(model::DashboardModel)
    manager = model.manager[]
    return manager isa DR.RunManager ? manager : nothing
end

"""
    run_seed(session::SessionState, key::AbstractString)::Int

Seed shown in the label of one run. Takes the session and the run key
and returns the seed of the registered job spec, else the seed of the
cached record, else 0.
"""
function run_seed(session::SessionState, key::AbstractString)::Int
    spec = job_spec(key)
    spec === nothing || return spec.seed
    for record in session.records.records
        record.run_id == key && return record.seed
    end
    return 0
end

"""
    build_job_rows(session::SessionState, summaries::Vector{DashboardRuntime.JobSummary})::Vector{Dict{String,Any}}

Render the job table rows. Takes the session and the job summaries and
returns one row per job in submission order with the job key, name,
state label, queue position, progress label, and cancel and clone
flags.
"""
function build_job_rows(
        session::SessionState,
        summaries::Vector{DR.JobSummary},
    )::Vector{Dict{String, Any}}
    rows = Dict{String, Any}[]
    for summary in summaries
        key = string(summary.job_id)
        percent = round(Int, 100 * summary.progress)
        push!(
            rows,
            Dict{String, Any}(
                "key" => key,
                "name" => summary.name,
                "state" => state_label(summary.state),
                "queue_label" => summary.queue_position > 0 ? "position $(summary.queue_position)" : "",
                "progress_label" => "$percent%",
                "can_cancel" => !DR.is_terminal_state(summary.state),
                "can_clone" => haskey(JOB_SPECS, key),
            ),
        )
    end
    return rows
end

"""
    build_run_rows(session::SessionState, summaries::Vector{DashboardRuntime.JobSummary}, labels::Dict{String,String})::Vector{Dict{String,Any}}

Render the run log rows. Takes the session, the job summaries, and the
per-run presentation status labels of the current update, and returns
one row per live job plus one row per recorded run not already covered
by a live job. Rows carry the run key, label, source, seed, status, and
the selection, load, replay, and clone flags; a record's notes surface
its record-structure diagnostics and, when the spec is missing or
invalid, its spec problems (cloning is disabled then).
"""
function build_run_rows(
        session::SessionState,
        summaries::Vector{DR.JobSummary},
        labels::Dict{String, String},
    )::Vector{Dict{String, Any}}
    model = session.model
    selected = model.selected_runs[]
    live_ids = Set{String}(summary.run_id for summary in summaries if !isempty(summary.run_id))
    rows = Dict{String, Any}[]
    for summary in summaries
        key = string(summary.job_id)
        push!(
            rows,
            Dict{String, Any}(
                "key" => key,
                "label" => run_label(summary.name, run_seed(session, key), summary.run_id),
                "source" => "live",
                "seed" => string(run_seed(session, key)),
                "state" => get(labels, key, state_label(summary.state)),
                "selected" => key in selected,
                "select_label" => key in selected ? "Unplot" : "Plot",
                "can_load" => false,
                "can_clone" => haskey(JOB_SPECS, key),
                "can_replay" => key in selected,
                "notes" => "",
            ),
        )
    end
    for record in session.records.records
        (isempty(record.run_id) || record.run_id in live_ids) && continue
        key = record.run_id
        push!(
            rows,
            Dict{String, Any}(
                "key" => key,
                "label" => run_label(record.name, record.seed, record.run_id),
                "source" => "recorded",
                "seed" => string(record.seed),
                "state" => get(labels, key, state_label(record.state)),
                "selected" => key in selected,
                "select_label" => key in selected ? "Unplot" : "Plot",
                "can_load" => true,
                "can_clone" => record.spec !== nothing,
                "can_replay" => key in selected,
                "notes" => join(vcat(record.diagnostics, record.spec_problems), "; "),
            ),
        )
    end
    return rows
end

"""
    active_plot_state(session::SessionState)::PlotState

Selection state of the single visible plot. Takes the session and
returns its `PlotState` with `id == session.active_plot_id`, falling
back to the first plot when the active id is stale. Session states
always hold at least one plot.
"""
function active_plot_state(session::SessionState)::PlotState
    for state in session.plots
        state.id == session.active_plot_id && return state
    end
    return session.plots[1]
end

"""
    plot_state_by_id(session::SessionState, plot_id::Integer)

Resolve one plot by its stable id. Takes the session and the plot id
and returns that plot's `PlotState`, or `nothing` when no live plot has
that id. Unlike `active_plot_state` this never falls back to another
plot, so a stale UI event is rejected instead of touching an unrelated
plot (see `handle_toggle_line!`).
"""
function plot_state_by_id(session::SessionState, plot_id::Integer)
    index = findfirst(state -> state.id == plot_id, session.plots)
    return index === nothing ? nothing : session.plots[index]
end

"""
    run_metric_names(session::SessionState, key::AbstractString)::Vector{String}

Metric names one run offers as lines. Takes the session and the run key
and returns the metric names of the run's received rows (including only
what a record actually carries, so a record with an excluded column
offers no line for it), falling back to the validated spec's metric
selection for a live run that has not streamed rows yet. Returns the
empty vector for unknown runs.
"""
function run_metric_names(session::SessionState, key::AbstractString)::Vector{String}
    probe = try
        DR.path_snapshot(session.manager, key; visible_rows = 0, max_points = 1)
    catch
        return String[]
    end
    isempty(probe.metric_names) || return copy(probe.metric_names)
    spec = job_spec(key)
    spec === nothing && return String[]
    return copy(spec.logging.metrics)
end

"""
    enable_run_lines!(session::SessionState, key::AbstractString)

Check one run's lines in the active plot. Takes the session and the run
key and adds the `line_key` of every metric the run offers (see
`run_metric_names`, in `metric_display_order`) to the active plot's
selection unless it is already selected. Other plots are never touched.
Returns nothing.
"""
function enable_run_lines!(session::SessionState, key::AbstractString)
    state = active_plot_state(session)
    for metric in metric_display_order(run_metric_names(session, key))
        line = line_key(key, metric)
        line in state.lines || push!(state.lines, line)
    end
    return nothing
end

"""
    drop_run_lines!(session::SessionState, key::AbstractString)

Drop one run's lines from every plot. Takes the session and the run key
and removes every selected line key with the run's `"<run key>:"`
prefix (run keys never contain `":"`, so the prefix identifies the run)
from all plots. Returns nothing.
"""
function drop_run_lines!(session::SessionState, key::AbstractString)
    prefix = string(key, ":")
    for state in session.plots
        filter!(line -> !startswith(line, prefix), state.lines)
    end
    return nothing
end

"""
    build_plot_tabs(session::SessionState)::Vector{Dict{String,Any}}

Render the plot tab strip rows. Takes the session and returns one row
per plot in creation order with the tab id, the `"Plot <id>"` label,
the active flag (exactly one tab is active), and the close flag (true
except on the last remaining plot).
"""
function build_plot_tabs(session::SessionState)::Vector{Dict{String, Any}}
    can_close = length(session.plots) > 1
    return [
        Dict{String, Any}(
                "id" => string(state.id),
                "label" => "Plot $(state.id)",
                "active" => state.id == session.active_plot_id,
                "can_close" => can_close,
            ) for state in session.plots
    ]
end

"""
    build_line_groups(session::SessionState, series::Vector{RunSeries})::Vector{Dict{String,Any}}

Render the line tickbox rows of the active plot. Takes the session and
the run series and returns one group per plotted run with the run label
and one row per metric the run actually carries (in
`metric_display_order`, never a row for a missing column): each line
row has its `line_key`, its metric title, and the checked flag from the
active plot's selection. Every group and line row also carries the
`plot_id` of the plot it was rendered for, so a delayed tickbox event
can resolve its originating plot instead of hitting whatever plot is
active when it arrives (see `handle_toggle_line!`). A plot's tickboxes
therefore offer exactly the run's existing lines and reflect only that
plot's selection. Groups follow the run series order.
"""
function build_line_groups(
        session::SessionState,
        series::Vector{RunSeries},
    )::Vector{Dict{String, Any}}
    state = active_plot_state(session)
    plot_id = string(state.id)
    selected = Set{String}(state.lines)
    groups = Dict{String, Any}[]
    for entry in series
        lines = Dict{String, Any}[]
        for metric in metric_display_order(entry.snapshot.metric_names)
            key = line_key(entry.key, metric)
            push!(
                lines,
                Dict{String, Any}(
                    "key" => key,
                    "label" => metric_title(metric),
                    "checked" => key in selected,
                    "plot_id" => plot_id,
                ),
            )
        end
        isempty(lines) && continue
        push!(
            groups,
            Dict{String, Any}(
                "key" => entry.key,
                "label" => run_label(entry.name, entry.seed, entry.snapshot.run_id),
                "plot_id" => plot_id,
                "lines" => lines,
            ),
        )
    end
    return groups
end

"""
    build_series!(session::SessionState)::Tuple{Vector{RunSeries},Dict{String,String}}

Collect the chart input of the selected runs. Takes the session, reads
the executed rows of every selected run through
`DashboardRuntime.path_snapshot`, advances its presentation cursor by
one reveal quota (or snaps it to the newest row after "Jump to latest"),
and returns the `RunSeries` for `build_plot` together with the
presentation status label per run key. A run's cursor is created on
first sight: complete for recorded and finished runs, at zero for live
runs so they animate in. Unknown or disappearing run keys are skipped,
never breaking the presentation loop.
"""
function build_series!(session::SessionState)
    model = session.model
    series = RunSeries[]
    labels = Dict{String, String}()
    for key in model.selected_runs[]
        length(series) >= MAX_SELECTED_RUNS && break
        probe = try
            DR.path_snapshot(session.manager, key; visible_rows = 0, max_points = 1)
        catch
            continue
        end
        cursor = get(session.cursors, key, nothing)
        if cursor === nothing
            complete = probe.source == :recorded || DR.is_terminal_state(probe.state)
            cursor = PresentationCursor(key; rows = complete ? probe.rows_total : 0)
            session.cursors[key] = cursor
        end
        visible = advance_cursor!(cursor, probe.rows_total, probe.ticks_requested; snap = session.snap)
        labels[key] = status_label(probe.state, is_lagging(cursor, probe.rows_total))
        snapshot = try
            DR.path_snapshot(session.manager, key; visible_rows = visible, max_points = PLOT_MAX_POINTS)
        catch
            continue
        end
        push!(
            series,
            RunSeries(;
                key,
                snapshot,
                name = snapshot.name,
                seed = run_seed(session, key),
            ),
        )
    end
    session.snap = false
    return series, labels
end

"""
    series_signature(series::Vector{RunSeries})::UInt64

Signature of the currently visible chart data. Takes the run series and
returns a hash over the run keys, the revealed and executed row counts,
the metric names, and the data revisions (so reloading a record with
changed content always republishes); `PublishGate` publishes only when
the full `page_signature` changed.
"""
function series_signature(series::Vector{RunSeries})::UInt64
    signature = zero(UInt64)
    for entry in series
        snapshot = entry.snapshot
        signature = hash(
            (
                entry.key,
                snapshot.rows_total,
                snapshot.visible_rows,
                snapshot.metric_names,
                snapshot.revision,
            ),
            signature,
        )
    end
    return signature
end

"""
    page_signature(session::SessionState, series::Vector{RunSeries})::UInt64

Signature of everything the chart shows. Takes the session and the run
series and returns the `series_signature` hashed with the active plot
id and every plot's selection, so switching plots or toggling a line
republishes even when the data itself is unchanged.
"""
function page_signature(session::SessionState, series::Vector{RunSeries})::UInt64
    selections = Tuple{Int, Vector{String}}[(state.id, copy(state.lines)) for state in session.plots]
    return hash((session.active_plot_id, selections), series_signature(series))
end

"""
    rescan_records!(session::SessionState; now::Real = time(), after_scan::Function = () -> nothing)::DashboardRuntime.RecordIndex

Rescan the record catalog of one page session unconditionally. Takes
the session, the current time, and an optional `after_scan` callback
(injectable for tests) that runs after the directory scan and before
the result is acknowledged. The change-check baseline
(`DashboardRuntime.catalog_signature`) is captured *before* the scan,
so a record another process promotes while the scan runs can never be
acknowledged without being in the cached index: `records_signature` is
never newer than `session.records`, and the periodic check of
`refresh_records_if_changed!` therefore always notices such a racing
promotion and rescans. Records the racing promotion added to the scan
are covered by the older baseline and cost one redundant rescan, never
permanent invisibility. Returns the new `RecordIndex`.
"""
function rescan_records!(
        session::SessionState;
        now::Real = time(),
        after_scan::Function = () -> nothing,
    )::DR.RecordIndex
    signature = DR.catalog_signature(String(session.manager.runs_root))
    index = DR.refresh_records!(session.manager)
    after_scan()
    session.records = index
    session.records_signature = signature
    session.records_checked_at = Float64(now)
    return index
end

"""
    refresh_records_if_changed!(session::SessionState, summaries::Vector{DashboardRuntime.JobSummary}; now::Real = time())::Bool

Keep the cached record catalog fresh while the page runs. Takes the
session, the current job summaries, and the current time, and rescans
the catalog when a job just reached a terminal outcome (its record is
promoted before the state turns terminal, so the rescan picks it up)
or when the record set changed since the last check. The record set is
compared with the cheap `DashboardRuntime.catalog_signature` at most
once per `RECORDS_REFRESH_INTERVAL`, so unchanged catalogs cost one
directory listing per interval and no record parsing. The baseline
compared against is never newer than the cached index (see
`rescan_records!`), so a promotion racing a rescan is always caught by
a later check. Cursors, plot selections, and the active plot are never
touched. Returns whether the catalog was rescanned.
"""
function refresh_records_if_changed!(
        session::SessionState,
        summaries::Vector{DR.JobSummary};
        now::Real = time(),
    )::Bool
    terminal = count(summary -> DR.is_terminal_state(summary.state), summaries)
    if terminal != session.terminal_jobs
        session.terminal_jobs = terminal
        rescan_records!(session; now)
        return true
    end
    now - session.records_checked_at < RECORDS_REFRESH_INTERVAL && return false
    session.records_checked_at = Float64(now)
    signature = DR.catalog_signature(String(session.manager.runs_root))
    signature == session.records_signature && return false
    rescan_records!(session; now)
    return true
end

"""
    update_page!(session::SessionState)::Bool

Run one presentation update. Takes the session, keeps the record
catalog fresh (`refresh_records_if_changed!`), refreshes the job and
run log rows and the plot tabs and line tickboxes when they changed,
computes the active plot of the revealed rows, and writes the reactive
chart fields exactly when the publish gate allows it (at most one
publish per `PUBLISH_INTERVAL`, only on changed visible data). On the
first update after the page's client signals readiness, and after
every channel (re)subscription (`handle_client_resync!`), the full
view state (run rows, job rows, plot tabs, line groups, the chart and
its axis label, and the status line) is (re)published even when
unchanged: the browser connects after the page was rendered and a
reconnecting browser missed every update of the disconnect window, so
without this sync a view computed earlier would reach it only after
some later change. The sync stays pending until the chart publish
actually succeeds, so a readiness or resubscription signal inside a
throttle window is retried on the next update instead of being
silently consumed. Only this function (the presentation task) writes
the reactive view fields. Returns whether the chart was published.
"""
function update_page!(session::SessionState)::Bool
    model = session.model
    summaries = DR.job_summaries(session.manager)
    refresh_records_if_changed!(session, summaries)
    series, labels = build_series!(session)
    sync_client = model.isready[] && !session.client_ready
    job_rows = build_job_rows(session, summaries)
    (sync_client || job_rows != model.job_rows[]) && (model.job_rows[] = job_rows)
    run_rows = build_run_rows(session, summaries, labels)
    (sync_client || run_rows != model.run_rows[]) && (model.run_rows[] = run_rows)
    tabs = build_plot_tabs(session)
    (sync_client || tabs != model.plot_tabs[]) && (model.plot_tabs[] = tabs)
    groups = build_line_groups(session, series)
    (sync_client || groups != model.line_groups[]) && (model.line_groups[] = groups)
    # The handlers write the status line, so only this forced republish
    # carries it across a reconnect (self-assignment on purpose: it
    # pushes the current value even when nothing changed).
    sync_client && (model.status_line[] = model.status_line[])

    result = build_plot(series, session.palette, active_plot_state(session).lines)
    signature = page_signature(session, series)
    can_publish!(session.gate, signature, time(); force = sync_client) || return false
    # The full view state reached the client only now; a sync rejected
    # by the throttle above stays pending (see the docstring).
    sync_client && (session.client_ready = true)
    model.active_plot[] = result.plot
    model.axis_label[] = axis_label(result.axis)
    model.display_reduced[] = result.reduced
    model.data_warnings[] = result.warnings
    return true
end

"""
    presentation_loop!(session::SessionState)

Per-page presentation task. Takes the session and polls the run manager
every `PUBLISH_INTERVAL` seconds until the session is detached (browser
disconnect or server shutdown) or the run manager is shut down, calling
`update_page!`. Browser disconnect only detaches this task; queued and
running jobs are never touched. Returns nothing.
"""
function presentation_loop!(session::SessionState)
    try
        while !session.closed && !session.manager.closed
            sleep(PUBLISH_INTERVAL)
            (session.closed || session.manager.closed) && break
            update_page!(session)
        end
    catch err
        err isa InterruptException && rethrow()
        @error "presentation task failed" exception = (err, catch_backtrace())
    end
    unregister_session!(session)
    return nothing
end

"""
    start_presentation!(session::SessionState)

Start the per-page presentation task. Takes the session and spawns
`presentation_loop!` as a detached task. Returns the task.
"""
function start_presentation!(session::SessionState)::Task
    session.task = @async presentation_loop!(session)
    return session.task
end

"""
    close_session!(session::SessionState)

Detach one page session. Takes the session and stops its presentation
task; runs and jobs are never touched. Returns nothing.
"""
function close_session!(session::SessionState)
    session.closed = true
    return nothing
end

"""
    stop_sessions!()

Detach every live page session and wait for its presentation task.
Takes no arguments and returns nothing; used on server shutdown so no
presentation task outlives the app.
"""
function stop_sessions!()
    sessions = lock(SESSIONS_LOCK) do
        copy(SESSIONS)
    end
    for session in sessions
        close_session!(session)
    end
    for session in sessions
        task = session.task
        task === nothing && continue
        try
            wait(task)
        catch
            # A failed presentation task is already reported; shutdown continues.
        end
    end
    return nothing
end

"""
    handle_submit!(model::DashboardModel)

Submit handler. Takes the page model, validates the form with
`DashboardRuntime.validate_form`, and either shows the validation
problems or enqueues the run (never executing model ticks here).
Returns nothing.
"""
function handle_submit!(model::DashboardModel)
    result = DR.validate_form(form_from_model(model))
    if result isa Vector{String}
        model.problems[] = copy(result)
        model.status_line[] = "configuration invalid; nothing was queued"
        return nothing
    end
    manager = _manager_of(model)
    if manager === nothing
        model.status_line[] = "no run manager attached to this page"
        return nothing
    end
    try
        job_id = DR.enqueue!(manager, result; record = model.record_run[])
        register_job_spec!(job_id, result)
        model.problems[] = String[]
        model.status_line[] = "run \"$(result.name)\" queued as job $(short_run_id(string(job_id)))"
    catch err
        err isa ArgumentError || rethrow()
        model.problems[] = [String(err.msg)]
        model.status_line[] = "job not queued"
    end
    return nothing
end

"""
    handle_cancel_job!(model::DashboardModel, event)

Cancel the job named in the event. Takes the page model and the UI event
carrying `job_id` and requests cancellation of that dashboard job.
Returns nothing.
"""
function handle_cancel_job!(model::DashboardModel, event)
    key = _event_field(event, "job_id")
    manager = _manager_of(model)
    if manager === nothing || isempty(key)
        model.status_line[] = "no job to cancel"
        return nothing
    end
    parsed = tryparse(UUIDs.UUID, key)
    ok = parsed !== nothing && DR.cancel!(manager, parsed)
    model.status_line[] =
        ok ? "cancellation requested for job $(short_run_id(key))" : "job $(short_run_id(key)) cannot be cancelled"
    return nothing
end

"""
    handle_cancel_active!(model::DashboardModel)

Cancel the currently executing run. Takes the page model and cancels
the single job in `starting` or `running` state, if any. Returns
nothing.
"""
function handle_cancel_active!(model::DashboardModel)
    manager = _manager_of(model)
    manager === nothing && return nothing
    for summary in DR.job_summaries(manager)
        summary.state in (DR.JOB_STARTING, DR.JOB_RUNNING) || continue
        return handle_cancel_job!(model, Dict{String, Any}("job_id" => string(summary.job_id)))
    end
    model.status_line[] = "no running job to cancel"
    return nothing
end

"""
    handle_refresh_records!(model::DashboardModel)

Rescan the record catalog. Takes the page model, rescans via
`rescan_records!` (which also refreshes the change-check baseline of
`refresh_records_if_changed!`), and reports the number of found
records. Returns nothing.
"""
function handle_refresh_records!(model::DashboardModel)
    session = _session_of(model)
    session === nothing && return nothing
    index = rescan_records!(session)
    problems = String[]
    for lines in values(index.problems)
        append!(problems, lines)
    end
    model.problems[] = problems
    model.status_line[] = "records refreshed: $(length(index.records)) under $(index.root)"
    return nothing
end

"""
    handle_load_record!(model::DashboardModel, event)

Load one recorded run by id. Takes the page model and the UI event
carrying the run id and loads `runs_root/<id>/run.toml` through
`DashboardRuntime.load_record!`; arbitrary paths are rejected. Returns
nothing.
"""
function handle_load_record!(model::DashboardModel, event)
    session = _session_of(model)
    key = _event_field(event, "key")
    if session === nothing || !_valid_record_id(key)
        model.status_line[] = "no record to load"
        return nothing
    end
    try
        DR.load_record!(session.manager, key)
        model.problems[] = String[]
        model.status_line[] = "record $(short_run_id(key)) loaded"
    catch err
        err isa ArgumentError || rethrow()
        model.problems[] = [String(err.msg)]
        model.status_line[] = "record $(short_run_id(key)) not loaded"
    end
    return nothing
end

"""
    _clone_source(session::SessionState, key::AbstractString)

Build the clone input of one run. Takes the session and the run key and
returns a `DashboardRuntime.RunPath` carrying the validated spec of a
live job or of a loaded record; a run without a valid spec yields a
path with `spec = nothing`, so `DashboardRuntime.clone_form` reports the
clear "cloning is disabled" error.
"""
function _clone_source(session::SessionState, key::AbstractString)
    spec = job_spec(key)
    if spec !== nothing
        return DR.RunPath(;
            run_id = String(key),
            name = spec.name,
            seed = spec.seed,
            source = :live,
            spec = spec,
        )
    end
    _valid_record_id(key) || return DR.RunPath(name = String(key))
    try
        return DR.load_record!(session.manager, key)
    catch
        return DR.RunPath(name = String(key))
    end
end

"""
    handle_clone_config!(model::DashboardModel, event)

Clone one run's configuration into the form. Takes the page model and
the UI event carrying the run key and fills the form through
`DashboardRuntime.clone_form` (model settings, seed, metric selection,
copied name, and the dashboard staging record policy). Runs without a
valid spec disable cloning with the `clone_form` error message shown in
the problem list. Returns nothing.
"""
function handle_clone_config!(model::DashboardModel, event)
    session = _session_of(model)
    key = _event_field(event, "key")
    if session === nothing || isempty(key)
        model.status_line[] = "no configuration to clone"
        return nothing
    end
    try
        form = DR.clone_form(_clone_source(session, key))
        apply_form!(model, form)
        model.problems[] = String[]
        model.status_line[] = "configuration cloned from $(short_run_id(key)); review and submit"
    catch err
        err isa ArgumentError || rethrow()
        model.problems[] = [String(err.msg)]
        model.status_line[] = "cloning disabled for run $(short_run_id(key))"
    end
    return nothing
end

"""
    handle_select_run!(model::DashboardModel, event)

Toggle one run in the plotted run selection. Takes the page model and
the UI event carrying the run key: selected runs are unselected (their
line keys are dropped from every plot), other runs are selected up to
`MAX_SELECTED_RUNS` after loading their record by id and their lines
are checked in the active plot only. Returns nothing.
"""
function handle_select_run!(model::DashboardModel, event)
    session = _session_of(model)
    key = _event_field(event, "key")
    if session === nothing || isempty(key)
        model.status_line[] = "no run to select"
        return nothing
    end
    selected = String[String(entry) for entry in model.selected_runs[]]
    if key in selected
        filter!(entry -> entry != key, selected)
        drop_run_lines!(session, key)
        model.selected_runs[] = selected
        model.status_line[] = "run $(short_run_id(key)) removed from the plots"
        return nothing
    end
    if length(selected) >= MAX_SELECTED_RUNS
        model.status_line[] = "at most $MAX_SELECTED_RUNS runs at once; deselect one first"
        return nothing
    end
    if job_spec(key) === nothing
        if !_valid_record_id(key)
            model.status_line[] = "run $(short_run_id(key)) cannot be selected"
            return nothing
        end
        try
            DR.load_record!(session.manager, key)
        catch err
            err isa ArgumentError || rethrow()
            model.problems[] = [String(err.msg)]
            model.status_line[] = "run $(short_run_id(key)) cannot be loaded"
            return nothing
        end
    end
    push!(selected, key)
    model.selected_runs[] = selected
    enable_run_lines!(session, key)
    model.status_line[] = "run $(short_run_id(key)) added to the plots"
    return nothing
end

"""
    handle_toggle_line!(model::DashboardModel, event)

Apply one line tickbox change to its originating plot. Takes the page
model and the UI event carrying the line key (see `line_key`), the
`plot_id` the tickbox row was rendered for (see `build_line_groups`),
and the desired `checked` state, and sets that line in that plot's
selection absolutely, never as a blind toggle. A delayed event
therefore always resolves the plot it came from, even when the page has
switched plots in the meantime; events whose plot was deleted (or never
existed) or whose payload lacks a line key, a parseable plot id, or a
boolean state are rejected without touching any plot. Other plots and
the run selection are never touched. Returns nothing.
"""
function handle_toggle_line!(model::DashboardModel, event)
    session = _session_of(model)
    line = _event_field(event, "line")
    (session === nothing || isempty(line)) && return nothing
    plot_id = tryparse(Int, _event_field(event, "plot_id"))
    checked = _event_bool(event, "checked")
    (plot_id === nothing || checked === nothing) && return nothing
    state = plot_state_by_id(session, plot_id)
    state === nothing && return nothing
    if checked
        line in state.lines || push!(state.lines, line)
    else
        filter!(entry -> entry != line, state.lines)
    end
    return nothing
end

"""
    handle_add_plot!(model::DashboardModel)

Add one plot. Takes the page model, appends a new `PlotState` (up to
`MAX_PLOTS`) whose lines are the currently available lines of the
selected runs (see `run_metric_names`), and switches to it; when no run
is selected the new plot starts empty. Returns nothing.
"""
function handle_add_plot!(model::DashboardModel)
    session = _session_of(model)
    if session === nothing
        model.status_line[] = "no page session"
        return nothing
    end
    if length(session.plots) >= MAX_PLOTS
        model.status_line[] = "at most $MAX_PLOTS plots; delete one first"
        return nothing
    end
    state = PlotState(session.next_plot_id)
    session.next_plot_id += 1
    for key in model.selected_runs[]
        for metric in metric_display_order(run_metric_names(session, key))
            push!(state.lines, line_key(key, metric))
        end
    end
    push!(session.plots, state)
    session.active_plot_id = state.id
    model.status_line[] = "plot $(state.id) created"
    return nothing
end

"""
    handle_remove_plot!(model::DashboardModel, event)

Delete one plot. Takes the page model and the UI event carrying the
plot id and removes that plot; the last remaining plot cannot be
deleted, and deleting the active plot activates its closest remaining
neighbor. Returns nothing.
"""
function handle_remove_plot!(model::DashboardModel, event)
    session = _session_of(model)
    plot_id = tryparse(Int, _event_field(event, "plot_id"))
    if session === nothing || plot_id === nothing
        model.status_line[] = "no plot to delete"
        return nothing
    end
    if length(session.plots) <= 1
        model.status_line[] = "the last plot cannot be deleted"
        return nothing
    end
    index = findfirst(state -> state.id == plot_id, session.plots)
    if index === nothing
        model.status_line[] = "plot $plot_id unknown"
        return nothing
    end
    deleteat!(session.plots, index)
    if session.active_plot_id == plot_id
        session.active_plot_id = session.plots[min(index, length(session.plots))].id
    end
    model.status_line[] = "plot $plot_id deleted"
    return nothing
end

"""
    handle_activate_plot!(model::DashboardModel, event)

Switch the visible plot. Takes the page model and the UI event carrying
the plot id and makes that plot the single active one (unknown ids leave
the selection unchanged). The chart follows within one publish
interval. Returns nothing.
"""
function handle_activate_plot!(model::DashboardModel, event)
    session = _session_of(model)
    plot_id = tryparse(Int, _event_field(event, "plot_id"))
    (session === nothing || plot_id === nothing) && return nothing
    any(state -> state.id == plot_id, session.plots) || return nothing
    session.active_plot_id = plot_id
    model.status_line[] = "showing plot $plot_id"
    return nothing
end

"""
    handle_jump_latest!(model::DashboardModel)

Snap every presentation cursor to the newest row. Takes the page model
and requests the snap for the next presentation update. Returns
nothing.
"""
function handle_jump_latest!(model::DashboardModel)
    session = _session_of(model)
    session === nothing && return nothing
    session.snap = true
    model.status_line[] = "jumped to the latest rows"
    return nothing
end

"""
    handle_replay_run!(model::DashboardModel, event)

Replay one run from its first row. Takes the page model and the UI
event carrying the run key and restarts the run's presentation cursor,
so the buffered rows play back again at the paced rate. Returns
nothing.
"""
function handle_replay_run!(model::DashboardModel, event)
    session = _session_of(model)
    key = _event_field(event, "key")
    (session === nothing || isempty(key)) && return nothing
    cursor = get(session.cursors, key, nothing)
    cursor === nothing && return nothing
    start_replay!(cursor)
    model.status_line[] = "replaying run $(short_run_id(key))"
    return nothing
end

"""
    handle_client_resync!(model::DashboardModel)

Client (re)subscription handler (the `client_resync` event of the
page's resubscription hook, see `dashboard_layout`). Takes the page
model and marks its session as not yet synced, so the next
presentation update republishes the full view state even when nothing
changed (see `update_page!`). The event fires on every channel
(re)subscription: a reconnecting browser missed every update of the
disconnect window, and Stipple suppresses repeated readiness updates of
an already-ready model, so readiness alone can never resync it.
Returns nothing.
"""
function handle_client_resync!(model::DashboardModel)
    session = _session_of(model)
    session === nothing && return nothing
    session.client_ready = false
    return nothing
end

"""
    handle_finalize(model::DashboardModel)

Browser-disconnect handler (the Stipple `finalize` event). Takes the
page model, detaches its presentation task only, and runs the default
Stipple finalizer; queued and running jobs are never cancelled on
disconnect. Returns nothing.
"""
function handle_finalize(model::DashboardModel)
    session = _session_of(model)
    session === nothing || close_session!(session)
    Base.notify(model, Val(:finalize))
    return nothing
end

@event DashboardModel :submit begin
    handle_submit!(__model__)
end

@event DashboardModel :cancel_job begin
    handle_cancel_job!(__model__, event)
end

@event DashboardModel :cancel_active begin
    handle_cancel_active!(__model__)
end

@event DashboardModel :refresh_records begin
    handle_refresh_records!(__model__)
end

@event DashboardModel :load_record begin
    handle_load_record!(__model__, event)
end

@event DashboardModel :clone_config begin
    handle_clone_config!(__model__, event)
end

@event DashboardModel :select_run begin
    handle_select_run!(__model__, event)
end

@event DashboardModel :toggle_line begin
    handle_toggle_line!(__model__, event)
end

@event DashboardModel :add_plot begin
    handle_add_plot!(__model__)
end

@event DashboardModel :remove_plot begin
    handle_remove_plot!(__model__, event)
end

@event DashboardModel :activate_plot begin
    handle_activate_plot!(__model__, event)
end

@event DashboardModel :jump_latest begin
    handle_jump_latest!(__model__)
end

@event DashboardModel :replay_run begin
    handle_replay_run!(__model__, event)
end

@event DashboardModel :client_resync begin
    handle_client_resync!(__model__)
end

@event DashboardModel :finalize begin
    handle_finalize(__model__)
end
