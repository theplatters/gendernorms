# Run the minimal GenderNorms example through the run execution pipeline
# (see ADR-0012): load the TOML run specification, create the seeded world,
# execute the ticks, and summarize the in-memory result plus the TOML record.
# The prints below are the example's intended program output, not debug output.

using GenderNorms

const GN = GenderNorms

spec = GN.load_spec(joinpath(@__DIR__, "example_run.toml"))
world = GN.create_world(spec)
result = GN.run(world)

function record_directory(spec)
    directory = "runs"
    for output in spec.logging.outputs
        if output.type == "toml" && haskey(output.args, "directory")
            directory = string(output.args["directory"])
        end
    end
    return directory
end

record_path = joinpath(record_directory(spec), result.id, "run.toml")

println("run id: ", result.id)
println("status: ", result.status == GN.RUN_SUCCESS ? "success" : "failure")
println("ticks executed: ", result.ticks_executed)
for name in spec.logging.metrics
    series = result.metrics[name]
    println(name, " final: ", isempty(series) ? "none" : string(series[end]))
end
println("record: ", record_path)
