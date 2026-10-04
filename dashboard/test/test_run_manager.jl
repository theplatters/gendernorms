# Tests for the run manager of `DashboardRuntime`
# (`dashboard/src/runtime/run_manager.jl`) against the scripted
# `test/fake_worker.jl`: FIFO order, the one-executing-run invariant,
# cancellation of queued and active jobs, worker reaping, staged-record
# promotion (success and model failure promoted, cancelled and
# infrastructure-failed never), corrupt protocol streams (bounded
# worker termination, identity, tick-count, and stream-ordering
# violations), hung terminal workers (bounded exit grace, cancellable
# and shut-downable teardown with the outcome preserved), deterministic
# cancellation races, spawn and promotion failures (terminal
# `JOB_WORKER_FAILED`, cleared active slot, advancing queue),
# cross-filesystem promotion, and `path_snapshot` isolation.

@testset "run manager" begin
    fake_worker = joinpath(@__DIR__, "fake_worker.jl")

    function make_manager(; max_queue = DR.DEFAULT_MAX_QUEUE)
        root = mktempdir()
        return DR.RunManager(;
            runs_root = root,
            worker_threads = 1,
            max_queue = max_queue,
            worker_script = fake_worker,
        )
    end

    function record_exists(manager, run_id)
        return isfile(joinpath(manager.runs_root, run_id, "run.toml"))
    end

    function active_count(manager)
        return count(
            summary -> summary.state in (DR.JOB_STARTING, DR.JOB_RUNNING, DR.JOB_CANCELLING),
            DR.job_summaries(manager),
        )
    end

    function synthetic_job(manager, spec; state, outcome = nothing, run_id = "", rows = [0, 1])
        job_id = UUIDs.uuid4()
        job = DR.ManagerJob(
            job_id,
            spec,
            GN.spec_to_dict(spec),
            true,
            state,
            outcome,
            DR.RunPath(;
                name = spec.name,
                seed = spec.seed,
                source = :live,
                state = state,
                ticks_requested = spec.runtime.ticks,
                ticks = copy(rows),
            ),
            joinpath(manager.staging_root, string(job_id)),
            nothing,
            nothing,
            nothing,
            true,
            true,
            run_id,
            false,
            String[],
        )
        manager.jobs[job_id] = job
        push!(manager.order, job_id)
        manager.paths[string(job_id)] = job.path
        return job
    end

    @testset "FIFO order and one executing run" begin
        manager = make_manager()
        try
            jobs = [DR.enqueue!(manager, tiny_spec(name = "fake-ok", ticks = 2)) for _ in 1:3]
            finished_order = UUIDs.UUID[]
            overloaded = false
            deadline = time() + 120
            while length(finished_order) < 3 && time() < deadline
                overloaded |= active_count(manager) > 1
                for summary in DR.job_summaries(manager)
                    summary.state === DR.JOB_COMPLETED || continue
                    summary.job_id in finished_order || push!(finished_order, summary.job_id)
                end
                sleep(0.005)
            end
            @test !overloaded
            @test finished_order == jobs
            @test active_count(manager) == 0
        finally
            DR.shutdown!(manager)
        end
    end

    @testset "staged records are promoted on success" begin
        manager = make_manager()
        try
            job_id = DR.enqueue!(manager, tiny_spec(name = "fake-ok", ticks = 2))
            summary = wait_for_job(manager, job_id)
            @test summary.state === DR.JOB_COMPLETED
            run_id = summary.run_id
            @test record_exists(manager, run_id)
            record = DR.load_record!(manager, run_id)
            @test record.state === DR.JOB_COMPLETED
            @test isempty(record.diagnostics)
            @test record.ticks == [0, 1]
            index = DR.refresh_records!(manager)
            @test [entry.run_id for entry in index.records] == [run_id]
        finally
            DR.shutdown!(manager)
        end
    end

    @testset "staged records are promoted on model failure" begin
        manager = make_manager()
        try
            job_id = DR.enqueue!(manager, tiny_spec(name = "fake-model-failure", ticks = 2))
            summary = wait_for_job(manager, job_id)
            @test summary.state === DR.JOB_MODEL_FAILED
            @test record_exists(manager, summary.run_id)
            record = DR.load_record!(manager, summary.run_id)
            @test record.state === DR.JOB_MODEL_FAILED
            @test occursin("scripted model failure", record.error)
        finally
            DR.shutdown!(manager)
        end
    end

    @testset "cancelled runs keep metrics but are never promoted" begin
        manager = make_manager()
        try
            job_id = DR.enqueue!(manager, tiny_spec(name = "fake-hang", ticks = 50))
            followup = DR.enqueue!(manager, tiny_spec(name = "fake-ok", ticks = 2))
            deadline = time() + 60
            while time() < deadline
                snapshot = DR.path_snapshot(manager, string(job_id))
                snapshot.rows_total >= 1 && break
                sleep(0.01)
            end
            @test DR.cancel!(manager, job_id)

            followup_summary = wait_for_job(manager, followup)
            @test followup_summary.state === DR.JOB_COMPLETED
            cancelled = wait_for_job(manager, job_id)
            @test cancelled.state === DR.JOB_CANCELLED

            snapshot = DR.path_snapshot(manager, string(job_id))
            @test snapshot.rows_total >= 1
            @test snapshot.state === DR.JOB_CANCELLED
            @test !record_exists(manager, snapshot.run_id)
        finally
            DR.shutdown!(manager)
        end
    end

    @testset "queued jobs are cancelled immediately" begin
        manager = make_manager()
        try
            running = DR.enqueue!(manager, tiny_spec(name = "fake-hang", ticks = 50))
            queued = DR.enqueue!(manager, tiny_spec(name = "fake-ok", ticks = 2))
            deadline = time() + 60
            while time() < deadline
                summaries = DR.job_summaries(manager)
                any(
                    summary -> summary.job_id == queued && summary.queue_position == 1,
                    summaries,
                ) && break
                sleep(0.01)
            end
            @test DR.cancel!(manager, queued)
            summary = wait_for_job(manager, queued)
            @test summary.state === DR.JOB_CANCELLED
            @test summary.queue_position == 0
            @test !record_exists(manager, summary.run_id)

            @test DR.cancel!(manager, running)
            @test wait_for_job(manager, running).state === DR.JOB_CANCELLED
        finally
            DR.shutdown!(manager)
        end
    end

    @testset "infrastructure failures and crashes are reaped" begin
        manager = make_manager()
        try
            failed = DR.enqueue!(manager, tiny_spec(name = "fake-infrastructure", ticks = 2))
            crashed = DR.enqueue!(manager, tiny_spec(name = "fake-crash", ticks = 2))
            recovered = DR.enqueue!(manager, tiny_spec(name = "fake-ok", ticks = 2))

            failed_summary = wait_for_job(manager, failed)
            @test failed_summary.state === DR.JOB_WORKER_FAILED

            crashed_summary = wait_for_job(manager, crashed)
            @test crashed_summary.state === DR.JOB_WORKER_FAILED

            recovered_summary = wait_for_job(manager, recovered)
            @test recovered_summary.state === DR.JOB_COMPLETED

            for job_id in (failed, crashed, recovered)
                job = manager.jobs[job_id]
                @test job.process !== nothing
                @test process_exited(job.process)
                @test !isempty(job.path.error) || job_id == recovered
            end
            @test manager.active === nothing
            @test !record_exists(manager, failed_summary.run_id)
            @test !record_exists(manager, crashed_summary.run_id)
        finally
            DR.shutdown!(manager)
        end
    end

    @testset "crash error text names the missing terminal message" begin
        manager = make_manager()
        try
            crashed = DR.enqueue!(manager, tiny_spec(name = "fake-crash", ticks = 2))
            summary = wait_for_job(manager, crashed)
            @test summary.state === DR.JOB_WORKER_FAILED
            snapshot = DR.path_snapshot(manager, string(crashed); max_points = 16)
            @test occursin("without a terminal protocol message", snapshot.error)
        finally
            DR.shutdown!(manager)
        end
    end

    @testset "queue capacity is enforced" begin
        manager = make_manager(max_queue = 2)
        try
            DR.enqueue!(manager, tiny_spec(name = "fake-hang", ticks = 50))
            DR.enqueue!(manager, tiny_spec(name = "fake-ok", ticks = 2))
            DR.enqueue!(manager, tiny_spec(name = "fake-ok", ticks = 2))
            @test_throws ArgumentError DR.enqueue!(manager, tiny_spec(name = "fake-ok"))
        finally
            DR.shutdown!(manager)
        end
    end

    @testset "path snapshots are isolated copies" begin
        manager = make_manager()
        try
            job_id = DR.enqueue!(manager, tiny_spec(name = "fake-ok", ticks = 4))
            summary = wait_for_job(manager, job_id)
            run_id = summary.run_id

            snapshot = DR.path_snapshot(manager, run_id)
            @test snapshot.rows_total == 4
            @test snapshot.ticks == [0, 1, 2, 3]
            push!(snapshot.ticks, 99)
            push!(snapshot.metrics["working_time_gap"], 99.0)

            fresh = DR.path_snapshot(manager, run_id)
            @test fresh.ticks == [0, 1, 2, 3]
            @test fresh.metrics["working_time_gap"] == [0.0, 0.5, 1.0, 1.5]

            windowed = DR.path_snapshot(manager, run_id; visible_rows = 2, max_points = 2)
            @test windowed.visible_rows == 2
            @test windowed.ticks == [0, 1]

            downsampled = DR.path_snapshot(manager, run_id; max_points = 2)
            @test length(downsampled.ticks) == 2
            @test downsampled.ticks[1] == 0
            @test downsampled.ticks[end] == 3

            @test_throws ArgumentError DR.path_snapshot(manager, "unknown-run")
            @test_throws ArgumentError DR.path_snapshot(manager, run_id; max_points = 0)
        finally
            DR.shutdown!(manager)
        end
    end

    @testset "shutdown cancels everything and blocks enqueue" begin
        manager = make_manager()
        job_id = DR.enqueue!(manager, tiny_spec(name = "fake-hang", ticks = 50))
        queued = DR.enqueue!(manager, tiny_spec(name = "fake-ok", ticks = 2))
        DR.shutdown!(manager)
        states = Dict(summary.job_id => summary.state for summary in DR.job_summaries(manager))
        @test states[job_id] === DR.JOB_CANCELLED
        @test states[queued] === DR.JOB_CANCELLED
        @test manager.active === nothing
        @test_throws ArgumentError DR.enqueue!(manager, tiny_spec(name = "fake-ok"))
    end

    @testset "malformed output terminates the worker and advances the queue" begin
        manager = make_manager()
        try
            started_at = time()
            corrupt = DR.enqueue!(manager, tiny_spec(name = "fake-garbage", ticks = 50))
            followup = DR.enqueue!(manager, tiny_spec(name = "fake-ok", ticks = 2))

            corrupt_summary = wait_for_job(manager, corrupt; timeout = 60.0)
            @test corrupt_summary.state === DR.JOB_WORKER_FAILED
            @test time() - started_at < 60

            followup_summary = wait_for_job(manager, followup; timeout = 60.0)
            @test followup_summary.state === DR.JOB_COMPLETED

            job = manager.jobs[corrupt]
            @test job.process !== nothing
            @test process_exited(job.process)
            snapshot = DR.path_snapshot(manager, string(corrupt); max_points = 16)
            @test occursin("protocol", snapshot.error)
            @test manager.active === nothing
        finally
            DR.shutdown!(manager)
        end
    end

    @testset "terminal message before malformed output is not accepted" begin
        manager = make_manager()
        try
            job_id = DR.enqueue!(manager, tiny_spec(name = "fake-finished-then-garbage", ticks = 2))
            summary = wait_for_job(manager, job_id; timeout = 60.0)
            @test summary.state === DR.JOB_WORKER_FAILED
            @test !isempty(summary.run_id)
            @test !record_exists(manager, summary.run_id)
            @test manager.active === nothing
        finally
            DR.shutdown!(manager)
        end
    end

    @testset "handshake job id must identify this job" begin
        manager = make_manager()
        try
            job_id = DR.enqueue!(manager, tiny_spec(name = "fake-wrong-job-id", ticks = 2))
            followup = DR.enqueue!(manager, tiny_spec(name = "fake-ok", ticks = 2))
            @test wait_for_job(manager, job_id; timeout = 60.0).state === DR.JOB_WORKER_FAILED
            @test wait_for_job(manager, followup; timeout = 60.0).state === DR.JOB_COMPLETED
            snapshot = DR.path_snapshot(manager, string(job_id); max_points = 16)
            @test occursin("job id", snapshot.error)
            @test manager.active === nothing
        finally
            DR.shutdown!(manager)
        end
    end

    @testset "terminal run id must match the started run" begin
        manager = make_manager()
        try
            job_id = DR.enqueue!(manager, tiny_spec(name = "fake-wrong-run-id", ticks = 2))
            summary = wait_for_job(manager, job_id; timeout = 60.0)
            @test summary.state === DR.JOB_WORKER_FAILED
            @test !record_exists(manager, summary.run_id)
            snapshot = DR.path_snapshot(manager, summary.run_id; max_points = 16)
            @test occursin("run id", snapshot.error)
            @test manager.active === nothing
        finally
            DR.shutdown!(manager)
        end
    end

    @testset "terminal tick count must match the received rows" begin
        manager = make_manager()
        try
            job_id = DR.enqueue!(manager, tiny_spec(name = "fake-tick-mismatch", ticks = 2))
            summary = wait_for_job(manager, job_id; timeout = 60.0)
            @test summary.state === DR.JOB_WORKER_FAILED
            @test !record_exists(manager, summary.run_id)
            snapshot = DR.path_snapshot(manager, summary.run_id; max_points = 16)
            @test occursin("ticks_executed", snapshot.error)
            @test manager.active === nothing
        finally
            DR.shutdown!(manager)
        end
    end

    @testset "spawn failures end jobs and clear the active slot" begin
        root = mktempdir()
        manager = DR.RunManager(;
            runs_root = root,
            worker_threads = 1,
            julia = joinpath(mktempdir(), "no-such-julia"),
            worker_script = fake_worker,
        )
        try
            first_job = DR.enqueue!(manager, tiny_spec(name = "fake-ok", ticks = 2))
            second_job = DR.enqueue!(manager, tiny_spec(name = "fake-ok", ticks = 2))
            first_summary = wait_for_job(manager, first_job; timeout = 60.0)
            @test first_summary.state === DR.JOB_WORKER_FAILED
            @test wait_for_job(manager, second_job; timeout = 60.0).state === DR.JOB_WORKER_FAILED
            @test occursin("spawn", manager.jobs[first_job].path.error)
            @test manager.active === nothing
        finally
            DR.shutdown!(manager)
        end
        @test manager.active === nothing
    end

    @testset "staging failures end the job and later jobs still run" begin
        root = mktempdir()
        staging_file = joinpath(root, "staging-is-a-file")
        write(staging_file, "not a directory")
        manager = DR.RunManager(;
            runs_root = joinpath(root, "runs"),
            worker_threads = 1,
            staging_root = staging_file,
            worker_script = fake_worker,
        )
        try
            broken = DR.enqueue!(manager, tiny_spec(name = "fake-ok", ticks = 2); record = true)
            followup = DR.enqueue!(manager, tiny_spec(name = "fake-ok", ticks = 2); record = false)
            broken_summary = wait_for_job(manager, broken; timeout = 60.0)
            @test broken_summary.state === DR.JOB_WORKER_FAILED
            @test occursin("spawn", manager.jobs[broken].path.error)
            followup_summary = wait_for_job(manager, followup; timeout = 60.0)
            @test followup_summary.state === DR.JOB_COMPLETED
            @test manager.active === nothing
        finally
            DR.shutdown!(manager)
        end
    end

    @testset "promotion failure finalizes the job without crashing" begin
        root = mktempdir()
        runs_file = joinpath(root, "runs-is-a-file")
        write(runs_file, "not a directory")
        manager = DR.RunManager(;
            runs_root = runs_file,
            worker_threads = 1,
            staging_root = joinpath(root, "staging"),
            worker_script = fake_worker,
        )
        try
            job_id = DR.enqueue!(manager, tiny_spec(name = "fake-ok", ticks = 2))
            followup = DR.enqueue!(manager, tiny_spec(name = "fake-ok", ticks = 2))
            summary = wait_for_job(manager, job_id; timeout = 60.0)
            @test summary.state === DR.JOB_WORKER_FAILED
            @test occursin("record promotion failed", manager.jobs[job_id].path.error)
            snapshot = DR.path_snapshot(manager, summary.run_id; max_points = 16)
            @test any(problem -> occursin("not promoted", problem), snapshot.diagnostics)
            @test wait_for_job(manager, followup; timeout = 60.0).state === DR.JOB_WORKER_FAILED
            @test manager.active === nothing
        finally
            DR.shutdown!(manager)
        end
    end

    @testset "promotion across filesystems ends atomically visible" begin
        runs_root = mktempdir()
        external = isdir("/dev/shm") ? mktempdir("/dev/shm") : ""
        if isempty(external) || stat(external).device == stat(runs_root).device
            @test_skip "no second filesystem available"
        else
            @test stat(external).device != stat(runs_root).device
            manager = DR.RunManager(;
                runs_root = runs_root,
                worker_threads = 1,
                staging_root = joinpath(external, "staging"),
                worker_script = fake_worker,
            )
            try
                job_id = DR.enqueue!(manager, tiny_spec(name = "fake-ok", ticks = 2))
                summary = wait_for_job(manager, job_id; timeout = 60.0)
                @test summary.state === DR.JOB_COMPLETED
                @test record_exists(manager, summary.run_id)
                @test !any(entry -> startswith(entry, ".promoting-"), readdir(runs_root))
                @test isempty(DR.scan_records(runs_root).problems)
                @test [entry.run_id for entry in DR.scan_records(runs_root).records] == [summary.run_id]
            finally
                DR.shutdown!(manager)
                rm(external; recursive = true, force = true)
            end
        end
    end

    @testset "terminal workers that hang are killed after the exit grace" begin
        for name in ("fake-finished-then-hang-closed", "fake-finished-then-hang-writing")
            manager = make_manager()
            try
                job_id = DR.enqueue!(manager, tiny_spec(name = name, ticks = 2))
                started_at = time()
                summary = wait_for_job(manager, job_id; timeout = 60.0)
                @test summary.state === DR.JOB_COMPLETED
                @test time() - started_at < 30
                @test record_exists(manager, summary.run_id)
                job = manager.jobs[job_id]
                @test job.process !== nothing
                @test process_exited(job.process)
                @test manager.active === nothing
            finally
                DR.shutdown!(manager)
            end
        end
    end

    @testset "cancel terminates a worker stuck after its terminal message" begin
        manager = make_manager()
        try
            job_id = DR.enqueue!(manager, tiny_spec(name = "fake-finished-then-hang-closed", ticks = 2))
            deadline = time() + 60
            while time() < deadline
                job = manager.jobs[job_id]
                (job.outcome !== nothing && !process_exited(job.process)) && break
                sleep(0.005)
            end
            job = manager.jobs[job_id]
            @test job.outcome === DR.JOB_COMPLETED
            @test DR.cancel!(manager, job_id)
            summary = wait_for_job(manager, job_id; timeout = 60.0)
            @test summary.state === DR.JOB_COMPLETED
            @test record_exists(manager, summary.run_id)
        finally
            DR.shutdown!(manager)
        end
    end

    @testset "shutdown bounds a worker stuck after its terminal message" begin
        manager = make_manager()
        job_id = DR.enqueue!(manager, tiny_spec(name = "fake-finished-then-hang-writing", ticks = 2))
        deadline = time() + 60
        while time() < deadline
            manager.jobs[job_id].outcome !== nothing && break
            sleep(0.005)
        end
        @test manager.jobs[job_id].outcome === DR.JOB_COMPLETED
        started_at = time()
        DR.shutdown!(manager)
        @test time() - started_at < 30
        summary = wait_for_job(manager, job_id; timeout = 60.0)
        @test summary.state === DR.JOB_COMPLETED
        @test record_exists(manager, summary.run_id)
    end

    @testset "started messages must carry a well-formed run id" begin
        cases = (
            ("fake-empty-run-id", "nonempty UUID"),
            ("fake-invalid-run-id", "nonempty UUID"),
            ("fake-duplicate-started", "duplicate"),
        )
        for (name, expected) in cases
            manager = make_manager()
            try
                job_id = DR.enqueue!(manager, tiny_spec(name = name, ticks = 2))
                summary = wait_for_job(manager, job_id; timeout = 60.0)
                @test summary.state === DR.JOB_WORKER_FAILED
                snapshot = DR.path_snapshot(manager, string(job_id); max_points = 16)
                @test occursin(expected, snapshot.error)
                @test !record_exists(manager, summary.run_id)
                @test manager.active === nothing
            finally
                DR.shutdown!(manager)
            end
        end
    end

    @testset "stream ordering and alignment violations are rejected" begin
        cases = (
            ("fake-rows-before-started", "before the started"),
            ("fake-missing-column", "metric names"),
            ("fake-decreasing-ticks", "strictly increasing"),
        )
        for (name, expected) in cases
            manager = make_manager()
            try
                job_id = DR.enqueue!(manager, tiny_spec(name = name, ticks = 2))
                summary = wait_for_job(manager, job_id; timeout = 60.0)
                @test summary.state === DR.JOB_WORKER_FAILED
                snapshot = DR.path_snapshot(manager, string(job_id); max_points = 16)
                @test occursin(expected, snapshot.error)
            finally
                DR.shutdown!(manager)
            end
        end
    end

    @testset "cancellation outranks a protocol failure without promotion" begin
        manager = make_manager()
        spec = tiny_spec(name = "fake-ok", ticks = 2)
        run_id = string(UUIDs.uuid4())
        job = synthetic_job(manager, spec; state = DR.JOB_CANCELLING, run_id = run_id)
        DR._finish_job!(manager, job, DR.ProtocolError(["injected stream failure"]))
        @test job.state === DR.JOB_CANCELLED
        @test job.path.state === DR.JOB_CANCELLED
        @test isempty(job.path.record_path)
        @test !record_exists(manager, run_id)
        @test manager.active === nothing
        DR.shutdown!(manager)
    end

    @testset "cancellation outranks a late terminal message" begin
        manager = make_manager()
        spec = tiny_spec(name = "fake-ok", ticks = 2)
        run_id = string(UUIDs.uuid4())
        job = synthetic_job(manager, spec; state = DR.JOB_CANCELLING, run_id = run_id)
        DR._handle_message!(
            manager,
            job,
            DR.finished_message(
                run_id,
                "success",
                "",
                2,
                Dates.format(Dates.now(), Dates.ISODateTimeFormat),
            ),
        )
        @test job.outcome === nothing
        DR._finish_job!(manager, job, nothing)
        @test job.state === DR.JOB_CANCELLED
        @test isempty(job.path.record_path)
        @test !record_exists(manager, run_id)
        DR.shutdown!(manager)
    end
end
