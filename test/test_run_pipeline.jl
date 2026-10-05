# Tests for world creation and execution in `src/runtime/runner.jl`
# (see `ADR-0012`). Uses the dummy model binding from
# `test_run_support.jl` to prove the pipeline core is model-agnostic.

using UUIDs

@testset "create_world attaches a unique RunContext" begin
    spec = GN.parse_spec(make_dummy_raw())
    first_world = GN.create_world(spec)
    second_world = GN.create_world(spec)
    first_context = Ark.get_resource(first_world, GN.RunContext)
    second_context = Ark.get_resource(second_world, GN.RunContext)
    @test UUIDs.UUID(first_context.id) isa UUIDs.UUID
    @test first_context.id != second_context.id
    @test first_context.spec.seed == 1
end

@testset "successful run executes every tick" begin
    spec = GN.parse_spec(make_dummy_raw(; seed = 1, ticks = 3))
    result = GN.run(GN.create_world(spec))
    @test result.status == GN.RUN_SUCCESS
    @test GN.is_success(result)
    @test result.ticks_executed == 3
    @test result.ticks == [0, 1, 2]
    @test length(result.metrics["value"]) == 3
    @test all(isfinite, result.metrics["value"])
    @test result.finished_at >= result.started_at
    @test result.spec.seed == 1
    @test result.config == Dict{String, Any}("fail_at" => -1, "scale" => 1.0)
end

@testset "identical seeds reproduce identical metrics" begin
    make_result = seed -> GN.run(GN.create_world(GN.parse_spec(make_dummy_raw(; seed = seed))))
    @test make_result(1).metrics == make_result(1).metrics
    @test make_result(1).metrics != make_result(2).metrics
end

@testset "failure run records the error and stops" begin
    spec = GN.parse_spec(make_dummy_raw(; ticks = 3, fail_at = 1))
    result = GN.run(GN.create_world(spec))
    @test result.status == GN.RUN_FAILURE
    @test !GN.is_success(result)
    @test result.ticks_executed == 1
    @test result.ticks == [0]
    @test result.error isa ErrorException
    @test occursin("dummy failure at tick 1", sprint(showerror, result.error))
end

@testset "run without a RunContext throws ArgumentError" begin
    @test_throws ArgumentError GN.run(Ark.World(DummyState))
end

@testset "second run on the same world throws ArgumentError" begin
    world = GN.create_world(GN.parse_spec(make_dummy_raw(; ticks = 2)))
    result = GN.run(world)
    @test GN.is_success(result)
    e = try
        GN.run(world)
        nothing
    catch err
        err
    end
    @test e isa ArgumentError
    @test occursin("one run per world", e.msg)
end

@testset "metrics_recorded! errors propagate without a result" begin
    world = GN.create_world(GN.parse_spec(make_dummy_raw(; ticks = 3)))
    GN.add_logger!(world, ThrowingMetricsLogger())
    e = try
        GN.run(world)
        nothing
    catch err
        err
    end
    @test e isa ErrorException
    @test occursin("logger hook failure", e.msg)
    second = try
        GN.run(world)
        nothing
    catch err
        err
    end
    @test second isa ArgumentError
    @test occursin("one run per world", second.msg)
end

@testset "add_logger! receives the run lifecycle" begin
    spec = GN.parse_spec(make_dummy_raw(; ticks = 3))
    world = GN.create_world(spec)
    logger = RecordingLogger()
    @test GN.add_logger!(world, logger) === nothing
    result = GN.run(world)
    @test length(logger.started) == 1
    @test logger.started[1].id == result.id
    @test length(logger.recorded) == 3
    @test [tick for (tick, _) in logger.recorded] == [0, 1, 2]
    @test length(logger.finished) == 1
    @test logger.finished[1] === result
end
