# Presentation cursor and publish throttle tests of the dashboard UI
# layer.
#
# Covers `GenderNormsDashboard.DashboardUI` presentation pacing: the
# reveal quota of one UI update, the lag label while the cursor trails
# execution, "Jump to latest", the publish throttle (one publish per
# window, only on changed data), recorded runs showing complete paths
# initially with a replay mode on the same cursor, run-row notes that
# surface invalid record columns, and revision-driven republishing when
# a loaded record is replaced with changed data. Also covers the plot
# contract of the publish flow (a switch inside a throttle window
# publishes the final active plot; plot creation and switching never
# restart or skip the shared per-run reveal cursor) and the
# labels-only legend whose trace visibility is rebuilt from the
# tickbox state on every publish.

@testset "presentation" begin
    @testset "reveal quota matches the frame budget" begin
        @test UI.REVEAL_FRAMES == 20
        @test UI.reveal_quota(500) == 25
        @test UI.reveal_quota(50) == 3
        @test UI.reveal_quota(39) == 2
        @test UI.reveal_quota(5) == 1
        @test UI.reveal_quota(0) == 1
    end

    @testset "a fast run animates in about twenty frames" begin
        cursor = UI.PresentationCursor("key"; rows = 0)
        frames = 0
        while UI.is_lagging(cursor, 500)
            before = cursor.visible_rows
            visible = UI.advance_cursor!(cursor, 500, 500)
            @test visible - before <= UI.reveal_quota(500)
            @test visible == min(500, before + 25)
            frames += 1
        end
        @test frames == 20
        @test cursor.visible_rows == 500
        @test UI.advance_cursor!(cursor, 500, 500) == 500
    end

    @testset "labels distinguish running from replaying" begin
        @test UI.status_label(DR.JOB_RUNNING, false) == "running"
        @test UI.status_label(DR.JOB_STARTING, false) == "running"
        @test UI.status_label(DR.JOB_RUNNING, true) == "replaying buffered metrics"
        @test UI.status_label(DR.JOB_COMPLETED, false) == "completed"
        @test UI.status_label(DR.JOB_QUEUED, false) == "queued"
        @test UI.state_label(DR.JOB_CANCELLED) == "cancelled"
    end

    @testset "jump to latest snaps the cursor" begin
        cursor = UI.PresentationCursor("key"; rows = 0)
        UI.advance_cursor!(cursor, 200, 200)
        @test cursor.visible_rows == 10
        @test UI.is_lagging(cursor, 200)
        @test UI.status_label(DR.JOB_RUNNING, UI.is_lagging(cursor, 200)) == "replaying buffered metrics"
        visible = UI.advance_cursor!(cursor, 200, 200; snap = true)
        @test visible == 200
        @test cursor.visible_rows == 200
        @test !UI.is_lagging(cursor, 200)
        @test UI.status_label(DR.JOB_RUNNING, UI.is_lagging(cursor, 200)) == "running"
    end

    @testset "publishes are throttled and skip unchanged data" begin
        gate = UI.PublishGate()
        @test UI.can_publish!(gate, UInt64(1), 100.0)
        @test !UI.can_publish!(gate, UInt64(1), 100.05)
        @test !UI.can_publish!(gate, UInt64(2), 100.05)
        @test !UI.can_publish!(gate, UInt64(2), 100.09)
        @test UI.can_publish!(gate, UInt64(2), 100.11)
        @test !UI.can_publish!(gate, UInt64(2), 100.5)
        @test UI.can_publish!(gate, UInt64(2), 100.5; force = true)
        @test UI.PUBLISH_INTERVAL == 0.1
    end

    @testset "recorded runs show complete paths initially" begin
        cursor = UI.PresentationCursor("key"; rows = 100)
        @test cursor.visible_rows == 100
        @test !UI.is_lagging(cursor, 100)
        @test UI.advance_cursor!(cursor, 100, 100) == 100
        @test UI.status_label(DR.JOB_COMPLETED, UI.is_lagging(cursor, 100)) == "completed"
    end

    @testset "replay mode uses the same cursor" begin
        cursor = UI.PresentationCursor("key"; rows = 100)
        @test UI.start_replay!(cursor) == 0
        @test cursor.replay
        @test UI.is_lagging(cursor, 100)
        @test UI.status_label(DR.JOB_COMPLETED, UI.is_lagging(cursor, 100)) == "replaying buffered metrics"
        @test UI.advance_cursor!(cursor, 100, 100) == UI.reveal_quota(100)
        @test UI.advance_cursor!(cursor, 100, 100; snap = true) == 100
    end

    @testset "invalid columns are excluded with a visible run-row note" begin
        root = mktempdir()
        run_id = string(UUIDs.uuid4())
        write_record_fixture(
            root,
            run_id;
            ticks = [0, 1, 2],
            metrics = Dict{String, Any}(
                "working_time_gap" => [0.1, 0.2, 0.3],
                "working_time_men" => [0.5],
            ),
        )
        manager = DR.RunManager(; runs_root = root, worker_threads = 1)
        try
            DR.load_record!(manager, run_id)
            model = UI.DashboardModel()
            session = UI.SessionState(model, manager)
            session.records = DR.refresh_records!(manager)

            snapshot = DR.path_snapshot(manager, run_id)
            series = [UI.RunSeries(; key = run_id, snapshot)]
            selected = String[
                UI.line_key(run_id, "working_time_gap"),
                UI.line_key(run_id, "working_time_men"),
            ]
            result = UI.build_plot(series, UI.RunPalette(), selected)
            @test length(result.plot.data) == 1
            @test result.plot.data[1][:uid] == "$run_id:working_time_gap"

            rows = UI.build_run_rows(session, DR.JobSummary[], Dict{String, String}())
            recorded = only(filter(row -> row["key"] == run_id, rows))
            @test occursin("working_time_men", recorded["notes"])
            @test recorded["state"] == "completed"
        finally
            DR.shutdown!(manager)
        end
    end

    @testset "reloading changed data republishes through the revision" begin
        root = mktempdir()
        run_id = string(UUIDs.uuid4())
        write_record_fixture(
            root,
            run_id;
            ticks = [0, 1],
            metrics = Dict{String, Any}("working_time_gap" => [0.1, 0.2]),
        )
        manager = DR.RunManager(; runs_root = root, worker_threads = 1)
        try
            model = UI.DashboardModel()
            session = UI.SessionState(model, manager)
            model.manager[] = manager
            model.session[] = session
            DR.load_record!(manager, run_id)
            model.selected_runs[] = [run_id]
            UI.enable_run_lines!(session, run_id)

            @test UI.update_page!(session)
            trace = only(model.active_plot[].data)
            @test trace[:uid] == "$run_id:working_time_gap"
            @test trace[:y] == [0.1, 0.2]
            @test model.axis_label[] == UI.axis_label(:signed_fraction)
            sleep(2 * UI.PUBLISH_INTERVAL)
            @test !UI.update_page!(session)

            write_record_fixture(
                root,
                run_id;
                ticks = [0, 1],
                metrics = Dict{String, Any}("working_time_gap" => [0.3, 0.4]),
            )
            loaded = DR.load_record!(manager, run_id)
            @test loaded.metrics["working_time_gap"] == [0.3, 0.4]
            @test loaded.revision == 1
            sleep(2 * UI.PUBLISH_INTERVAL)
            @test UI.update_page!(session)
            trace = only(model.active_plot[].data)
            @test trace[:uid] == "$run_id:working_time_gap"
            @test trace[:y] == [0.3, 0.4]
        finally
            DR.shutdown!(manager)
        end
    end

    @testset "a throttled plot switch publishes the final active plot" begin
        root = mktempdir()
        run_id = string(UUIDs.uuid4())
        write_record_fixture(
            root,
            run_id;
            ticks = [0, 1],
            metrics = Dict{String, Any}(
                "working_time_men" => [0.1, 0.2],
                "working_time_gap" => [-0.5, 0.5],
                "utility_men" => [1.5, 2.5],
            ),
        )
        manager = DR.RunManager(; runs_root = root, worker_threads = 1)
        try
            model = UI.DashboardModel()
            session = UI.SessionState(model, manager)
            model.manager[] = manager
            model.session[] = session
            DR.load_record!(manager, run_id)
            model.selected_runs[] = [run_id]
            UI.enable_run_lines!(session, run_id)

            # three plots with distinct line selections and axis units
            plot1 = session.plots[1]
            empty!(plot1.lines)
            push!(plot1.lines, UI.line_key(run_id, "working_time_men"))
            UI.handle_add_plot!(model)
            plot2 = UI.active_plot_state(session)
            empty!(plot2.lines)
            push!(plot2.lines, UI.line_key(run_id, "working_time_gap"))
            UI.handle_add_plot!(model)
            plot3 = UI.active_plot_state(session)
            empty!(plot3.lines)
            push!(plot3.lines, UI.line_key(run_id, "utility_men"))
            UI.handle_activate_plot!(model, Dict{String, Any}("plot_id" => "1"))

            series, = UI.build_series!(session)
            signature_plot1 = UI.page_signature(session, series)
            session.gate = UI.PublishGate(; interval = 60.0)
            @test UI.update_page!(session)
            @test [trace[:uid] for trace in model.active_plot[].data] == ["$run_id:working_time_men"]
            @test model.axis_label[] == UI.axis_label(:proportion)

            # two switches inside one throttle window: the signature
            # follows the active plot while the chart is held back
            UI.handle_activate_plot!(model, Dict{String, Any}("plot_id" => "2"))
            series, = UI.build_series!(session)
            signature_plot2 = UI.page_signature(session, series)
            @test signature_plot2 != signature_plot1
            @test !UI.update_page!(session)
            UI.handle_activate_plot!(model, Dict{String, Any}("plot_id" => "3"))
            series, = UI.build_series!(session)
            @test UI.page_signature(session, series) != signature_plot2
            @test !UI.update_page!(session)

            # the eventual publish belongs to the final active plot
            session.gate = UI.PublishGate()
            @test UI.update_page!(session)
            @test [trace[:uid] for trace in model.active_plot[].data] == ["$run_id:utility_men"]
            @test model.axis_label[] == UI.axis_label(:value)
            groups = model.line_groups[]
            @test [line["checked"] for line in groups[1]["lines"]] == [false, false, true]
            @test [line["plot_id"] for line in groups[1]["lines"]] == ["3", "3", "3"]
        finally
            DR.shutdown!(manager)
        end
    end

    @testset "plot switching never restarts or skips the reveal cursor" begin
        root = mktempdir()
        run_id = string(UUIDs.uuid4())
        write_record_fixture(
            root,
            run_id;
            ticks = collect(0:11),
            metrics = Dict{String, Any}("working_time_gap" => collect(0.0:11.0)),
            spec = fixture_spec_dict(ticks = 24),
        )
        manager = DR.RunManager(; runs_root = root, worker_threads = 1)
        try
            model = UI.DashboardModel()
            session = UI.SessionState(model, manager)
            model.manager[] = manager
            model.session[] = session
            DR.load_record!(manager, run_id)
            model.selected_runs[] = [run_id]
            UI.enable_run_lines!(session, run_id)
            # the complete record plays back like a live run's buffered
            # rows: one shared cursor per run, revealed at the paced rate
            session.cursors[run_id] = UI.PresentationCursor(run_id; rows = 0)
            @test UI.reveal_quota(24) == 2

            revealed = Int[]
            for step in 1:6
                if step == 4
                    UI.handle_add_plot!(model)
                elseif step == 5
                    UI.handle_activate_plot!(model, Dict{String, Any}("plot_id" => "1"))
                elseif step == 6
                    UI.handle_activate_plot!(model, Dict{String, Any}("plot_id" => "2"))
                end
                @test UI.update_page!(session)
                push!(revealed, session.cursors[run_id].visible_rows)
                step < 6 && sleep(1.5 * UI.PUBLISH_INTERVAL)
            end
            @test revealed == [2, 4, 6, 8, 10, 12]
            @test UI.active_plot_state(session).id == 2
            @test collect(keys(session.cursors)) == [run_id]
            @test [length(trace[:x]) for trace in model.active_plot[].data] == [12]
        finally
            DR.shutdown!(manager)
        end
    end

    @testset "a live run keeps animating across plot creation and switching" begin
        root = mktempdir()
        manager = DR.RunManager(; runs_root = root, worker_threads = 2)
        try
            spec = tiny_spec(name = "anim", seed = 7, ticks = 20, agents_per_gender = 20)
            job_id = DR.enqueue!(manager, spec)
            UI.register_job_spec!(job_id, spec)
            key = string(job_id)
            model = UI.DashboardModel()
            session = UI.SessionState(model, manager)
            model.manager[] = manager
            model.session[] = session
            model.selected_runs[] = [key]
            UI.enable_run_lines!(session, key)
            quota = UI.reveal_quota(spec.runtime.ticks)
            @test quota == 1

            revealed = Int[]
            step = 0
            deadline = time() + 120.0
            while time() < deadline
                step += 1
                if step == 2
                    UI.handle_add_plot!(model)
                elseif step % 5 == 0
                    UI.handle_activate_plot!(
                        model,
                        Dict{String, Any}("plot_id" => string(1 + step % 2)),
                    )
                end
                UI.update_page!(session)
                cursor = session.cursors[key]
                push!(revealed, cursor.visible_rows)
                rows_total = DR.path_snapshot(manager, key; visible_rows = 0, max_points = 1).rows_total
                summary = only(filter(job -> job.job_id == job_id, DR.job_summaries(manager)))
                if DR.is_terminal_state(summary.state) && !UI.is_lagging(cursor, rows_total)
                    break
                end
                sleep(1.5 * UI.PUBLISH_INTERVAL)
            end

            # the shared cursor animates from zero, never restarts, and
            # never skips ahead of the paced reveal quota
            @test revealed[1] == 0
            @test all(diff(revealed) .>= 0)
            @test all(diff(revealed) .<= quota)
            @test revealed[end] == spec.runtime.ticks
            @test collect(keys(session.cursors)) == [key]
            @test length(session.plots) == 2
            summary = wait_for_job(manager, job_id; timeout = 300.0)
            @test summary.state === DR.JOB_COMPLETED
        finally
            DR.shutdown!(manager)
        end
    end

    @testset "republished charts keep the tickbox visibility authoritative" begin
        root = mktempdir()
        run_id = string(UUIDs.uuid4())
        write_record_fixture(
            root,
            run_id;
            ticks = [0, 1],
            metrics = Dict{String, Any}(
                "working_time_men" => [0.1, 0.2],
                "working_time_women" => [0.3, 0.35],
                "working_time_gap" => [-0.5, 0.5],
            ),
        )
        manager = DR.RunManager(; runs_root = root, worker_threads = 1)
        try
            model = UI.DashboardModel()
            session = UI.SessionState(model, manager)
            model.manager[] = manager
            model.session[] = session
            DR.load_record!(manager, run_id)
            model.selected_runs[] = [run_id]
            UI.enable_run_lines!(session, run_id)

            @test UI.update_page!(session)
            published = model.active_plot[]
            @test length(published.data) == 3
            # the legend is labels-only: no click ever hides a line
            @test published.layout[:legend][:itemclick] == false
            @test published.layout[:legend][:itemdoubleclick] == false
            @test all(trace -> trace[:visible] == true, published.data)

            # a simulated Plotly-side visibility change never survives
            # the next publish: visibility is rebuilt from the tickboxes
            for trace in published.data
                trace[:visible] = "legendonly"
            end
            gap_line = UI.line_key(run_id, "working_time_gap")
            UI.handle_toggle_line!(
                model,
                Dict{String, Any}("line" => gap_line, "plot_id" => "1", "checked" => false),
            )
            sleep(2 * UI.PUBLISH_INTERVAL)
            @test UI.update_page!(session)
            published = model.active_plot[]
            @test [trace[:uid] for trace in published.data] == [
                "$run_id:working_time_men",
                "$run_id:working_time_women",
            ]
            @test all(trace -> trace[:visible] == true, published.data)
        finally
            DR.shutdown!(manager)
        end
    end
end
