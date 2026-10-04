# End-to-end integration of `DashboardRuntime` with the real
# `bin/run_worker.jl`: `enqueue!` runs a tiny model in a worker process
# under a temp runs root, the streamed and promoted metrics equal a
# direct `GenderNorms.run` of the same spec and seed exactly, and an
# unrecorded run leaves no record behind.

@testset "worker integration" begin
    @testset "a tiny run completes, streams, and promotes exactly" begin
        root = mktempdir()
        manager = DR.RunManager(; runs_root = root, worker_threads = 2)
        spec = tiny_spec(name = "integration", seed = 5, ticks = 5, agents_per_gender = 30)
        try
            job_id = DR.enqueue!(manager, spec)
            summary = wait_for_job(manager, job_id; timeout = 300.0)
            @test summary.state === DR.JOB_COMPLETED
            @test summary.progress == 1.0

            reference = GN.run(GN.create_world(spec))
            @test GN.is_success(reference)

            snapshot = DR.path_snapshot(manager, summary.run_id)
            @test snapshot.ticks == reference.ticks
            @test snapshot.metrics == reference.metrics
            @test snapshot.state === DR.JOB_COMPLETED
            @test snapshot.rows_total == 5

            record_file = joinpath(root, summary.run_id, "run.toml")
            @test isfile(record_file)
            record = DR.read_record(record_file)
            @test isempty(record.diagnostics)
            @test isempty(record.spec_problems)
            @test record.state === DR.JOB_COMPLETED
            @test record.ticks == reference.ticks
            @test record.metrics == reference.metrics
            @test record.name == "integration"
            @test record.seed == 5
            @test record.spec isa GN.RunSpec

            index = DR.refresh_records!(manager)
            @test [entry.run_id for entry in index.records] == [summary.run_id]
            loaded = DR.load_record!(manager, summary.run_id)
            @test loaded.metrics == reference.metrics
        finally
            DR.shutdown!(manager)
        end
    end

    @testset "an unrecorded run leaves no record behind" begin
        root = mktempdir()
        manager = DR.RunManager(; runs_root = root, worker_threads = 2)
        spec = tiny_spec(name = "integration-unrecorded", seed = 6, ticks = 2, agents_per_gender = 20)
        try
            job_id = DR.enqueue!(manager, spec; record = false)
            summary = wait_for_job(manager, job_id; timeout = 300.0)
            @test summary.state === DR.JOB_COMPLETED
            @test !ispath(joinpath(root, summary.run_id))
            snapshot = DR.path_snapshot(manager, summary.run_id)
            @test snapshot.rows_total == 2
        finally
            DR.shutdown!(manager)
        end
    end
end
