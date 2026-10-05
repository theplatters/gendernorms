# Threading speedup measurement for the multithreaded world loops
# (`calculate_norm_perception!` and `set_theta!`, see `ADR-0014`). Times
# one full `GenderNorms.run` on a fixed deterministic configuration with
# `time_ns()` and prints the elapsed seconds and ticks per second at full
# Float64 precision together with the thread count. The prints below are
# the script's intended program output, not debug output (same policy as
# `examples/run_example.jl` and `benchmark/run_benchmarks.jl`).
#
# Usage:
#   JULIA_NUM_THREADS=1 julia --project=. benchmark/threading_speedup.jl [agents_per_gender] [ticks]
#   JULIA_NUM_THREADS=4 julia --project=. benchmark/threading_speedup.jl [agents_per_gender] [ticks]
#
# Defaults: 100 agents per gender, 10 ticks, seed 1, `watts_strogatz`
# network with `neighbors_per_side` 2 and `rewiring` 0.1. Run both
# invocations and compare the elapsed times for the speedup factor.

using GenderNorms

const GN = GenderNorms

"""
    speedup_spec(agents_per_gender::Int, ticks::Int)

Build one run specification table of this driver (the shape accepted by
`GenderNorms.parse_spec`, see `ADR-0012`): seed 1, the fixed
`watts_strogatz` network of this script, and the given population size
and tick count. Returns the dictionary.
"""
function speedup_spec(agents_per_gender::Int, ticks::Int)
    return Dict{String, Any}(
        "run" => Dict{String, Any}("name" => "threading-speedup", "seed" => 1),
        "model" => Dict{String, Any}(
            "name" => "gender_norms",
            "agents_per_gender" => agents_per_gender,
            "network" => Dict{String, Any}(
                "type" => "watts_strogatz", "neighbors_per_side" => 2, "rewiring" => 0.1
            ),
        ),
        "runtime" => Dict{String, Any}("ticks" => ticks),
    )
end

"""
    main(args::Vector{String})

Measure one model run. Takes the positional arguments
`[agents_per_gender] [ticks]` (defaults 100 and 10), warms the JIT up
with one tiny discarded run, then builds the world, times `GenderNorms.run`
with `time_ns()`, and prints the thread count, the workload, the elapsed
seconds, and the ticks per second at full precision. Returns nothing.
"""
function main(args::Vector{String})
    agents_per_gender = length(args) >= 1 ? parse(Int, args[1]) : 100
    ticks = length(args) >= 2 ? parse(Int, args[2]) : 10
    (agents_per_gender >= 1 && ticks >= 1) || error("agents_per_gender and ticks must be >= 1")
    # JIT warmup on a tiny workload, discarded before timing.
    GN.run(GN.create_world(GN.parse_spec(speedup_spec(2, 1))))
    spec = GN.parse_spec(speedup_spec(agents_per_gender, ticks))
    world = GN.create_world(spec)
    start = time_ns()
    result = GN.run(world)
    elapsed_s = (time_ns() - start) / 1.0e9
    GN.is_success(result) || error("run failed: $(result.error)")
    println("threads ", repr(Threads.nthreads()))
    println("agents_per_gender ", repr(agents_per_gender))
    println("ticks ", repr(ticks))
    println("elapsed_s ", repr(elapsed_s))
    println("ticks_per_s ", repr(ticks / elapsed_s))
    return nothing
end

main(ARGS)
