# Tests for the TOML logging backend in `src/runtime/logging.jl`
# (see `ADR-0012`). Uses the dummy model binding from
# `test_run_support.jl` to prove logging is model-agnostic.

using TOML

@testset "toml output writes a recoverable run record" begin
    dir = mktempdir()
    raw = make_dummy_raw(;
        seed = 4,
        ticks = 3,
        outputs = Any[Dict{String, Any}("type" => "toml", "directory" => dir)],
    )
    spec = GN.parse_spec(raw)
    result = GN.run(GN.create_world(spec))
    @test result.status == GN.RUN_SUCCESS
    record = TOML.parsefile(joinpath(dir, result.id, "run.toml"))
    @test record["run"]["id"] == result.id
    @test record["run"]["seed"] == spec.seed
    @test record["run"]["status"] == "success"
    @test !isempty(record["run"]["started_at"])
    @test !isempty(record["run"]["finished_at"])
    @test record["run"]["ticks_executed"] == 3
    recovered = GN.parse_spec(record["spec"])
    @test GN.spec_to_dict(recovered) == record["spec"]
    @test record["metrics"]["tick"] == result.ticks
    @test record["metrics"]["value"] == result.metrics["value"]
end

@testset "toml output records failures with an error" begin
    dir = mktempdir()
    raw = make_dummy_raw(;
        ticks = 3,
        fail_at = 1,
        outputs = Any[Dict{String, Any}("type" => "toml", "directory" => dir)],
    )
    result = GN.run(GN.create_world(GN.parse_spec(raw)))
    @test result.status == GN.RUN_FAILURE
    record = TOML.parsefile(joinpath(dir, result.id, "run.toml"))
    @test record["run"]["status"] == "failure"
    @test !isempty(record["run"]["error"])
end

@testset "empty metrics still write a run record" begin
    dir = mktempdir()
    raw = make_dummy_raw(;
        seed = 4,
        ticks = 2,
        metrics = String[],
        outputs = Any[Dict{String, Any}("type" => "toml", "directory" => dir)],
    )
    spec = GN.parse_spec(raw)
    @test spec.logging.metrics == String[]
    result = GN.run(GN.create_world(spec))
    @test result.status == GN.RUN_SUCCESS
    @test isempty(result.metrics)
    @test result.ticks == [0, 1]
    record = TOML.parsefile(joinpath(dir, result.id, "run.toml"))
    @test haskey(record, "run")
    @test haskey(record, "spec")
    @test record["run"]["ticks_executed"] == 2
    @test record["metrics"]["tick"] == [0, 1]
    @test !haskey(record["metrics"], "value")
    recovered = GN.parse_spec(record["spec"])
    @test GN.spec_to_dict(recovered) == record["spec"]
end

@testset "parse_spec rejects an unknown logging output key" begin
    raw = make_dummy_raw(;
        outputs = Any[Dict{String, Any}("type" => "toml", "bogus" => true)],
    )
    e = try
        GN.parse_spec(raw)
        nothing
    catch err
        err
    end
    @test e isa GN.RunSpecError
    @test any(p -> occursin("bogus", p), e.problems)
end
