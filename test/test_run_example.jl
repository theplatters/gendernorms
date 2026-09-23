# End-to-end test running the real `examples/example_run.toml` through
# the run execution pipeline (see `ADR-0012` and `MDR-0010`). Only the
# log directory is overridden with a temporary directory; the run then
# checks success, full metric series, record recovery, and reproducibility.

using TOML

@testset "example spec runs end to end and reproduces" begin
    path = joinpath(@__DIR__, "..", "examples", "example_run.toml")
    raw = TOML.parsefile(path)
    raw["logging"]["outputs"][1]["directory"] = mktempdir()
    spec = GN.parse_spec(raw)
    result = GN.run(GN.create_world(spec))
    @test GN.is_success(result)
    @test result.ticks_executed == spec.runtime.ticks
    for name in spec.logging.metrics
        @test haskey(result.metrics, name)
        @test length(result.metrics[name]) == spec.runtime.ticks
        @test all(isfinite, result.metrics[name])
    end
    record_path = joinpath(raw["logging"]["outputs"][1]["directory"], result.id, "run.toml")
    @test isfile(record_path)
    record = TOML.parsefile(record_path)
    recovered = GN.parse_spec(record["spec"])
    @test recovered.seed == spec.seed
    @test GN.spec_to_dict(recovered) == record["spec"]
    # A second world from the same spec reproduces identical series.
    again = GN.run(GN.create_world(spec))
    @test again.metrics == result.metrics
end
