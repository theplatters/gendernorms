# Tests for the run specification parsing and validation in
# `src/runtime/run_spec.jl` (see `ADR-0012`). Uses the dummy model
# binding from `test_run_support.jl` to prove the specification layer
# is model-agnostic.

using TOML

@testset "valid minimal spec parses with defaults" begin
    raw = Dict{String,Any}(
        "run" => Dict{String,Any}("seed" => 5),
        "model" => Dict{String,Any}("name" => "dummy"),
        "runtime" => Dict{String,Any}("ticks" => 2),
    )
    spec = GN.parse_spec(raw)
    @test spec.name == "unnamed"
    @test spec.seed == 5
    @test spec.model_name == "dummy"
    @test spec.runtime.ticks == 2
    @test spec.logging.metrics == ["value"]
    @test spec.logging.outputs == GN.OutputSpec[]
end

@testset "full spec round-trips through spec_to_dict" begin
    raw = make_dummy_raw(;
        name = "full",
        seed = 7,
        ticks = 4,
        fail_at = -1,
        scale = 2.5,
        metrics = ["value"],
        outputs = Any[Dict{String,Any}("type" => "toml", "directory" => "runs")],
    )
    spec = GN.parse_spec(raw)
    @test spec.name == "full"
    @test spec.logging.outputs[1].type == "toml"
    @test spec.logging.outputs[1].args["directory"] == "runs"
    echoed = GN.spec_to_dict(spec)
    @test GN.spec_to_dict(GN.parse_spec(echoed)) == echoed
end

@testset "load_spec reads a TOML file" begin
    dir = mktempdir()
    path = joinpath(dir, "run.toml")
    open(path, "w") do io
        print(
            io,
            "[run]\nseed = 3\n[model]\nname = \"dummy\"\n[runtime]\nticks = 2\n",
        )
    end
    spec = GN.load_spec(path)
    @test spec.seed == 3
    @test spec.model_name == "dummy"
    @test spec.runtime.ticks == 2
end

@testset "load_spec rejects a missing file" begin
    e = try
        GN.load_spec(joinpath(mktempdir(), "missing.toml"))
        nothing
    catch err
        err
    end
    @test e isa GN.RunSpecError
    @test length(e.problems) == 1
end

@testset "load_spec rejects malformed TOML" begin
    dir = mktempdir()
    path = joinpath(dir, "broken.toml")
    open(path, "w") do io
        print(io, "[run\nseed = \n")
    end
    @test_throws GN.RunSpecError GN.load_spec(path)
end

function spec_message(raw)
    return try
        GN.parse_spec(raw)
        error("expected RunSpecError")
    catch e
        e isa GN.RunSpecError || rethrow()
        sprint(showerror, e)
    end
end

function with_model(raw, model)
    raw["model"] = model
    return raw
end

@testset "missing run.seed reports its key path" begin
    raw = make_dummy_raw()
    delete!(raw["run"], "seed")
    @test occursin("[run]", spec_message(raw))
    @test occursin("seed", spec_message(raw))
end

@testset "missing model.name reports its key path" begin
    raw = with_model(make_dummy_raw(), Dict{String,Any}("fail_at" => -1))
    @test occursin("[model]", spec_message(raw))
    @test occursin("name", spec_message(raw))
end

@testset "missing runtime.ticks reports its key path" begin
    raw = make_dummy_raw()
    delete!(raw["runtime"], "ticks")
    @test occursin("[runtime]", spec_message(raw))
    @test occursin("ticks", spec_message(raw))
end

@testset "ticks = 0 reports its key path" begin
    @test occursin("[runtime.ticks]", spec_message(make_dummy_raw(; ticks = 0)))
end

@testset "negative seed reports its key path" begin
    @test occursin("[run.seed]", spec_message(make_dummy_raw(; seed = -2)))
end

@testset "unknown top-level key is rejected" begin
    raw = make_dummy_raw()
    raw["experiment"] = Dict{String,Any}()
    message = spec_message(raw)
    @test occursin("experiment", message)
end

@testset "unknown run key is rejected" begin
    raw = make_dummy_raw()
    raw["run"]["extra"] = 1
    message = spec_message(raw)
    @test occursin("[run]", message)
    @test occursin("extra", message)
end

@testset "unknown model name lists registered models" begin
    raw = with_model(make_dummy_raw(), Dict{String,Any}("name" => "nope"))
    message = spec_message(raw)
    @test occursin("[model.name]", message)
    @test occursin("dummy", message)
end

@testset "unknown metric name lists available metrics" begin
    raw = make_dummy_raw(; metrics = ["value", "bogus"])
    message = spec_message(raw)
    @test occursin("[logging.metrics]", message)
    @test occursin("bogus", message)
    @test occursin("value", message)
end

@testset "unknown output type lists known backends" begin
    raw = make_dummy_raw(; outputs = Any[Dict{String,Any}("type" => "csv")])
    message = spec_message(raw)
    @test occursin("[logging.outputs[1]]", message)
    @test occursin("csv", message)
    @test occursin("toml", message)
end

@testset "bad output argument type keeps its entry index" begin
    raw = make_dummy_raw(; outputs = Any[Dict{String,Any}("type" => "toml", "directory" => 7)])
    message = spec_message(raw)
    @test occursin("[logging.outputs[1]]", message)
    @test occursin("directory", message)
end

@testset "second bad output entry keeps its own index" begin
    raw = make_dummy_raw(;
        outputs = Any[
            Dict{String,Any}("type" => "toml"),
            Dict{String,Any}("type" => "toml", "directory" => 7),
        ],
    )
    message = spec_message(raw)
    @test occursin("[logging.outputs[2]]", message)
    @test !occursin("[logging.outputs[1]]", message)
end

@testset "duplicate metric names are rejected" begin
    raw = make_dummy_raw(; metrics = ["value", "value"])
    message = spec_message(raw)
    @test occursin("[logging.metrics]", message)
    @test occursin("duplicate metric name", message)
    @test occursin("value", message)
end

@testset "non-table section is rejected" begin
    raw = make_dummy_raw()
    raw["run"] = 3
    message = spec_message(raw)
    @test occursin("[run]", message)
    @test occursin("table", message)
end

@testset "unknown model-section key is rejected" begin
    raw = with_model(
        make_dummy_raw(),
        Dict{String,Any}("name" => "dummy", "bogus" => 1),
    )
    message = spec_message(raw)
    @test occursin("[model]", message)
    @test occursin("bogus", message)
end

@testset "multiple problems aggregate into one error" begin
    raw = make_dummy_raw(; seed = -1, ticks = 0)
    delete!(raw["run"], "seed")
    raw["model"]["bogus"] = true
    raw["surprise"] = 1
    e = try
        GN.parse_spec(raw)
        nothing
    catch err
        err
    end
    @test e isa GN.RunSpecError
    @test length(e.problems) >= 4
    message = sprint(showerror, e)
    @test occursin("invalid run specification:", message)
    @test occursin("[run]", message)
    @test occursin("[runtime.ticks]", message)
end
