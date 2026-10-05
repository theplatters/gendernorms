# Plot management tests of the dashboard UI layer.
#
# Covers the per-page plot model of `GenderNormsDashboard.DashboardUI`:
# the one-visible-plot switcher state (create via the plus button,
# activate, delete with the last-plot guard), the `MAX_PLOTS` cap,
# per-plot line selection isolation, run-scoped line enabling and
# dropping, the stale-event contract of the line tickboxes (a delayed
# click resolves its originating plot and is rejected once that plot is
# deleted), and the line tickbox offering of a legacy three-metric
# record (only its existing lines, never fabricated ones).

"""
    fresh_page(manager)

Build an isolated page session for plot-state tests. Takes the run
manager and returns a fresh `DashboardModel` with its `SessionState`
attached and the record catalog refreshed, like `page_ready` does.
"""
function fresh_page(manager)
    model = UI.DashboardModel()
    session = UI.SessionState(model, manager)
    model.manager[] = manager
    model.session[] = session
    session.records = DR.refresh_records!(manager)
    return model, session
end

@testset "plot state" begin
    root = mktempdir()
    old_id = string(UUIDs.uuid4())
    write_record_fixture(
        root,
        old_id;
        name = "old-record",
        ticks = [0, 1, 2],
        metrics = Dict{String, Any}(
            "working_time_men" => [0.5, 0.6, 0.7],
            "working_time_women" => [0.3, 0.35, 0.4],
            "working_time_gap" => [0.2, 0.25, 0.3],
        ),
    )
    full_id = string(UUIDs.uuid4())
    write_record_fixture(
        root,
        full_id;
        name = "full-record",
        ticks = [0, 1],
        metrics = Dict{String, Any}(
            "working_time_men" => [0.5, 0.6],
            "working_time_women" => [0.3, 0.35],
            "working_time_gap" => [0.2, 0.25],
            "preference_men" => [0.4, 0.45],
            "preference_women" => [0.4, 0.5],
            "utility_men" => [1.5, 2.5],
            "utility_women" => [1.0, 2.0],
            "transfer_mean" => [-0.5, 0.5],
        ),
    )
    manager = DR.RunManager(; runs_root = root, worker_threads = 1)
    try
        @testset "a fresh page starts with one empty plot" begin
            model, session = fresh_page(manager)
            @test length(session.plots) == 1
            @test session.active_plot_id == 1
            @test UI.active_plot_state(session).id == 1
            tabs = UI.build_plot_tabs(session)
            @test length(tabs) == 1
            @test tabs[1]["active"]
            @test !tabs[1]["can_close"]
            @test isempty(UI.build_line_groups(session, UI.RunSeries[]))
        end

        @testset "the plus button creates a plot and switches to it" begin
            model, session = fresh_page(manager)
            UI.handle_add_plot!(model)
            @test length(session.plots) == 2
            @test session.active_plot_id == 2
            tabs = UI.build_plot_tabs(session)
            @test [tab["active"] for tab in tabs] == [false, true]
            @test all(tab -> tab["can_close"], tabs)
            @test occursin("plot 2 created", model.status_line[])
        end

        @testset "only one plot is active at a time" begin
            model, session = fresh_page(manager)
            UI.handle_add_plot!(model)
            UI.handle_activate_plot!(model, Dict{String, Any}("plot_id" => "1"))
            @test session.active_plot_id == 1
            @test count(tab -> tab["active"], UI.build_plot_tabs(session)) == 1
            UI.handle_activate_plot!(model, Dict{String, Any}("plot_id" => "bogus"))
            @test session.active_plot_id == 1
        end

        @testset "selecting a run checks its lines in the active plot only" begin
            model, session = fresh_page(manager)
            UI.handle_add_plot!(model)
            UI.handle_activate_plot!(model, Dict{String, Any}("plot_id" => "1"))
            UI.handle_select_run!(model, Dict{String, Any}("key" => old_id))
            @test model.selected_runs[] == [old_id]
            @test UI.active_plot_state(session).lines == [
                UI.line_key(old_id, "working_time_men"),
                UI.line_key(old_id, "working_time_women"),
                UI.line_key(old_id, "working_time_gap"),
            ]
            @test session.plots[2].lines == String[]
        end

        @testset "tickboxes offer only the lines a run carries" begin
            model, session = fresh_page(manager)
            UI.handle_select_run!(model, Dict{String, Any}("key" => old_id))
            series, = UI.build_series!(session)
            groups = UI.build_line_groups(session, series)
            @test length(groups) == 1
            @test groups[1]["label"] == "old-record (seed 1, $(old_id[1:8]))"
            @test groups[1]["plot_id"] == "1"
            lines = groups[1]["lines"]
            @test [line["key"] for line in lines] == [
                UI.line_key(old_id, "working_time_men"),
                UI.line_key(old_id, "working_time_women"),
                UI.line_key(old_id, "working_time_gap"),
            ]
            @test all(line -> line["checked"], lines)
            @test all(line -> line["plot_id"] == "1", lines)
            @test [line["label"] for line in lines] ==
                ["Working time (men)", "Working time (women)", "Working time gap"]

            full_model, full_session = fresh_page(manager)
            UI.handle_select_run!(full_model, Dict{String, Any}("key" => full_id))
            full_series, = UI.build_series!(full_session)
            full_groups = UI.build_line_groups(full_session, full_series)
            @test [line["key"] for line in full_groups[1]["lines"]] ==
                [UI.line_key(full_id, metric) for metric in UI.KNOWN_METRICS]
        end

        @testset "a three-metric record loads and plots its own columns" begin
            model, session = fresh_page(manager)
            UI.handle_select_run!(model, Dict{String, Any}("key" => old_id))
            series, = UI.build_series!(session)
            result = UI.build_plot(series, UI.LinePalette(), UI.active_plot_state(session).lines)
            @test length(result.plot.data) == 3
            @test [trace[:uid] for trace in result.plot.data] == [
                "$old_id:working_time_men",
                "$old_id:working_time_women",
                "$old_id:working_time_gap",
            ]
            @test result.axis === :signed_fraction
        end

        @testset "tickbox changes stay inside one plot" begin
            model, session = fresh_page(manager)
            UI.handle_select_run!(model, Dict{String, Any}("key" => old_id))
            UI.handle_add_plot!(model)
            @test length(UI.active_plot_state(session).lines) == 3
            gap_line = UI.line_key(old_id, "working_time_gap")
            UI.handle_toggle_line!(
                model,
                Dict{String, Any}("line" => gap_line, "plot_id" => "2", "checked" => false),
            )
            @test length(UI.active_plot_state(session).lines) == 2
            @test !(gap_line in UI.active_plot_state(session).lines)
            @test length(session.plots[1].lines) == 3

            series, = UI.build_series!(session)
            groups = UI.build_line_groups(session, series)
            @test [line["checked"] for line in groups[1]["lines"]] == [true, true, false]
            @test [line["plot_id"] for line in groups[1]["lines"]] == ["2", "2", "2"]
            UI.handle_activate_plot!(model, Dict{String, Any}("plot_id" => "1"))
            groups = UI.build_line_groups(session, series)
            @test [line["checked"] for line in groups[1]["lines"]] == [true, true, true]
            @test [line["plot_id"] for line in groups[1]["lines"]] == ["1", "1", "1"]
        end

        @testset "a delayed tickbox click lands on its originating plot" begin
            model, session = fresh_page(manager)
            UI.handle_select_run!(model, Dict{String, Any}("key" => old_id))
            UI.handle_add_plot!(model)
            @test UI.active_plot_state(session).id == 2
            gap_line = UI.line_key(old_id, "working_time_gap")
            men_line = UI.line_key(old_id, "working_time_men")

            # a click rendered for plot 1 arrives after the page switched to plot 2
            UI.handle_toggle_line!(
                model,
                Dict{String, Any}("line" => gap_line, "plot_id" => "1", "checked" => false),
            )
            @test !(gap_line in session.plots[1].lines)
            @test length(session.plots[1].lines) == 2
            @test gap_line in session.plots[2].lines
            @test length(session.plots[2].lines) == 3
            @test UI.active_plot_state(session).id == 2

            # the desired state is applied absolutely, never as a blind toggle
            UI.handle_toggle_line!(
                model,
                Dict{String, Any}("line" => gap_line, "plot_id" => "1", "checked" => false),
            )
            @test length(session.plots[1].lines) == 2
            UI.handle_toggle_line!(
                model,
                Dict{String, Any}("line" => gap_line, "plot_id" => "1", "checked" => true),
            )
            @test gap_line in session.plots[1].lines
            @test length(session.plots[1].lines) == 3
            UI.handle_toggle_line!(
                model,
                Dict{String, Any}("line" => men_line, "plot_id" => "1", "checked" => true),
            )
            @test count(==(men_line), session.plots[1].lines) == 1
        end

        @testset "a delayed tickbox click of a deleted plot is rejected" begin
            model, session = fresh_page(manager)
            UI.handle_select_run!(model, Dict{String, Any}("key" => old_id))
            UI.handle_add_plot!(model)
            UI.handle_remove_plot!(model, Dict{String, Any}("plot_id" => "2"))
            @test [state.id for state in session.plots] == [1]
            @test UI.plot_state_by_id(session, 1) === session.plots[1]
            @test UI.plot_state_by_id(session, 2) === nothing

            gap_line = UI.line_key(old_id, "working_time_gap")
            before = copy(session.plots[1].lines)
            UI.handle_toggle_line!(
                model,
                Dict{String, Any}("line" => gap_line, "plot_id" => "2", "checked" => false),
            )
            @test session.plots[1].lines == before

            # events without a plot id or without a boolean state are rejected too
            UI.handle_toggle_line!(model, Dict{String, Any}("line" => gap_line, "checked" => false))
            @test session.plots[1].lines == before
            UI.handle_toggle_line!(model, Dict{String, Any}("line" => gap_line, "plot_id" => "1"))
            @test session.plots[1].lines == before

            # the string spelling of the desired state still applies absolutely
            UI.handle_toggle_line!(
                model,
                Dict{String, Any}("line" => gap_line, "plot_id" => "1", "checked" => "false"),
            )
            @test !(gap_line in session.plots[1].lines)
            @test length(session.plots[1].lines) == 2
        end

        @testset "unselecting a run drops its lines from every plot" begin
            model, session = fresh_page(manager)
            UI.handle_select_run!(model, Dict{String, Any}("key" => old_id))
            UI.handle_add_plot!(model)
            @test !isempty(session.plots[1].lines)
            @test !isempty(session.plots[2].lines)
            UI.handle_select_run!(model, Dict{String, Any}("key" => old_id))
            @test isempty(model.selected_runs[])
            @test all(state -> isempty(state.lines), session.plots)
        end

        @testset "the plot count is capped" begin
            model, session = fresh_page(manager)
            for _ in 2:UI.MAX_PLOTS
                UI.handle_add_plot!(model)
            end
            @test length(session.plots) == UI.MAX_PLOTS
            UI.handle_add_plot!(model)
            @test length(session.plots) == UI.MAX_PLOTS
            @test occursin("at most $(UI.MAX_PLOTS) plots", model.status_line[])
        end

        @testset "the last plot cannot be deleted" begin
            model, session = fresh_page(manager)
            UI.handle_remove_plot!(model, Dict{String, Any}("plot_id" => "1"))
            @test length(session.plots) == 1
            @test occursin("last plot", model.status_line[])
            UI.handle_add_plot!(model)
            UI.handle_add_plot!(model)
            UI.handle_remove_plot!(model, Dict{String, Any}("plot_id" => "2"))
            @test [state.id for state in session.plots] == [1, 3]
            @test session.active_plot_id == 3
            UI.handle_remove_plot!(model, Dict{String, Any}("plot_id" => "3"))
            @test [state.id for state in session.plots] == [1]
            @test session.active_plot_id == 1
            UI.handle_remove_plot!(model, Dict{String, Any}("plot_id" => "1"))
            @test length(session.plots) == 1
        end
    finally
        DR.shutdown!(manager)
    end
end
