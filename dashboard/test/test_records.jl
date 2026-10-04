# Tests for the run record catalog of `DashboardRuntime`
# (`dashboard/src/runtime/records.jl`): TOML fixtures cover success,
# model failure, empty metrics, mismatched lengths (excluded columns
# with diagnostics), malformed TOML, a bad spec (cloning disabled but
# visualization intact), non-finite values, UUID disagreement, scanning,
# caching, and staged-record promotion (atomic rename into place, hidden
# in-flight directories, cross-filesystem fallback, records preserved
# when source cleanup fails, and cleanup on failure).

@testset "records" begin
    @testset "success record loads cleanly" begin
        root = mktempdir()
        run_id = string(UUIDs.uuid4())
        path = DR.read_record(write_record_fixture(root, run_id))
        @test path.run_id == run_id
        @test path.name == "fixture-run"
        @test path.seed == 1
        @test path.source === :recorded
        @test path.state === DR.JOB_COMPLETED
        @test path.started_at == Dates.DateTime("2026-01-02T03:04:05")
        @test path.finished_at == Dates.DateTime("2026-01-02T03:04:06.5")
        @test path.ticks == [0, 1]
        @test path.ticks_requested == 2
        @test path.ticks_executed == 2
        @test path.metrics == Dict("working_time_gap" => [0.1, 0.2])
        @test isempty(path.diagnostics)
        @test isempty(path.spec_problems)
        @test path.spec isa GN.RunSpec
        @test path.record_path == joinpath(root, run_id, "run.toml")
    end

    @testset "model failure record maps onto JOB_MODEL_FAILED" begin
        root = mktempdir()
        run_id = string(UUIDs.uuid4())
        path = DR.read_record(
            write_record_fixture(
                root,
                run_id;
                status = "failure",
                error = "DomainError: boom",
            ),
        )
        @test path.state === DR.JOB_MODEL_FAILED
        @test path.error == "DomainError: boom"
        @test isempty(path.diagnostics)
    end

    @testset "empty metrics record loads cleanly" begin
        root = mktempdir()
        run_id = string(UUIDs.uuid4())
        path = DR.read_record(
            write_record_fixture(
                root,
                run_id;
                ticks = Int[],
                metrics = Dict{String,Any}(),
                ticks_executed = 0,
            ),
        )
        @test isempty(path.diagnostics)
        @test path.ticks == Int[]
        @test path.metrics == Dict{String,Vector{Float64}}()
        @test path.ticks_executed == 0
    end

    @testset "mismatched lengths become diagnostics and are excluded" begin
        root = mktempdir()
        path = DR.read_record(
            write_record_fixture(
                root,
                string(UUIDs.uuid4());
                metrics = Dict{String,Any}(
                    "working_time_gap" => [0.1, 0.2, 0.3],
                    "paid_time_men" => [0.7],
                ),
            ),
        )
        @test any(problem -> occursin("values but", problem), path.diagnostics)
        @test !haskey(path.metrics, "working_time_gap")
        @test !haskey(path.metrics, "paid_time_men")
    end

    @testset "malformed TOML becomes a diagnostic" begin
        root = mktempdir()
        directory = joinpath(root, string(UUIDs.uuid4()))
        mkpath(directory)
        path = joinpath(directory, "run.toml")
        write(path, "this is [not\n valid toml")
        record = DR.read_record(path)
        @test record.source === :recorded
        @test record.state === DR.JOB_WORKER_FAILED
        @test any(problem -> occursin("cannot load", problem), record.diagnostics)
        @test record.ticks == Int[]
    end

    @testset "bad spec disables cloning but not visualization" begin
        root = mktempdir()
        run_id = string(UUIDs.uuid4())
        bad = fixture_spec_dict()
        delete!(bad["model"], "name")
        path = DR.read_record(write_record_fixture(root, run_id; spec = bad))
        @test isempty(path.diagnostics)
        @test !isempty(path.spec_problems)
        @test path.spec === nothing
        @test path.ticks == [0, 1]
        @test path.metrics["working_time_gap"] == [0.1, 0.2]

        missing_spec = DR.read_record(
            write_record_fixture(root, string(UUIDs.uuid4()); spec = nothing),
        )
        @test !isempty(missing_spec.spec_problems)
        @test isempty(missing_spec.diagnostics)
    end

    @testset "non-finite values are kept as data" begin
        root = mktempdir()
        path = DR.read_record(
            write_record_fixture(
                root,
                string(UUIDs.uuid4());
                metrics = Dict{String,Any}("working_time_gap" => [NaN, Inf, -Inf]),
                ticks = [0, 1, 2],
            ),
        )
        @test isempty(path.diagnostics)
        values = path.metrics["working_time_gap"]
        @test isnan(values[1])
        @test values[2] === Inf
        @test values[3] === -Inf
    end

    @testset "directory and record id must agree" begin
        root = mktempdir()
        run_id = string(UUIDs.uuid4())
        record_path = write_record_fixture(
            root,
            run_id;
            directory_name = string(UUIDs.uuid4()),
        )
        path = DR.read_record(record_path)
        @test any(problem -> occursin("record directory", problem), path.diagnostics)
    end

    @testset "scan_records catalogs only direct run.toml files" begin
        root = mktempdir()
        first = write_record_fixture(root, string(UUIDs.uuid4()))
        second = write_record_fixture(root, string(UUIDs.uuid4()))
        write_record_fixture(joinpath(root, ".dashboard-staging", "job"), string(UUIDs.uuid4()))
        mkpath(joinpath(root, "empty-dir"))
        write(joinpath(root, "stray.txt"), "not a record")
        cache = DR.RecordCache()
        index = DR.scan_records(root, cache)
        @test isempty(index.problems)
        @test Set(record.record_path for record in index.records) == Set([first, second])
        @test all(record -> isempty(record.diagnostics), index.records)

        missing_index = DR.scan_records(joinpath(root, "does-not-exist"))
        @test isempty(missing_index.records)
        @test !isempty(missing_index.problems)
    end

    @testset "read_record caches by path, size, and mtime" begin
        root = mktempdir()
        record_path = write_record_fixture(root, string(UUIDs.uuid4()))
        cache = DR.RecordCache()
        first = DR.read_record(record_path, cache)
        @test length(cache.entries) == 1
        second = DR.read_record(record_path, cache)
        @test second.metrics == first.metrics
        @test second.metrics !== first.metrics
        run_id = first.run_id
        write_record_fixture(root, run_id; ticks = [0, 1, 2, 3])
        third = DR.read_record(record_path, cache)
        @test length(third.ticks) > length(first.ticks)
    end

    @testset "promote_record! moves validated staged runs" begin
        runs_root = mktempdir()
        staging = mktempdir()

        good = string(UUIDs.uuid4())
        good_dir = joinpath(staging, "job", good)
        write_record_fixture(joinpath(staging, "job"), good)
        promoted = DR.promote_record!(good_dir, runs_root)
        @test promoted == joinpath(runs_root, good, "run.toml")
        @test isfile(promoted)

        failed = string(UUIDs.uuid4())
        failed_dir = joinpath(staging, "job", failed)
        write_record_fixture(joinpath(staging, "job"), failed; status = "failure")
        promoted = DR.promote_record!(failed_dir, runs_root)
        @test promoted == joinpath(runs_root, failed, "run.toml")
        @test isfile(promoted)
        @test DR.read_record(promoted).state === DR.JOB_MODEL_FAILED

        broken = string(UUIDs.uuid4())
        broken_dir = joinpath(staging, "job", broken)
        write_record_fixture(joinpath(staging, "job"), broken; ticks_executed = 99)
        problems = DR.promote_record!(broken_dir, runs_root)
        @test problems isa Vector{String}
        @test any(problem -> occursin("failed validation", problem), problems)
        @test isfile(joinpath(broken_dir, "run.toml"))
        @test !ispath(joinpath(runs_root, broken))

        absent = DR.promote_record!(joinpath(staging, "job", "missing"), runs_root)
        @test absent isa Vector{String}
        @test any(problem -> occursin("missing", problem), absent)

        mismatch = string(UUIDs.uuid4())
        mismatch_dir = joinpath(staging, "job", string(UUIDs.uuid4()))
        write_record_fixture(
            joinpath(staging, "job"),
            mismatch;
            directory_name = basename(mismatch_dir),
        )
        problems = DR.promote_record!(mismatch_dir, runs_root)
        @test problems isa Vector{String}
        @test any(problem -> occursin("record directory", problem), problems)
    end

    @testset "valid columns survive with an excluded neighbor" begin
        root = mktempdir()
        run_id = string(UUIDs.uuid4())
        path = DR.read_record(
            write_record_fixture(
                root,
                run_id;
                ticks = [0, 1, 2],
                metrics = Dict{String,Any}(
                    "working_time_gap" => [0.1, 0.2, 0.3],
                    "short_column" => [0.5],
                ),
            ),
        )
        @test path.metrics == Dict("working_time_gap" => [0.1, 0.2, 0.3])
        @test any(problem -> occursin("\"short_column\"", problem), path.diagnostics)

        manager = DR.RunManager(; runs_root = root, worker_threads = 1)
        try
            DR.load_record!(manager, run_id)
            snapshot = DR.path_snapshot(manager, run_id)
            @test snapshot.ticks == [0, 1, 2]
            @test snapshot.metrics == Dict("working_time_gap" => [0.1, 0.2, 0.3])
            @test snapshot.metric_names == ["working_time_gap"]
            @test any(problem -> occursin("\"short_column\"", problem), snapshot.diagnostics)
        finally
            DR.shutdown!(manager)
        end
    end

    @testset "promotion stages hidden and renames into place" begin
        runs_root = mktempdir()
        staging = mktempdir()
        run_id = string(UUIDs.uuid4())
        write_record_fixture(staging, run_id)
        staged = joinpath(staging, run_id)
        promoted = DR.promote_record!(staged, runs_root)
        @test promoted == joinpath(runs_root, run_id, "run.toml")
        @test isfile(promoted)
        @test !ispath(staged)
        @test !any(entry -> startswith(entry, ".promoting-"), readdir(runs_root))
    end

    @testset "promotion failure cleans up and never publishes partially" begin
        runs_root = mktempdir()
        staging = mktempdir()
        run_id = string(UUIDs.uuid4())
        write_record_fixture(staging, run_id)
        staged = joinpath(staging, run_id)
        problems = DR.promote_record!(
            staged,
            runs_root;
            rename = (source, destination) -> error("injected rename failure"),
        )
        @test problems isa Vector{String}
        @test any(problem -> occursin("injected rename failure", problem), problems)
        @test !ispath(joinpath(runs_root, run_id))
        @test !any(entry -> startswith(entry, ".promoting-"), readdir(runs_root))
        @test isfile(joinpath(staged, "run.toml"))
        @test isempty(DR.read_record(joinpath(staged, "run.toml")).diagnostics)
    end

    @testset "scan_records ignores in-flight promotion directories" begin
        runs_root = mktempdir()
        write_record_fixture(
            runs_root,
            string(UUIDs.uuid4());
            directory_name = ".promoting-$(UUIDs.uuid4())",
        )
        index = DR.scan_records(runs_root)
        @test isempty(index.records)
        @test isempty(index.problems)
    end

    @testset "promotion stages across filesystems and renames into place" begin
        runs_root = mktempdir()
        external = isdir("/dev/shm") ? mktempdir("/dev/shm") : ""
        if isempty(external) || stat(external).device == stat(runs_root).device
            @test_skip "no second filesystem available"
        else
            @test stat(external).device != stat(runs_root).device
            try
                staging = joinpath(external, "staging")
                run_id = string(UUIDs.uuid4())
                write_record_fixture(staging, run_id)
                staged = joinpath(staging, run_id)
                promoted = DR.promote_record!(staged, runs_root)
                @test promoted == joinpath(runs_root, run_id, "run.toml")
                @test isfile(promoted)
                record = DR.read_record(promoted)
                @test isempty(record.diagnostics)
                @test record.ticks == [0, 1]
                @test !ispath(staged)
                @test !any(entry -> startswith(entry, ".promoting-"), readdir(runs_root))
            finally
                rm(external; recursive = true, force = true)
            end
        end
    end

    @testset "failed source cleanup preserves the published record" begin
        runs_root = mktempdir()
        external = isdir("/dev/shm") ? mktempdir("/dev/shm") : ""
        if isempty(external) || stat(external).device == stat(runs_root).device
            @test_skip "no second filesystem available"
        else
            @test stat(external).device != stat(runs_root).device
            try
                staging = joinpath(external, "staging")
                run_id = string(UUIDs.uuid4())
                write_record_fixture(staging, run_id)
                staged = joinpath(staging, run_id)
                protected = joinpath(staged, "z-protected")
                mkpath(protected)
                write(joinpath(protected, "payload"), "x")
                chmod(protected, 0o555)
                notes = String[]
                promoted = DR.promote_record!(staged, runs_root; diagnostics = notes)
                @test promoted == joinpath(runs_root, run_id, "run.toml")
                record = DR.read_record(promoted)
                @test isempty(record.diagnostics)
                @test record.ticks == [0, 1]
                @test record.metrics["working_time_gap"] == [0.1, 0.2]
                @test any(note -> occursin(staged, note), notes)
                @test !any(entry -> startswith(entry, ".promoting-"), readdir(runs_root))
                @test ispath(staged)
            finally
                for (directory, _, _) in walkdir(external)
                    chmod(directory, 0o755)
                end
                rm(external; recursive = true, force = true)
            end
        end
    end
end
