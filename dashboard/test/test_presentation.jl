# Presentation cursor and publish throttle tests of the dashboard UI
# layer.
#
# Covers `GenderNormsDashboard.DashboardUI` presentation pacing: the
# reveal quota of one UI update, the lag label while the cursor trails
# execution, "Jump to latest", the publish throttle (one publish per
# window, only on changed data), recorded runs showing complete paths
# initially with a replay mode on the same cursor, run-row notes that
# surface invalid record columns, and revision-driven republishing when
# a loaded record is replaced with changed data.

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
            metrics = Dict{String,Any}(
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
            result = UI.build_plots(series, UI.RunPalette())
            @test length(result.plots[UI.PANEL_METRICS[3]].data) == 1
            @test isempty(result.plots[UI.PANEL_METRICS[1]].data)

            rows = UI.build_run_rows(session, DR.JobSummary[], Dict{String,String}())
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
            metrics = Dict{String,Any}("working_time_gap" => [0.1, 0.2]),
        )
        manager = DR.RunManager(; runs_root = root, worker_threads = 1)
        try
            model = UI.DashboardModel()
            session = UI.SessionState(model, manager)
            model.manager[] = manager
            model.session[] = session
            DR.load_record!(manager, run_id)
            model.selected_runs[] = [run_id]

            @test UI.update_page!(session)
            sleep(2 * UI.PUBLISH_INTERVAL)
            @test !UI.update_page!(session)

            write_record_fixture(
                root,
                run_id;
                ticks = [0, 1],
                metrics = Dict{String,Any}("working_time_gap" => [0.3, 0.4]),
            )
            loaded = DR.load_record!(manager, run_id)
            @test loaded.metrics["working_time_gap"] == [0.3, 0.4]
            @test loaded.revision == 1
            sleep(2 * UI.PUBLISH_INTERVAL)
            @test UI.update_page!(session)
        finally
            DR.shutdown!(manager)
        end
    end
end
