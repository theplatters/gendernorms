# Plot construction of the dashboard UI layer.
#
# `build_plots` turns the `PathSnapshot` views of the selected runs into
# the three PlotlyBase panels (one per metric): one line trace per run,
# x = tick, session-stable run colors, and a stable `uirevision` so zoom
# survives republishing. Display-only downsampling keeps every panel
# within a fixed point budget; non-finite values become gaps. This file
# depends only on `DashboardRuntime` and PlotlyBase.

"""
    PANEL_METRICS

Metric names of the three dashboard panels, one panel per metric:
`"working_time_men"`, `"working_time_women"`, and `"working_time_gap"`.
The list is the display order of the panels and the y-axis titles.
"""
const PANEL_METRICS = ["working_time_men", "working_time_women", "working_time_gap"]

"""
    PANEL_TITLES

Human-readable panel headings keyed by metric name (see
`PANEL_METRICS`). Only used for headings; axis titles carry the raw
metric names.
"""
const PANEL_TITLES = Dict{String,String}(
    "working_time_men" => "Working time (men)",
    "working_time_women" => "Working time (women)",
    "working_time_gap" => "Working time gap",
)

"""
    PANEL_MAX_POINTS

Display budget per panel: at most 6000 points across all traces of one
panel. Panels above the budget downsample every trace with
`downsample_indices` and report `PlotBuildResult.reduced`.
"""
const PANEL_MAX_POINTS = 6000

"""
    PLOT_UIREVISION

Stable `layout.uirevision` of every dashboard panel, so Plotly keeps the
current zoom and pan state across republished plots.
"""
const PLOT_UIREVISION = "gendernorms-dashboard"

"""
    RUN_PALETTE

Trace colors assigned to runs in order of first appearance in a
`RunPalette`. Ten distinguishable colors; runs beyond the palette cycle
through it.
"""
const RUN_PALETTE = [
    "#1f77b4",
    "#ff7f0e",
    "#2ca02c",
    "#d62728",
    "#9467bd",
    "#8c564b",
    "#e377c2",
    "#7f7f7f",
    "#bcbd22",
    "#17becf",
]

"""
    RunSeries

Chart input of one selected run. Field `key` is the session-stable run
identity (the dashboard job id of a live run or the run UUID of a
recorded run), field `name` the run label, field `seed` the run seed,
field `snapshot` the chart data with the rows the presentation cursor
currently reveals, and field `visible` whether the run is shown (the
visibility toggle applies to all panels).
"""
struct RunSeries
    key::String
    name::String
    seed::Int
    snapshot::DR.PathSnapshot
    visible::Bool
end

"""
    RunSeries(; key, snapshot, name = snapshot.name, seed = 0, visible = true)

Construct a `RunSeries`. Takes the session key, the chart data, and the
optional run label, run seed, and visibility. Returns the series.
"""
function RunSeries(;
    key::AbstractString,
    snapshot::DR.PathSnapshot,
    name::AbstractString = snapshot.name,
    seed::Integer = 0,
    visible::Bool = true,
)
    return RunSeries(String(key), String(name), Int(seed), snapshot, visible)
end

"""
    RunPalette

Session-stable run colors. Field `order` records the run keys in order
of first appearance, field `colors` maps each known key to its assigned
hex color. `color_for!` assigns a color when a run first appears and
returns the same color on every later call, so a run keeps its color
across all panels and republishes of one session.
"""
mutable struct RunPalette
    order::Vector{String}
    colors::Dict{String,String}
end

"""
    RunPalette()

Construct an empty run palette. Takes no arguments and returns the
palette.
"""
RunPalette() = RunPalette(String[], Dict{String,String}())

"""
    color_for!(palette::RunPalette, key::AbstractString)::String

Return the session color of one run. Takes the palette and the
session-stable run key, assigning the next palette color when the key is
new (cycles through `RUN_PALETTE`). Returns the hex color, identical for
the same key in the same palette.
"""
function color_for!(palette::RunPalette, key::AbstractString)::String
    return get!(palette.colors, String(key)) do
        push!(palette.order, String(key))
        return RUN_PALETTE[mod1(length(palette.order), length(RUN_PALETTE))]
    end
end

"""
    short_run_id(run_id::AbstractString)::String

Shorten a run identity for labels. Takes the run UUID or session key and
returns its first 8 characters, or the empty string for the empty id.
"""
function short_run_id(run_id::AbstractString)::String
    id = strip(run_id)
    return isempty(id) ? "" : id[1:min(8, lastindex(id))]
end

"""
    run_label(name::AbstractString, seed::Integer, run_id::AbstractString)::String

Build the legend label of one run: the run name, its seed, and the short
run id. Takes the run name, the seed, and the run UUID or session key.
Returns `"<name> (seed <seed>, <short id>)"`, or `"<name> (seed
<seed>)"` when the id is empty.
"""
function run_label(name::AbstractString, seed::Integer, run_id::AbstractString)::String
    short = short_run_id(run_id)
    label = strip(name)
    isempty(label) && (label = "run")
    return isempty(short) ? "$label (seed $seed)" : "$label (seed $seed, $short)"
end

"""
    trace_uid(series::RunSeries, metric::AbstractString)::String

Build the Plotly trace uid of one run and metric: `"<run-uuid>:<metric>"`
with the core run UUID from the snapshot, falling back to the session
key when the run has no UUID yet. Returns the uid.
"""
function trace_uid(series::RunSeries, metric::AbstractString)::String
    id = isempty(series.snapshot.run_id) ? series.key : series.snapshot.run_id
    return string(id, ":", metric)
end

"""
    PlotBuildResult

Result of `build_plots`. Field `plots` holds one `PlotlyBase.Plot` per
`PANEL_METRICS` entry, field `reduced` whether any panel downsampled its
traces for the display budget, field `nonfinite` whether any trace
carries non-finite values, and field `warnings` the human-readable
warning lines for those values.
"""
struct PlotBuildResult
    plots::Dict{String,PlotlyBase.Plot}
    reduced::Bool
    nonfinite::Bool
    warnings::Vector{String}
end

"""
    panel_layout(metric::AbstractString; uirevision = PLOT_UIREVISION)::PlotlyBase.Layout

Build the layout of one panel. Takes the metric name (used as the y-axis
title) and the stable uirevision, and returns the layout with a "tick"
x-axis title, the run legend, and zero-duration transitions.
"""
function panel_layout(
    metric::AbstractString;
    uirevision::AbstractString = PLOT_UIREVISION,
)::PlotlyBase.Layout
    return PlotlyBase.Layout(
        xaxis_title = "tick",
        yaxis_title = String(metric),
        uirevision = String(uirevision),
        showlegend = true,
        legend = PlotlyBase.attr(title = PlotlyBase.attr(text = "runs")),
        transition = PlotlyBase.attr(duration = 0),
    )
end

"""
    panel_plot(traces, metric; uirevision = PLOT_UIREVISION)::PlotlyBase.Plot

Assemble one panel. Takes the panel traces and the metric name and
returns the `PlotlyBase.Plot` with the `panel_layout` of the metric.
"""
function panel_plot(
    traces::Vector{PlotlyBase.GenericTrace},
    metric::AbstractString;
    uirevision::AbstractString = PLOT_UIREVISION,
)::PlotlyBase.Plot
    return PlotlyBase.Plot(traces, panel_layout(metric; uirevision))
end

"""
    empty_panel(metric; uirevision = PLOT_UIREVISION)::PlotlyBase.Plot

Build the empty version of one panel. Takes the metric name and the
stable uirevision and returns a panel with no traces; used as the
initial reactive plot value before the first publish.
"""
function empty_panel(
    metric::AbstractString;
    uirevision::AbstractString = PLOT_UIREVISION,
)::PlotlyBase.Plot
    return panel_plot(PlotlyBase.GenericTrace[], metric; uirevision)
end

"""
    _gap_values(values::Vector{Float64})

Convert one metric series for display. Takes the values and returns a
vector of equal length where every non-finite value becomes `nothing`,
which Plotly renders as a gap in the line, plus whether a gap was
introduced.
"""
function _gap_values(values::Vector{Float64})
    gaps = Union{Float64,Nothing}[isfinite(value) ? value : nothing for value in values]
    return gaps, length(gaps) != count(isfinite, values)
end

"""
    _series_trace(series::RunSeries, metric::AbstractString, color::AbstractString, indices::Vector{Int})

Build one run trace of one panel. Takes the series, the metric name, the
run color, and the row indices to show. Returns the line trace with
`uid` `"<run-uuid>:<metric>"`, the `run_label` legend name, the run
legend group, the visibility flag, and non-finite values as gaps.
"""
function _series_trace(
    series::RunSeries,
    metric::AbstractString,
    color::AbstractString,
    indices::Vector{Int},
)
    values = series.snapshot.metrics[metric]
    gaps, had_gaps = _gap_values(Float64[values[i] for i in indices])
    trace = PlotlyBase.scatter(
        x = Int[series.snapshot.ticks[i] for i in indices],
        y = gaps;
        uid = trace_uid(series, metric),
        name = run_label(series.name, series.seed, series.snapshot.run_id),
        legendgroup = series.key,
        mode = "lines",
        connectgaps = false,
        visible = series.visible,
        line = PlotlyBase.attr(color = String(color)),
    )
    return trace, had_gaps
end

"""
    build_plots(series::Vector{RunSeries}, palette::RunPalette; hidden = Set{String}(), max_points = PANEL_MAX_POINTS, uirevision = PLOT_UIREVISION)::PlotBuildResult

Build the three dashboard panels from the selected runs. Takes the run
series, the session palette, the hidden run keys, the per-panel display
budget, and the stable uirevision. One panel per `PANEL_METRICS` entry,
one line trace per run carrying the metric (a run without the metric
gets no trace there, never a zero-filled one), x = tick. Traces of a
panel share the `max_points` display budget, reduced uniformly per trace
with `downsample_indices` above it (endpoints and the newest point are
kept) and reported in `PlotBuildResult.reduced`. Non-finite values are
rendered as gaps and reported in `PlotBuildResult.warnings`. Hidden runs
keep their traces with `visible = false` in every panel. Returns the
build result; the plots never alias the input data.
"""
function build_plots(
    series::Vector{RunSeries},
    palette::RunPalette;
    hidden::AbstractSet{String} = Set{String}(),
    max_points::Integer = PANEL_MAX_POINTS,
    uirevision::AbstractString = PLOT_UIREVISION,
)::PlotBuildResult
    max_points >= 1 || throw(ArgumentError("max_points must be >= 1, got $max_points"))
    plots = Dict{String,PlotlyBase.Plot}()
    reduced = false
    nonfinite = false
    warnings = String[]
    for metric in PANEL_METRICS
        candidates = [entry for entry in series if haskey(entry.snapshot.metrics, metric)]
        quota = isempty(candidates) ? Int(max_points) : max(2, div(Int(max_points), length(candidates)))
        traces = PlotlyBase.GenericTrace[]
        for entry in candidates
            values = entry.snapshot.metrics[metric]
            indices = DR.downsample_indices(length(values), quota)
            length(indices) < length(values) && (reduced = true)
            color = color_for!(palette, entry.key)
            trace, had_gaps = _series_trace(entry, metric, color, indices)
            if had_gaps
                nonfinite = true
                push!(
                    warnings,
                    "run \"$(entry.name)\" metric \"$metric\" has non-finite values, shown as gaps",
                )
            end
            visible = entry.visible && !(entry.key in hidden)
            trace[:visible] = visible
            push!(traces, trace)
        end
        plots[metric] = panel_plot(traces, metric; uirevision)
    end
    return PlotBuildResult(plots, reduced, nonfinite, warnings)
end
