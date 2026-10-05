# Plot construction of the dashboard UI layer.
#
# `build_plot` turns the `PathSnapshot` views of the selected runs into
# one PlotlyBase chart of individually selectable lines (one line is one
# metric of one run): x = tick, session-stable run colors, and a stable
# `uirevision` so zoom survives republishing. All plots share that
# uirevision and the trace uids, so every trace is published with
# explicit visibility and the legend is labels-only (item clicks
# disabled): the per-plot line tickboxes alone decide what a chart
# shows, never Plotly-side UI state. `METRIC_META` holds the
# dashboard-side metric metadata (title and unit class) that drives the
# y-axis and hover formatting: proportion and signed-fraction metrics
# render as percent, value metrics render raw. Display-only
# downsampling keeps every chart within a fixed point budget;
# non-finite values become gaps. This file depends only on
# `DashboardRuntime` and PlotlyBase.

"""
    MetricMeta

Dashboard-side metadata of one metric. Field `title` is the
human-readable chart and tickbox title, field `unit` the unit class of
the values: `:proportion` (share in `[0, 1]`, rendered as percent),
`:signed_fraction` (difference in `[-1, 1]`, rendered as percent), or
`:value` (raw numbers). See `METRIC_META` and `metric_meta`.
"""
struct MetricMeta
    title::String
    unit::Symbol
end

"""
    METRIC_META

Metric metadata table keyed by metric name (see `MetricMeta`): the
eight `GenderNorms` metrics with their chart titles and unit classes.
`working_time_men`, `working_time_women`, `preference_men`, and
`preference_women` are `:proportion`; `working_time_gap` and
`transfer_mean` are `:signed_fraction`; `utility_men` and
`utility_women` are `:value`. The keys equal `KNOWN_METRICS` (checked
by the test suite); metric names outside the table fall back to
`:value` behavior with a derived title (see `metric_meta`).
"""
const METRIC_META = Dict{String, MetricMeta}(
    "working_time_men" => MetricMeta("Working time (men)", :proportion),
    "working_time_women" => MetricMeta("Working time (women)", :proportion),
    "working_time_gap" => MetricMeta("Working time gap", :signed_fraction),
    "preference_men" => MetricMeta("Preference (men)", :proportion),
    "preference_women" => MetricMeta("Preference (women)", :proportion),
    "utility_men" => MetricMeta("Utility (men)", :value),
    "utility_women" => MetricMeta("Utility (women)", :value),
    "transfer_mean" => MetricMeta("Mean transfer", :signed_fraction),
)

"""
    KNOWN_METRICS

Canonical display order of the known metric names: the eight keys of
`METRIC_META`. Line tickboxes and the configuration form list metrics
in this order; unknown metric names sort after these (see
`metric_display_order`).
"""
const KNOWN_METRICS = [
    "working_time_men",
    "working_time_women",
    "working_time_gap",
    "preference_men",
    "preference_women",
    "utility_men",
    "utility_women",
    "transfer_mean",
]

"""
    metric_meta(name::AbstractString)::MetricMeta

Metadata of one metric. Takes the metric name and returns the
`METRIC_META` entry, or the `:value` fallback with a title derived from
the name (underscores become spaces, words capitalized) for unknown
names, so future metrics plot as raw values without a dashboard change.
"""
function metric_meta(name::AbstractString)::MetricMeta
    return get(METRIC_META, String(name)) do
        MetricMeta(title_from_name(name), :value)
    end
end

"""
    metric_title(name::AbstractString)::String

Human-readable title of one metric. Takes the metric name and returns
`MetricMeta.title` (see `metric_meta`), the fallback for unknown names
derived from the name.
"""
function metric_title(name::AbstractString)::String
    return metric_meta(name).title
end

"""
    metric_unit(name::AbstractString)::Symbol

Unit class of one metric. Takes the metric name and returns the
`MetricMeta.unit` class `:proportion`, `:signed_fraction`, or `:value`
(see `metric_meta`).
"""
function metric_unit(name::AbstractString)::Symbol
    return metric_meta(name).unit
end

"""
    title_from_name(name::AbstractString)::String

Derive a chart title from an unknown metric name. Takes the name and
returns it with underscores replaced by spaces and every word
capitalized, e.g. `"future_metric"` becomes `"Future Metric"`. Returns
`"value"` for the empty name.
"""
function title_from_name(name::AbstractString)::String
    words = split(String(name), '_')
    titled = join(uppercasefirst.(words), " ")
    return isempty(strip(titled)) ? "value" : titled
end

"""
    metric_display_order(names)::Vector{String}

Order metric names for display (line tickboxes and trace order). Takes
an iterable of metric names and returns the known names in
`KNOWN_METRICS` order followed by the unknown names in sorted order.
"""
function metric_display_order(names)::Vector{String}
    known = String[name for name in KNOWN_METRICS if name in names]
    unknown = sort!(String[String(name) for name in names if !(name in KNOWN_METRICS)])
    return vcat(known, unknown)
end

"""
    line_key(run_key::AbstractString, metric::AbstractString)::String

Identity of one selectable plot line. Takes the session-stable run key
and the metric name and returns `"<run key>:<metric>"`. Run keys never
contain `":"`, so the key identifies the run by its `"<run key>:"`
prefix.
"""
function line_key(run_key::AbstractString, metric::AbstractString)::String
    return string(run_key, ":", metric)
end

"""
    axis_unit(units)::Symbol

Resolve the y-axis unit class of one plot from the unit classes of its
visible lines. Returns `:proportion` (fixed range `[0, 1]`, percent
ticks 0% to 100%) only when every line is `:proportion`, `:value`
(raw values, automatic range) when any line is `:value` or the plot has
no lines, and `:signed_fraction` (fixed range `[-1, 1]`, percent ticks
-100% to 100%) for the remaining fraction-class mixtures.
"""
function axis_unit(units)::Symbol
    collected = Symbol[Symbol(unit) for unit in units]
    isempty(collected) && return :value
    any(unit -> unit === :value, collected) && return :value
    all(unit -> unit === :proportion, collected) && return :proportion
    return :signed_fraction
end

"""
    axis_label(axis::Symbol)::String

Human-readable y-axis note of one resolved axis unit (see
`axis_unit`). Returns `"y-axis: percent (0% to 100%)"` for
`:proportion`, `"y-axis: percent (-100% to 100%)"` for
`:signed_fraction`, and `"y-axis: raw values"` for `:value`.
"""
function axis_label(axis::Symbol)::String
    axis === :proportion && return "y-axis: percent (0% to 100%)"
    axis === :signed_fraction && return "y-axis: percent (-100% to 100%)"
    return "y-axis: raw values"
end

"""
    hover_template(unit::Symbol)::String

Plotly hover template of one metric. Takes the metric unit class and
returns the template that shows the tick and the value: percent with
one decimal for `:proportion` and `:signed_fraction` (values in
`[0, 1]` or `[-1, 1]` rendered as percent), raw numbers for `:value`.
The trace name is appended by Plotly.
"""
function hover_template(unit::Symbol)::String
    unit === :value && return "%{x}: %{y:.6g}<extra>%{fullData.name}</extra>"
    return "%{x}: %{y:.1%}<extra>%{fullData.name}</extra>"
end

"""
    PLOT_MAX_POINTS

Display budget per plot: at most 6000 points across all traces of one
plot. Plots above the budget downsample every trace with
`downsample_indices` and report `PlotBuildResult.reduced`.
"""
const PLOT_MAX_POINTS = 6000

"""
    PLOT_HEIGHT

Pixel height of the dashboard chart: 560, so the single visible plot
is the dominant element of the page.
"""
const PLOT_HEIGHT = 560

"""
    PLOT_UIREVISION

Stable `layout.uirevision` of every dashboard plot, so Plotly keeps the
current zoom and pan state across republished plots. Trace visibility is
never left to Plotly-side UI state: traces publish with explicit
`visible` and the legend disables item clicks (see `plot_layout`), so
the shared revision cannot leak a hidden trace from one plot into
another.
"""
const PLOT_UIREVISION = "gendernorms-dashboard"

"""
    RUN_PALETTE

Trace colors assigned to runs in order of first appearance in a
`RunPalette`. Ten distinguishable colors; runs beyond the palette cycle
through it. All lines of one run share its color across metrics and
plots.
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
and field `snapshot` the chart data with the rows the presentation
cursor currently reveals. Which of the run's metrics are drawn is
decided per plot by its line selection (see `build_plot`), never here.
"""
struct RunSeries
    key::String
    name::String
    seed::Int
    snapshot::DR.PathSnapshot
end

"""
    RunSeries(; key, snapshot, name = snapshot.name, seed = 0)

Construct a `RunSeries`. Takes the session key, the chart data, and the
optional run label and run seed. Returns the series.
"""
function RunSeries(;
        key::AbstractString,
        snapshot::DR.PathSnapshot,
        name::AbstractString = snapshot.name,
        seed::Integer = 0,
    )
    return RunSeries(String(key), String(name), Int(seed), snapshot)
end

"""
    RunPalette

Session-stable run colors. Field `order` records the run keys in order
of first appearance, field `colors` maps each known key to its assigned
hex color. `color_for!` assigns a color when a run first appears and
returns the same color on every later call, so a run keeps its color
across all plots and republishes of one session.
"""
mutable struct RunPalette
    order::Vector{String}
    colors::Dict{String, String}
end

"""
    RunPalette()

Construct an empty run palette. Takes no arguments and returns the
palette.
"""
RunPalette() = RunPalette(String[], Dict{String, String}())

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

Build the Plotly trace uid of one line: `"<run-uuid>:<metric>"` with the
core run UUID from the snapshot, falling back to the session key when
the run has no UUID yet. The uid depends only on the run and the metric,
so it is stable across plots, tickbox changes, and republishes. Returns
the uid.
"""
function trace_uid(series::RunSeries, metric::AbstractString)::String
    id = isempty(series.snapshot.run_id) ? series.key : series.snapshot.run_id
    return string(id, ":", metric)
end

"""
    PlotBuildResult

Result of `build_plot`. Field `plot` holds the `PlotlyBase.Plot` of the
selected lines, field `axis` the resolved y-axis unit class (see
`axis_unit`), field `reduced` whether the traces were downsampled for
the display budget, field `nonfinite` whether any trace carries
non-finite values, and field `warnings` the human-readable warning
lines for those values.
"""
struct PlotBuildResult
    plot::PlotlyBase.Plot
    axis::Symbol
    reduced::Bool
    nonfinite::Bool
    warnings::Vector{String}
end

"""
    _yaxis_attrs(axis::Symbol)::PlotlyBase.attr

Build the y-axis attributes of one resolved axis unit (see
`axis_unit`). Takes the axis unit and returns the attributes: `:value`
gets an automatic range and raw values, `:proportion` a fixed `[0, 1]`
range with percent ticks 0% to 100%, and `:signed_fraction` a fixed
`[-1, 1]` range with percent ticks -100% to 100%.
"""
function _yaxis_attrs(axis::Symbol)
    title = PlotlyBase.attr(
        text = axis === :proportion ? "proportion" :
            axis === :signed_fraction ? "fraction" : "value"
    )
    axis === :proportion && return PlotlyBase.attr(
        title = title,
        range = [0.0, 1.0],
        tickvals = [0.0, 0.25, 0.5, 0.75, 1.0],
        ticktext = ["0%", "25%", "50%", "75%", "100%"],
    )
    axis === :signed_fraction && return PlotlyBase.attr(
        title = title,
        range = [-1.0, 1.0],
        tickvals = [-1.0, -0.5, 0.0, 0.5, 1.0],
        ticktext = ["-100%", "-50%", "0%", "50%", "100%"],
    )
    return PlotlyBase.attr(title = title)
end

"""
    plot_layout(axis::Symbol; uirevision = PLOT_UIREVISION, height = PLOT_HEIGHT)::PlotlyBase.Layout

Build the layout of one dashboard plot. Takes the resolved y-axis unit
(see `axis_unit`) and the stable uirevision and pixel height, and
returns the layout with a "tick" x-axis title, the `axis_unit`-specific
y-axis, the run legend as a labels-only key (legend item clicks and
double clicks disabled, since the per-plot line tickboxes are the
authoritative visibility control), zero-duration transitions, and the
fixed plot height.
"""
function plot_layout(
        axis::Symbol;
        uirevision::AbstractString = PLOT_UIREVISION,
        height::Integer = PLOT_HEIGHT,
    )::PlotlyBase.Layout
    return PlotlyBase.Layout(
        xaxis = PlotlyBase.attr(title = PlotlyBase.attr(text = "tick")),
        yaxis = _yaxis_attrs(axis),
        height = Int(height),
        uirevision = String(uirevision),
        showlegend = true,
        legend = PlotlyBase.attr(
            title = PlotlyBase.attr(text = "lines"),
            itemclick = false,
            itemdoubleclick = false,
        ),
        transition = PlotlyBase.attr(duration = 0),
    )
end

"""
    assemble_plot(traces, axis; uirevision = PLOT_UIREVISION, height = PLOT_HEIGHT)::PlotlyBase.Plot

Assemble one dashboard plot. Takes the plot traces and the resolved
y-axis unit and returns the `PlotlyBase.Plot` with the `plot_layout` of
that axis unit.
"""
function assemble_plot(
        traces::Vector{PlotlyBase.GenericTrace},
        axis::Symbol;
        uirevision::AbstractString = PLOT_UIREVISION,
        height::Integer = PLOT_HEIGHT,
    )::PlotlyBase.Plot
    return PlotlyBase.Plot(traces, plot_layout(axis; uirevision, height))
end

"""
    empty_plot(; uirevision = PLOT_UIREVISION, height = PLOT_HEIGHT)::PlotlyBase.Plot

Build an empty dashboard plot. Takes the stable uirevision and pixel
height and returns a plot with no traces and the `:value` axis unit;
used as the initial reactive chart value before the first publish.
"""
function empty_plot(;
        uirevision::AbstractString = PLOT_UIREVISION,
        height::Integer = PLOT_HEIGHT,
    )::PlotlyBase.Plot
    return assemble_plot(PlotlyBase.GenericTrace[], :value; uirevision, height)
end

"""
    _gap_values(values::Vector{Float64})

Convert one metric series for display. Takes the values and returns a
vector of equal length where every non-finite value becomes `nothing`,
which Plotly renders as a gap in the line, plus whether a gap was
introduced.
"""
function _gap_values(values::Vector{Float64})
    gaps = Union{Float64, Nothing}[isfinite(value) ? value : nothing for value in values]
    return gaps, length(gaps) != count(isfinite, values)
end

"""
    _series_trace(series::RunSeries, metric::AbstractString, color::AbstractString, indices::Vector{Int})

Build one line trace of one plot. Takes the series, the metric name, the
run color, and the row indices to show. Returns the line trace with
`uid` `"<run-uuid>:<metric>"`, the `run_label` plus metric title as
legend name (labels-only, no legend group), explicit `visible = true`
so every republish restores the tickbox-selected lines regardless of
Plotly-side UI state, the metric's hover template, and non-finite values
as gaps.
"""
function _series_trace(
        series::RunSeries,
        metric::AbstractString,
        color::AbstractString,
        indices::Vector{Int},
    )
    values = series.snapshot.metrics[metric]
    gaps, had_gaps = _gap_values(Float64[values[i] for i in indices])
    name = string(run_label(series.name, series.seed, series.snapshot.run_id), " - ", metric_title(metric))
    trace = PlotlyBase.scatter(
        x = Int[series.snapshot.ticks[i] for i in indices],
        y = gaps;
        uid = trace_uid(series, metric),
        name = name,
        visible = true,
        mode = "lines",
        connectgaps = false,
        hovertemplate = hover_template(metric_unit(metric)),
        line = PlotlyBase.attr(color = String(color)),
    )
    return trace, had_gaps
end

"""
    build_plot(series::Vector{RunSeries}, palette::RunPalette, selected; max_points = PLOT_MAX_POINTS, uirevision = PLOT_UIREVISION)::PlotBuildResult

Build one dashboard plot from the selected runs and one plot's line
selection. Takes the run series, the session palette, the selected line
keys (see `line_key`), the per-plot display budget, and the stable
uirevision. One line trace per selected `(run, metric)` combination the
run actually carries (a run without the metric gets no trace there,
never a zero-filled one), x = tick; selected keys that match no run or
metric are ignored. Traces share the `max_points` display budget,
reduced uniformly per trace with `downsample_indices` above it
(endpoints and the newest point are kept) and reported in
`PlotBuildResult.reduced`. Only selected lines get a trace and every
trace publishes with explicit `visible = true`, so the chart always
shows exactly the plot's tickbox selection. Non-finite values are
rendered as gaps and reported in `PlotBuildResult.warnings`. The y-axis
follows `axis_unit` over the visible lines: percent 0% to 100% for
proportions only, percent -100% to 100% for fraction-class mixtures,
raw values with an automatic range when any line is `:value`. Returns
the build result; the plot never aliases the input data.
"""
function build_plot(
        series::Vector{RunSeries},
        palette::RunPalette,
        selected;
        max_points::Integer = PLOT_MAX_POINTS,
        uirevision::AbstractString = PLOT_UIREVISION,
    )::PlotBuildResult
    max_points >= 1 || throw(ArgumentError("max_points must be >= 1, got $max_points"))
    wanted = Set{String}(String(entry) for entry in selected)
    lines = Tuple{RunSeries, String}[]
    for entry in series
        for metric in metric_display_order(entry.snapshot.metric_names)
            line_key(entry.key, metric) in wanted && push!(lines, (entry, metric))
        end
    end
    axis = axis_unit(metric_unit(metric) for (_, metric) in lines)
    quota = isempty(lines) ? Int(max_points) : max(2, div(Int(max_points), length(lines)))
    traces = PlotlyBase.GenericTrace[]
    reduced = false
    nonfinite = false
    warnings = String[]
    for (entry, metric) in lines
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
        push!(traces, trace)
    end
    return PlotBuildResult(assemble_plot(traces, axis; uirevision), axis, reduced, nonfinite, warnings)
end
