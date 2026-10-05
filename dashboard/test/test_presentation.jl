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
# restart or skip the shared per-run reveal cursor), the tickbox
# contract (toggling a line republishes the chart without it on the
# next publish), the record-catalog freshness of the presentation loop
# (a finished job's promoted record surfaces without any manual
# refresh; unchanged catalogs are not rescanned or republished; a
# record promoted while a rescan runs is never permanently invisible),
# and the full view-state sync for a client that connects after the
# page was rendered or reconnects after a disconnect (every channel
# (re)subscription triggers the sync, and a sync inside a throttle
# window stays pending until the publish succeeds), and the
# labels-only legend whose trace visibility is rebuilt from the tickbox
# state on every publish.

"""
    view_update_counts(model)::Dict{Symbol,Int}

Count the reactive writes of one page's full view state. Takes the
model and registers a counting listener on every reactive field a
client sync republishes (job and run rows, plot tabs, line groups, the
chart, its axis label, the display notes, and the status line). The
listeners fire exactly when a write would reach a connected browser,
so the returned counter dictionary asserts which fields one update
really pushed.
"""
function view_update_counts(model)
    fields = (
        :job_rows,
        :run_rows,
        :plot_tabs,
        :line_groups,
        :active_plot,
        :axis_label,
        :display_reduced,
        :data_warnings,
        :status_line,
    )
    counts = Dict{Symbol, Int}(field => 0 for field in fields)
    for field in fields
        Stipple.on((_value) -> (counts[field] += 1), getfield(model, field))
    end
    return counts
end

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
            result = UI.build_plot(series, UI.LinePalette(), selected)
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

    @testset "toggling a line changes the next published chart" begin
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
            @test [trace[:uid] for trace in model.active_plot[].data] == [
                "$run_id:working_time_men",
                "$run_id:working_time_women",
                "$run_id:working_time_gap",
            ]

            # on a static run the selection change alone must republish
            # the chart promptly (the next throttled publish)
            gap_line = UI.line_key(run_id, "working_time_gap")
            UI.handle_toggle_line!(
                model,
                Dict{String, Any}("line" => gap_line, "plot_id" => "1", "checked" => false),
            )
            sleep(2 * UI.PUBLISH_INTERVAL)
            @test UI.update_page!(session)
            @test [trace[:uid] for trace in model.active_plot[].data] == [
                "$run_id:working_time_men",
                "$run_id:working_time_women",
            ]

            # and re-checking restores the line on the next publish
            UI.handle_toggle_line!(
                model,
                Dict{String, Any}("line" => gap_line, "plot_id" => "1", "checked" => true),
            )
            sleep(2 * UI.PUBLISH_INTERVAL)
            @test UI.update_page!(session)
            @test [trace[:uid] for trace in model.active_plot[].data] == [
                "$run_id:working_time_men",
                "$run_id:working_time_women",
                "$run_id:working_time_gap",
            ]
        finally
            DR.shutdown!(manager)
        end
    end

    @testset "a finished job's record appears without a manual refresh" begin
        root = mktempdir()
        manager = DR.RunManager(; runs_root = root, worker_threads = 2)
        try
            spec = tiny_spec(name = "auto-records", seed = 3, ticks = 3, agents_per_gender = 10)
            job_id = DR.enqueue!(manager, spec)
            UI.register_job_spec!(job_id, spec)
            model = UI.DashboardModel()
            session = UI.SessionState(model, manager)
            model.manager[] = manager
            model.session[] = session
            UI.rescan_records!(session)
            @test isempty(session.records.records)

            summary = wait_for_job(manager, job_id; timeout = 300.0)
            @test summary.state === DR.JOB_COMPLETED

            # no manual refresh event: the next presentation update
            # notices the terminal outcome and rescans, so the promoted
            # record and the completed run are published right away
            visible = false
            deadline = time() + 60.0
            while time() < deadline && !visible
                UI.update_page!(session)
                rows = model.run_rows[]
                visible =
                    any(record -> record.run_id == summary.run_id, session.records.records) &&
                    any(row -> row["key"] == string(job_id) && row["state"] == "completed", rows)
                visible || sleep(2 * UI.PUBLISH_INTERVAL)
            end
            @test visible

            # loading and cloning work right after the run appears
            UI.handle_load_record!(model, Dict{String, Any}("key" => summary.run_id))
            @test occursin("loaded", model.status_line[])
            UI.handle_clone_config!(model, Dict{String, Any}("key" => string(job_id)))
            @test occursin("cloned", model.status_line[])
        finally
            DR.shutdown!(manager)
        end
    end

    @testset "record changes surface through the periodic rescan" begin
        root = mktempdir()
        run_id = string(UUIDs.uuid4())
        manager = DR.RunManager(; runs_root = root, worker_threads = 1)
        try
            model = UI.DashboardModel()
            session = UI.SessionState(model, manager)
            model.manager[] = manager
            model.session[] = session
            UI.rescan_records!(session)
            @test UI.update_page!(session)
            @test isempty(model.run_rows[])

            # a record promoted outside this manager (a run that finished
            # elsewhere) shows up within the rescan interval, unprompted
            write_record_fixture(root, run_id; name = "external-run")
            @test UI.refresh_records_if_changed!(
                session,
                DR.JobSummary[];
                now = session.records_checked_at + 2 * UI.RECORDS_REFRESH_INTERVAL,
            )
            UI.update_page!(session)
            recorded = only(filter(row -> row["key"] == run_id, model.run_rows[]))
            @test recorded["source"] == "recorded"
            @test recorded["state"] == "completed"

            # and its row actions work right after it appears
            UI.handle_load_record!(model, Dict{String, Any}("key" => run_id))
            @test occursin("loaded", model.status_line[])
            UI.handle_clone_config!(model, Dict{String, Any}("key" => run_id))
            @test occursin("cloned", model.status_line[])
        finally
            DR.shutdown!(manager)
        end
    end

    @testset "unchanged record sets are not rescanned or republished" begin
        root = mktempdir()
        run_id = string(UUIDs.uuid4())
        write_record_fixture(root, run_id)
        manager = DR.RunManager(; runs_root = root, worker_threads = 1)
        try
            model = UI.DashboardModel()
            session = UI.SessionState(model, manager)
            model.manager[] = manager
            model.session[] = session
            UI.rescan_records!(session)
            @test UI.update_page!(session)
            published_rows = model.run_rows[]
            published_index = session.records

            # the periodic check finds no record change: no rescan ...
            @test !UI.refresh_records_if_changed!(
                session,
                DR.JobSummary[];
                now = session.records_checked_at + 2 * UI.RECORDS_REFRESH_INTERVAL,
            )
            @test session.records === published_index

            # ... and the next update republishes nothing
            sleep(2 * UI.PUBLISH_INTERVAL)
            @test !UI.update_page!(session)
            @test model.run_rows[] === published_rows
        finally
            DR.shutdown!(manager)
        end
    end

    @testset "a newly connected client receives the full view state" begin
        root = mktempdir()
        run_id = string(UUIDs.uuid4())
        write_record_fixture(root, run_id)
        manager = DR.RunManager(; runs_root = root, worker_threads = 1)
        try
            model = UI.DashboardModel()
            session = UI.SessionState(model, manager)
            model.manager[] = manager
            model.session[] = session
            UI.rescan_records!(session)

            # the presentation task computes the view before the browser
            # has connected: nothing is republished while it is unchanged
            @test UI.update_page!(session)
            published_rows = model.run_rows[]
            sleep(2 * UI.PUBLISH_INTERVAL)
            @test !UI.update_page!(session)
            @test model.run_rows[] === published_rows

            # the client signals readiness after it connected; the next
            # update republishes the full view state even though nothing
            # changed, so the late client never sees a stale page
            model.isready[] = true
            @test UI.update_page!(session)
            @test model.run_rows[] == published_rows
            @test model.run_rows[] !== published_rows
        finally
            DR.shutdown!(manager)
        end
    end

    @testset "a promotion racing the rescan surfaces through the periodic check" begin
        root = mktempdir()
        run_id = string(UUIDs.uuid4())
        manager = DR.RunManager(; runs_root = root, worker_threads = 1)
        try
            model = UI.DashboardModel()
            session = UI.SessionState(model, manager)
            model.manager[] = manager
            model.session[] = session

            # an external process promotes a record inside the rescan:
            # the directory listing already ran without it, so the
            # cached index lacks the record while a fingerprint taken
            # afterwards would already acknowledge it
            index = UI.rescan_records!(
                session;
                after_scan = () -> write_record_fixture(root, run_id; name = "racing-run"),
            )
            @test !any(record -> record.run_id == run_id, index.records)
            @test session.records_signature != DR.catalog_signature(root)

            # the periodic change check must notice the difference and
            # rescan; a baseline newer than the scanned index would
            # compare equal forever and hide the record permanently
            @test UI.refresh_records_if_changed!(
                session,
                DR.JobSummary[];
                now = session.records_checked_at + 2 * UI.RECORDS_REFRESH_INTERVAL,
            )
            @test any(record -> record.run_id == run_id, session.records.records)

            # and the surfaced record renders as a usable run row
            @test UI.update_page!(session)
            recorded = only(filter(row -> row["key"] == run_id, model.run_rows[]))
            @test recorded["source"] == "recorded"
            @test recorded["state"] == "completed"
        finally
            DR.shutdown!(manager)
        end
    end

    @testset "a readiness sync inside the throttle window publishes after it" begin
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
            UI.rescan_records!(session)
            DR.load_record!(manager, run_id)
            model.selected_runs[] = [run_id]
            UI.enable_run_lines!(session, run_id)
            UI.handle_add_plot!(model)
            UI.handle_activate_plot!(model, Dict{String, Any}("plot_id" => "1"))

            # one publish opens a long throttle window, and readiness
            # arrives inside it: the chart sync is rejected by the
            # throttle and must not be consumed by that attempt
            session.gate = UI.PublishGate(; interval = 60.0)
            @test UI.update_page!(session)
            model.isready[] = true
            @test !UI.update_page!(session)
            @test !session.client_ready

            # the still-pending sync publishes the full view state when
            # the window opens (a fresh gate stands in for its expiry):
            # job rows, run rows, plot tabs, line groups, the chart, its
            # axis label, the display notes, and the status line
            counts = view_update_counts(model)
            session.gate = UI.PublishGate()
            @test UI.update_page!(session)
            @test session.client_ready
            @test counts == Dict(
                :job_rows => 1,
                :run_rows => 1,
                :plot_tabs => 1,
                :line_groups => 1,
                :active_plot => 1,
                :axis_label => 1,
                :display_reduced => 1,
                :data_warnings => 1,
                :status_line => 1,
            )
        finally
            DR.shutdown!(manager)
        end
    end

    @testset "a reconnecting client resyncs the full view state" begin
        root = mktempdir()
        manager = DR.RunManager(; runs_root = root, worker_threads = 2)
        try
            spec = tiny_spec(name = "reconnect", seed = 11, ticks = 4, agents_per_gender = 10)
            job_id = DR.enqueue!(manager, spec)
            UI.register_job_spec!(job_id, spec)
            key = string(job_id)
            model = UI.DashboardModel()
            session = UI.SessionState(model, manager)
            model.manager[] = manager
            model.session[] = session
            model.isready[] = true
            model.selected_runs[] = [key]
            UI.enable_run_lines!(session, key)

            # the connected client is synced while the run starts
            @test UI.update_page!(session)
            @test session.client_ready
            connected_rows = model.run_rows[]

            # the browser disconnects: the presentation task keeps
            # advancing rows and chart server-side while every push is
            # lost on the wire, and the run finishes unnoticed
            summary = wait_for_job(manager, job_id; timeout = 300.0)
            @test summary.state === DR.JOB_COMPLETED
            deadline = time() + 60.0
            while time() < deadline
                UI.update_page!(session)
                cursor = session.cursors[key]
                rows_total = DR.path_snapshot(manager, key; visible_rows = 0, max_points = 1).rows_total
                if !UI.is_lagging(cursor, rows_total)
                    break
                end
                sleep(1.5 * UI.PUBLISH_INTERVAL)
            end
            rows_total = DR.path_snapshot(manager, key; visible_rows = 0, max_points = 1).rows_total
            @test !UI.is_lagging(session.cursors[key], rows_total)
            stale_rows = model.run_rows[]
            stale_plot = model.active_plot[]
            @test stale_rows != connected_rows

            # without a resync signal the stale client stays stale:
            # nothing changed, so nothing is republished
            sleep(2 * UI.PUBLISH_INTERVAL)
            @test !UI.update_page!(session)

            # the browser reconnects: the page's resubscription hook
            # sends the client_resync event and the next update pushes
            # the complete view state again, without any submit,
            # refresh, or other page event
            counts = view_update_counts(model)
            UI.handle_client_resync!(model)
            @test !session.client_ready
            sleep(2 * UI.PUBLISH_INTERVAL)
            @test UI.update_page!(session)
            @test session.client_ready
            @test counts == Dict(
                :job_rows => 1,
                :run_rows => 1,
                :plot_tabs => 1,
                :line_groups => 1,
                :active_plot => 1,
                :axis_label => 1,
                :display_reduced => 1,
                :data_warnings => 1,
                :status_line => 1,
            )
            @test model.run_rows[] !== stale_rows
            @test model.active_plot[] !== stale_plot

            # rows and chart show the finished run with every row
            rows = only(filter(row -> row["key"] == key, model.run_rows[]))
            @test rows["state"] == "completed"
            plot = model.active_plot[]
            @test !isempty(plot.data)
            @test all(trace -> length(trace[:y]) == rows_total, plot.data)
        finally
            DR.shutdown!(manager)
        end
    end
end
