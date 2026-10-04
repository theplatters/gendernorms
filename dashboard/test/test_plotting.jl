# Plot construction tests of the dashboard UI layer.
#
# Covers `GenderNormsDashboard.DashboardUI` plot building: trace uids,
# labels, and session-stable run colors, one panel per metric, missing
# metrics without traces, non-finite values as flagged gaps, the display
# budget with endpoint-preserving downsampling, stable `uirevision`, and
# visibility toggles across panels.

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
    metrics = Dict{String,Vector{Float64}}(
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
        Dict{String,Vector{Float64}}(key => copy(values) for (key, values) in metrics),
        sort!(collect(keys(metrics))),
        "",
        String[],
        Int(revision),
    )
end

"""
    series_of(key, snapshot; name = snapshot.name, seed = 0, visible = true)

Build one `RunSeries` for plotting tests. Returns the series.
"""
function series_of(key, snapshot; name = snapshot.name, seed = 0, visible = true)
    return UI.RunSeries(; key, snapshot, name, seed, visible)
end

"""
    panel_points(plot)::Int

Total number of x-values across all traces of one panel plot. Returns
the count.
"""
panel_points(plot) = sum(length(trace[:x]) for trace in plot.data; init = 0)

@testset "plotting" begin
    @testset "traces carry uids, labels, and one color per run" begin
        snapshot_a = make_snapshot(run_id = "aaaaaaaa-1111", name = "alpha")
        snapshot_b = make_snapshot(run_id = "bbbbbbbb-2222", name = "beta")
        series = [
            series_of("key-a", snapshot_a; name = "alpha", seed = 3),
            series_of("key-b", snapshot_b; name = "beta", seed = 7),
        ]
        palette = UI.RunPalette()
        result = UI.build_plots(series, palette)

        @test sort(collect(keys(result.plots))) == sort(copy(UI.PANEL_METRICS))
        men = result.plots["working_time_men"]
        @test [trace[:uid] for trace in men.data] ==
            ["aaaaaaaa-1111:working_time_men", "bbbbbbbb-2222:working_time_men"]
        @test [trace[:name] for trace in men.data] ==
            ["alpha (seed 3, aaaaaaaa)", "beta (seed 7, bbbbbbbb)"]

        men_colors = [trace[:line][:color] for trace in men.data]
        gap_colors = [trace[:line][:color] for trace in result.plots["working_time_gap"].data]
        @test men_colors == gap_colors
        @test men_colors[1] != men_colors[2]

        rebuilt = UI.build_plots(series, palette)
        @test [trace[:line][:color] for trace in rebuilt.plots["working_time_men"].data] == men_colors

        fresh = UI.build_plots(series, UI.RunPalette())
        @test [trace[:line][:color] for trace in fresh.plots["working_time_men"].data] == men_colors
    end

    @testset "missing metrics produce no trace, never zero-fill" begin
        snapshot = make_snapshot(
            metrics = Dict{String,Vector{Float64}}(
                "working_time_men" => Float64[1.0, 2.0, 3.0, 4.0, 5.0],
            ),
        )
        result = UI.build_plots([series_of("key", snapshot)], UI.RunPalette())
        @test length(result.plots["working_time_men"].data) == 1
        @test isempty(result.plots["working_time_women"].data)
        @test isempty(result.plots["working_time_gap"].data)
    end

    @testset "non-finite values render as gaps with a warning flag" begin
        snapshot = make_snapshot(
            run_id = "cccccccc-3333",
            name = "gamma",
            metrics = Dict{String,Vector{Float64}}(
                "working_time_men" => Float64[1.0, NaN, 3.0, Inf, 5.0],
            ),
        )
        result = UI.build_plots([series_of("key", snapshot)], UI.RunPalette())
        @test result.nonfinite
        @test !isempty(result.warnings)
        @test any(line -> occursin("non-finite", line), result.warnings)
        values = result.plots["working_time_men"].data[1][:y]
        @test values[1] == 1.0
        @test values[2] === nothing
        @test values[3] == 3.0
        @test values[4] === nothing
        @test values[5] == 5.0

        clean = UI.build_plots([series_of("key", make_snapshot())], UI.RunPalette())
        @test !clean.nonfinite
        @test isempty(clean.warnings)
    end

    @testset "downsampling stays in budget and preserves endpoints" begin
        ticks = collect(0:19999)
        long_metrics = Dict{String,Vector{Float64}}(
            "working_time_men" => Float64.(ticks),
            "working_time_women" => Float64.(ticks) ./ 2,
            "working_time_gap" => Float64.(ticks) ./ 4,
        )
        one = UI.build_plots(
            [series_of("key-1", make_snapshot(run_id = "run-1", ticks = ticks, metrics = long_metrics))],
            UI.RunPalette(),
        )
        @test one.reduced
        @test panel_points(one.plots["working_time_men"]) <= UI.PANEL_MAX_POINTS
        trace = one.plots["working_time_men"].data[1]
        @test trace[:x][1] == 0
        @test trace[:x][end] == 19999
        @test trace[:y][end] == 19999.0

        two = UI.build_plots(
            [
                series_of("key-1", make_snapshot(run_id = "run-1", ticks = ticks, metrics = long_metrics)),
                series_of("key-2", make_snapshot(run_id = "run-2", ticks = ticks, metrics = long_metrics)),
            ],
            UI.RunPalette(),
        )
        @test two.reduced
        @test panel_points(two.plots["working_time_men"]) <= UI.PANEL_MAX_POINTS
        for trace in two.plots["working_time_gap"].data
            @test trace[:x][1] == 0
            @test trace[:x][end] == 19999
        end

        small = UI.build_plots([series_of("key-1", make_snapshot())], UI.RunPalette())
        @test !small.reduced
        @test panel_points(small.plots["working_time_men"]) == 5
    end

    @testset "uirevision and axis titles are stable" begin
        snapshot = make_snapshot()
        first_result = UI.build_plots([series_of("key", snapshot)], UI.RunPalette())
        second_result = UI.build_plots([series_of("key", snapshot)], UI.RunPalette())
        for metric in UI.PANEL_METRICS
            layout = first_result.plots[metric].layout
            @test layout[:uirevision] == UI.PLOT_UIREVISION
            @test layout[:uirevision] == second_result.plots[metric].layout[:uirevision]
            @test layout[:transition][:duration] == 0
            @test layout[:xaxis][:title][:text] == "tick"
            @test layout[:yaxis][:title][:text] == metric
        end
    end

    @testset "visibility toggles apply across all panels" begin
        hidden_series = [
            series_of("key-1", make_snapshot(run_id = "run-1"); visible = true),
            series_of("key-2", make_snapshot(run_id = "run-2"); visible = false),
        ]
        result = UI.build_plots(hidden_series, UI.RunPalette())
        for metric in UI.PANEL_METRICS
            @test [trace[:visible] for trace in result.plots[metric].data] == [true, false]
        end
        via_hidden = UI.build_plots(
            [series_of("key-1", make_snapshot(run_id = "run-1"))],
            UI.RunPalette();
            hidden = Set(["key-1"]),
        )
        for metric in UI.PANEL_METRICS
            @test [trace[:visible] for trace in via_hidden.plots[metric].data] == [false]
        end
    end

    @testset "labels and uids fall back for nameless runs" begin
        @test UI.run_label("demo", 5, "12345678-aaaa") == "demo (seed 5, 12345678)"
        @test UI.run_label("", 0, "") == "run (seed 0)"
        snapshot = make_snapshot(run_id = "", name = "live")
        @test UI.trace_uid(series_of("job-9", snapshot), "working_time_men") == "job-9:working_time_men"
    end
end
