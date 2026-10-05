# Plot construction tests of the dashboard UI layer.
#
# Covers `GenderNormsDashboard.DashboardUI` plot building: the metric
# metadata table and its unknown-metric fallback, per-plot line
# selection (tickbox state to traces), trace uids, labels, and
# session-stable run colors, missing metrics without traces, non-finite
# values as flagged gaps, the display budget with endpoint-preserving
# downsampling, stable `uirevision`, the labels-only legend whose
# disabled item clicks and explicit trace visibility keep Plotly-side UI
# state from leaking between plots, and the three y-axis unit-class
# behaviors with their percent tick and hover formatting.

"""
    make_snapshot(; kwargs...)

Build a `PathSnapshot` for plotting tests. Takes the run id, name,
source, state, tick counts, metric series, and data revision and returns
the snapshot with rows aligned across all metrics.
"""
function make_snapshot(;
        run_id = "run-1",
        name = "test",
        source = :live,
        state = DR.JOB_RUNNING,
        ticks = Int[0, 1, 2, 3, 4],
        metrics = Dict{String, Vector{Float64}}(
            "working_time_men" => Float64[1.0, 2.0, 3.0, 4.0, 5.0],
            "working_time_women" => Float64[0.5, 1.5, 2.5, 3.5, 4.5],
            "working_time_gap" => Float64[0.5, 0.5, 0.5, 0.5, 0.5],
        ),
        revision = 0,
    )
    rows = length(ticks)
    return DR.PathSnapshot(
        String(run_id),
        String(name),
        source,
        state,
        rows,
        rows,
        rows,
        rows,
        copy(ticks),
        Dict{String, Vector{Float64}}(key => copy(values) for (key, values) in metrics),
        sort!(collect(keys(metrics))),
        "",
        String[],
        Int(revision),
    )
end

"""
    series_of(key, snapshot; name = snapshot.name, seed = 0)

Build one `RunSeries` for plotting tests. Returns the series.
"""
function series_of(key, snapshot; name = snapshot.name, seed = 0)
    return UI.RunSeries(; key, snapshot, name, seed)
end

"""
    selected_lines(entries...)

Build one line selection from `(run key, metric)` pairs. Returns the
line keys.
"""
function selected_lines(entries...)
    return String[UI.line_key(run_key, metric) for (run_key, metric) in entries]
end

"""
    plot_points(plot)::Int

Total number of x-values across all traces of one plot. Returns the
count.
"""
plot_points(plot) = sum(length(trace[:x]) for trace in plot.data; init = 0)

@testset "plotting" begin
    @testset "metric metadata covers the model metrics" begin
        @test Set(UI.KNOWN_METRICS) == Set(keys(UI.METRIC_META))
        @test length(UI.KNOWN_METRICS) == 8
        @test UI.metric_unit("working_time_men") === :proportion
        @test UI.metric_unit("working_time_women") === :proportion
        @test UI.metric_unit("working_time_gap") === :signed_fraction
        @test UI.metric_unit("preference_men") === :proportion
        @test UI.metric_unit("preference_women") === :proportion
        @test UI.metric_unit("utility_men") === :value
        @test UI.metric_unit("utility_women") === :value
        @test UI.metric_unit("transfer_mean") === :signed_fraction
        @test UI.metric_title("working_time_gap") == "Working time gap"
    end

    @testset "unknown metrics fall back to raw values" begin
        @test UI.metric_meta("future_metric").unit === :value
        @test UI.metric_title("future_metric") == "Future Metric"
        @test UI.metric_title("another_one") == "Another One"
    end

    @testset "metrics display in canonical order, unknown names last" begin
        @test UI.metric_display_order(["transfer_mean", "zz_unknown", "working_time_men"]) ==
            ["working_time_men", "transfer_mean", "zz_unknown"]
    end

    @testset "line keys identify run and metric" begin
        @test UI.line_key("run-1", "working_time_men") == "run-1:working_time_men"
    end

    @testset "tickbox selection builds exactly those traces" begin
        snapshot_a = make_snapshot(run_id = "aaaaaaaa-1111", name = "alpha")
        snapshot_b = make_snapshot(run_id = "bbbbbbbb-2222", name = "beta")
        series = [
            series_of("key-a", snapshot_a; name = "alpha", seed = 3),
            series_of("key-b", snapshot_b; name = "beta", seed = 7),
        ]
        selection = selected_lines(("key-a", "working_time_men"), ("key-b", "working_time_gap"))
        result = UI.build_plot(series, UI.RunPalette(), selection)

        @test length(result.plot.data) == 2
        @test [trace[:uid] for trace in result.plot.data] ==
            ["aaaaaaaa-1111:working_time_men", "bbbbbbbb-2222:working_time_gap"]
        @test result.plot.data[1][:name] == "alpha (seed 3, aaaaaaaa) - Working time (men)"
        @test result.plot.data[2][:name] == "beta (seed 7, bbbbbbbb) - Working time gap"

        nothing_selected = UI.build_plot(series, UI.RunPalette(), String[])
        @test isempty(nothing_selected.plot.data)

        stale = UI.build_plot(series, UI.RunPalette(), selected_lines(("gone", "working_time_men")))
        @test isempty(stale.plot.data)
    end

    @testset "colors and uids are stable across rebuilds and plots" begin
        snapshot_a = make_snapshot(run_id = "aaaaaaaa-1111", name = "alpha")
        snapshot_b = make_snapshot(run_id = "bbbbbbbb-2222", name = "beta")
        series = [
            series_of("key-a", snapshot_a; name = "alpha", seed = 3),
            series_of("key-b", snapshot_b; name = "beta", seed = 7),
        ]
        selection = selected_lines(
            ("key-a", "working_time_men"),
            ("key-b", "working_time_men"),
            ("key-a", "working_time_gap"),
        )
        palette = UI.RunPalette()
        first_result = UI.build_plot(series, palette, selection)
        men_colors = [trace[:line][:color] for trace in first_result.plot.data if endswith(trace[:uid], "working_time_men")]
        @test length(men_colors) == 2
        @test men_colors[1] != men_colors[2]

        rebuilt = UI.build_plot(series, palette, selection)
        @test [trace[:line][:color] for trace in rebuilt.plot.data] ==
            [trace[:line][:color] for trace in first_result.plot.data]

        fresh = UI.build_plot(series, UI.RunPalette(), selection)
        @test [trace[:line][:color] for trace in fresh.plot.data] ==
            [trace[:line][:color] for trace in first_result.plot.data]

        other_selection = selected_lines(("key-a", "working_time_gap"))
        other_plot = UI.build_plot(series, palette, other_selection)
        @test other_plot.plot.data[1][:uid] == first_result.plot.data[2][:uid]
        @test other_plot.plot.data[1][:line][:color] == first_result.plot.data[2][:line][:color]
    end

    @testset "missing metrics produce no trace, never zero-fill" begin
        snapshot = make_snapshot(
            metrics = Dict{String, Vector{Float64}}(
                "working_time_men" => Float64[1.0, 2.0, 3.0, 4.0, 5.0],
            ),
        )
        selection = selected_lines(
            ("key", "working_time_men"),
            ("key", "working_time_women"),
            ("key", "working_time_gap"),
        )
        result = UI.build_plot([series_of("key", snapshot)], UI.RunPalette(), selection)
        @test length(result.plot.data) == 1
        @test result.plot.data[1][:uid] == "run-1:working_time_men"
    end

    @testset "non-finite values render as gaps with a warning flag" begin
        snapshot = make_snapshot(
            run_id = "cccccccc-3333",
            name = "gamma",
            metrics = Dict{String, Vector{Float64}}(
                "working_time_men" => Float64[1.0, NaN, 3.0, Inf, 5.0],
            ),
        )
        selection = selected_lines(("key", "working_time_men"))
        result = UI.build_plot([series_of("key", snapshot)], UI.RunPalette(), selection)
        @test result.nonfinite
        @test !isempty(result.warnings)
        @test any(line -> occursin("non-finite", line), result.warnings)
        values = result.plot.data[1][:y]
        @test values[1] == 1.0
        @test values[2] === nothing
        @test values[3] == 3.0
        @test values[4] === nothing
        @test values[5] == 5.0

        clean = UI.build_plot([series_of("key", make_snapshot())], UI.RunPalette(), selection)
        @test !clean.nonfinite
        @test isempty(clean.warnings)
    end

    @testset "downsampling stays in budget and preserves endpoints" begin
        ticks = collect(0:19999)
        long_metrics = Dict{String, Vector{Float64}}(
            "working_time_men" => Float64.(ticks),
            "working_time_women" => Float64.(ticks) ./ 2,
            "working_time_gap" => Float64.(ticks) ./ 4,
        )
        all_three = selected_lines(
            ("key-1", "working_time_men"),
            ("key-1", "working_time_women"),
            ("key-1", "working_time_gap"),
        )
        one = UI.build_plot(
            [series_of("key-1", make_snapshot(run_id = "run-1", ticks = ticks, metrics = long_metrics))],
            UI.RunPalette(),
            all_three,
        )
        @test one.reduced
        @test plot_points(one.plot) <= UI.PLOT_MAX_POINTS
        for trace in one.plot.data
            @test trace[:x][1] == 0
            @test trace[:x][end] == 19999
        end

        six = vcat(
            all_three, selected_lines(
                ("key-2", "working_time_men"),
                ("key-2", "working_time_women"),
                ("key-2", "working_time_gap"),
            )
        )
        two = UI.build_plot(
            [
                series_of("key-1", make_snapshot(run_id = "run-1", ticks = ticks, metrics = long_metrics)),
                series_of("key-2", make_snapshot(run_id = "run-2", ticks = ticks, metrics = long_metrics)),
            ],
            UI.RunPalette(),
            six,
        )
        @test two.reduced
        @test plot_points(two.plot) <= UI.PLOT_MAX_POINTS

        small = UI.build_plot(
            [series_of("key-1", make_snapshot())],
            UI.RunPalette(),
            selected_lines(("key-1", "working_time_men")),
        )
        @test !small.reduced
        @test plot_points(small.plot) == 5
    end

    @testset "proportion-only plots span 0 to 100 percent" begin
        snapshot = make_snapshot(
            metrics = Dict{String, Vector{Float64}}(
                "working_time_men" => Float64[0.1, 0.2, 0.3, 0.4, 0.5],
                "preference_women" => Float64[0.5, 0.4, 0.3, 0.2, 0.1],
            ),
        )
        selection = selected_lines(("key", "working_time_men"), ("key", "preference_women"))
        result = UI.build_plot([series_of("key", snapshot)], UI.RunPalette(), selection)
        @test result.axis === :proportion
        yaxis = result.plot.layout[:yaxis]
        @test yaxis[:range] == [0.0, 1.0]
        @test yaxis[:tickvals] == [0.0, 0.25, 0.5, 0.75, 1.0]
        @test yaxis[:ticktext] == ["0%", "25%", "50%", "75%", "100%"]
        for trace in result.plot.data
            @test occursin("%{y:.1%}", trace[:hovertemplate])
        end
    end

    @testset "fraction-class mixtures span -100 to 100 percent" begin
        snapshot = make_snapshot(
            metrics = Dict{String, Vector{Float64}}(
                "working_time_men" => Float64[0.1, 0.2, 0.3, 0.4, 0.5],
                "working_time_gap" => Float64[-0.25, -0.5, 0.0, 0.5, 1.0],
                "transfer_mean" => Float64[-1.0, -0.5, 0.0, 0.5, 1.0],
            ),
        )
        mixed = UI.build_plot(
            [series_of("key", snapshot)],
            UI.RunPalette(),
            selected_lines(("key", "working_time_men"), ("key", "working_time_gap")),
        )
        @test mixed.axis === :signed_fraction
        yaxis = mixed.plot.layout[:yaxis]
        @test yaxis[:range] == [-1.0, 1.0]
        @test yaxis[:tickvals] == [-1.0, -0.5, 0.0, 0.5, 1.0]
        @test yaxis[:ticktext] == ["-100%", "-50%", "0%", "50%", "100%"]

        signed_only = UI.build_plot(
            [series_of("key", snapshot)],
            UI.RunPalette(),
            selected_lines(("key", "transfer_mean")),
        )
        @test signed_only.axis === :signed_fraction
        @test signed_only.plot.layout[:yaxis][:range] == [-1.0, 1.0]
    end

    @testset "value metrics use raw values and automatic range" begin
        snapshot = make_snapshot(
            metrics = Dict{String, Vector{Float64}}(
                "utility_men" => Float64[1.5, 2.5, 3.5, 4.5, 5.5],
                "working_time_men" => Float64[0.1, 0.2, 0.3, 0.4, 0.5],
            ),
        )
        result = UI.build_plot(
            [series_of("key", snapshot)],
            UI.RunPalette(),
            selected_lines(("key", "utility_men"), ("key", "working_time_men")),
        )
        @test result.axis === :value
        @test !haskey(result.plot.layout[:yaxis], :range)
        by_uid = Dict(trace[:uid] => trace for trace in result.plot.data)
        @test occursin("%{y:.6g}", by_uid["run-1:utility_men"][:hovertemplate])
        @test occursin("%{y:.1%}", by_uid["run-1:working_time_men"][:hovertemplate])
    end

    @testset "unknown metrics plot as raw values in a mixed plot" begin
        snapshot = make_snapshot(
            metrics = Dict{String, Vector{Float64}}(
                "mystery_metric" => Float64[1.0, 2.0, 3.0, 4.0, 5.0],
                "working_time_men" => Float64[0.1, 0.2, 0.3, 0.4, 0.5],
            ),
        )
        result = UI.build_plot(
            [series_of("key", snapshot)],
            UI.RunPalette(),
            selected_lines(("key", "mystery_metric"), ("key", "working_time_men")),
        )
        @test result.axis === :value
        @test !haskey(result.plot.layout[:yaxis], :range)
        names = [trace[:name] for trace in result.plot.data]
        @test any(name -> occursin("Mystery Metric", name), names)
    end

    @testset "uirevision and axis titles are stable" begin
        snapshot = make_snapshot()
        selection = selected_lines(("key", "working_time_men"))
        first_result = UI.build_plot([series_of("key", snapshot)], UI.RunPalette(), selection)
        second_result = UI.build_plot([series_of("key", snapshot)], UI.RunPalette(), selection)
        for result in (first_result, second_result)
            layout = result.plot.layout
            @test layout[:uirevision] == UI.PLOT_UIREVISION
            @test layout[:transition][:duration] == 0
            @test layout[:xaxis][:title][:text] == "tick"
            @test layout[:height] == UI.PLOT_HEIGHT
            @test UI.PLOT_HEIGHT >= 500
        end
        @test first_result.plot.layout[:yaxis][:title][:text] == "proportion"
        @test second_result.plot.layout[:yaxis][:title][:text] == "proportion"
        @test UI.axis_label(:proportion) == "y-axis: percent (0% to 100%)"
        @test UI.axis_label(:signed_fraction) == "y-axis: percent (-100% to 100%)"
        @test UI.axis_label(:value) == "y-axis: raw values"
    end

    @testset "the legend is labels-only and visibility follows the tickboxes" begin
        snapshot = make_snapshot()
        series = [series_of("key", snapshot)]
        selection = selected_lines(("key", "working_time_men"), ("key", "working_time_gap"))
        result = UI.build_plot(series, UI.RunPalette(), selection)

        # legend item clicks are disabled and every trace publishes
        # explicitly visible: the tickboxes alone decide visibility
        legend = result.plot.layout[:legend]
        @test legend[:itemclick] == false
        @test legend[:itemdoubleclick] == false
        @test result.plot.layout[:showlegend]
        @test all(trace -> trace[:visible] == true, result.plot.data)
        @test all(trace -> !haskey(trace, :legendgroup), result.plot.data)

        # a simulated Plotly-side visibility change never survives the
        # next publish of the same lines
        for trace in result.plot.data
            trace[:visible] = "legendonly"
        end
        republished = UI.build_plot(series, UI.RunPalette(), selection)
        @test [trace[:visible] for trace in republished.plot.data] == [true, true]

        # an unchecked line gets no trace at all, so the chart shows
        # exactly the tickbox selection
        reduced = UI.build_plot(series, UI.RunPalette(), selected_lines(("key", "working_time_gap")))
        @test [trace[:uid] for trace in reduced.plot.data] == ["run-1:working_time_gap"]
        @test reduced.plot.data[1][:visible] == true
        @test reduced.plot.layout[:legend][:itemclick] == false
    end

    @testset "labels and uids fall back for nameless runs" begin
        @test UI.run_label("demo", 5, "12345678-aaaa") == "demo (seed 5, 12345678)"
        @test UI.run_label("", 0, "") == "run (seed 0)"
        snapshot = make_snapshot(run_id = "", name = "live")
        @test UI.trace_uid(series_of("job-9", snapshot), "working_time_men") == "job-9:working_time_men"
    end
end
