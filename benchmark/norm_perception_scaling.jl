# Micro-benchmark for the norm perception kernel
# `calculate_norm_perception!` (`src/systems/norm_perception.jl`, see
# `ADR-0014`). Times only the `calculate_norm_perception!` calls with
# `time_ns()` and takes `Base.gc_num()` deltas around exactly those
# calls. The methodology mirrors `benchmark/scheduling_sweep.jl` and
# `benchmark/threading_speedup.jl`: seed-1 Watts-Strogatz workload
# (`neighbors_per_side` 2, `rewiring` 0.1), one discarded tiny and one
# discarded full-size JIT warmup pass, then one fresh `create_world`
# per measured repetition (identical initial states across
# repetitions; no GC is forced between repetitions). Each pass drives
# `ticks` ticks of repeated `calculate_norm_perception!` calls on the
# same world without advancing any other system, so the workload stays
# constant (the kernel reads lagged `old` state and writes perception
# state only). The prints below are the script's intended program
# output, not debug output (same policy as
# `benchmark/threading_speedup.jl`).
#
# Usage (one thread count at a time; do not run other heavy jobs while
# timing):
#   JULIA_NUM_THREADS=N julia --project=. benchmark/norm_perception_scaling.jl [agents_per_gender] [ticks] [reps]
#
# Defaults: 2000 agents per gender, 30 ticks, 5 repetitions.

using GenderNorms
using Statistics

const GN = GenderNorms

"""
    norm_perception_spec(agents_per_gender::Int, ticks::Int)

Build one run specification table of this driver (the shape accepted by
`GenderNorms.parse_spec`, see `ADR-0012`): seed 1, the fixed
`watts_strogatz` network of `benchmark/threading_speedup.jl`
(`neighbors_per_side` 2, `rewiring` 0.1), and the given population size
and tick count. Returns the dictionary.
"""
function norm_perception_spec(agents_per_gender::Int, ticks::Int)
    return Dict{String,Any}(
        "run" => Dict{String,Any}("name" => "norm-perception-scaling", "seed" => 1),
        "model" => Dict{String,Any}(
            "name" => "gender_norms",
            "agents_per_gender" => agents_per_gender,
            "network" => Dict{String,Any}(
                "type" => "watts_strogatz", "neighbors_per_side" => 2, "rewiring" => 0.1
            ),
        ),
        "runtime" => Dict{String,Any}("ticks" => ticks),
    )
end

"""
    measure_pass(spec_dict::Dict{String,Any}, ticks::Int)

One measurement pass of this driver. Builds the `RunSpec` with
`parse_spec`, builds the world with `create_world` (setup, outside the
reported kernel numbers), then calls
`GenderNorms.calculate_norm_perception!` `ticks` times on the same
world without advancing any other system, timing each call with
`time_ns()` and taking `Base.gc_num()` deltas around exactly those
calls. Returns a `NamedTuple` with `kernel_s` (sum of the kernel times
over the ticks), `alloc_bytes` and `alloc_count` (totals of the timed
kernel sections), and `setup_s`.
"""
function measure_pass(spec_dict::Dict{String,Any}, ticks::Int)
    spec = GN.parse_spec(spec_dict)
    config = spec.model_config
    setup_start = time_ns()
    world = GN.create_world(spec)
    setup_s = (time_ns() - setup_start) / 1.0e9
    kernel_s = 0.0
    alloc_bytes = 0
    alloc_count = 0
    for _ in 1:ticks
        alloc_start = Base.gc_num()
        kernel_start = time_ns()
        GN.calculate_norm_perception!(world, config.utility)
        kernel_s += (time_ns() - kernel_start) / 1.0e9
        alloc_diff = Base.GC_Diff(Base.gc_num(), alloc_start)
        alloc_bytes += Int(alloc_diff.allocd)
        alloc_count += Int(Base.gc_alloc_count(alloc_diff))
    end
    return (; kernel_s, alloc_bytes, alloc_count, setup_s)
end

"""
    main(args::Vector{String})

Measure the norm perception kernel. Takes the positional arguments
`[agents_per_gender] [ticks] [reps]` (defaults 2000, 30, and 5). Runs
one discarded tiny pass (2 agents per gender, 1 tick) and one discarded
full-size pass for JIT warmup, then `reps` timed passes, each from a
fresh `create_world` on the same specification and seed. Prints the
environment, one human-readable result block with the raw
per-repetition table, and one machine-readable `RESULT` summary line
with the median ms per tick across repetitions and the median per-call
allocations. Returns nothing.
"""
function main(args::Vector{String})
    agents_per_gender = length(args) >= 1 ? parse(Int, args[1]) : 2000
    ticks = length(args) >= 2 ? parse(Int, args[2]) : 30
    reps = length(args) >= 3 ? parse(Int, args[3]) : 5
    (agents_per_gender >= 1 && ticks >= 1 && reps >= 1) ||
        error("agents_per_gender, ticks, and repetitions must be >= 1")
    spec_dict = norm_perception_spec(agents_per_gender, ticks)
    tiny_dict = norm_perception_spec(2, 1)
    measure_pass(tiny_dict, 1)         # discarded JIT warmup, tiny workload
    measure_pass(spec_dict, ticks)     # discarded JIT warmup, full-size workload
    passes = [measure_pass(spec_dict, ticks) for _ in 1:reps]
    kernel = [pass.kernel_s for pass in passes]
    setup = [pass.setup_s for pass in passes]
    per_tick_ms = [(pass.kernel_s / ticks) * 1.0e3 for pass in passes]
    per_call_bytes = [Float64(pass.alloc_bytes) / ticks for pass in passes]
    per_call_count = [Float64(pass.alloc_count) / ticks for pass in passes]
    kernel_median_s = median(kernel)
    median_ms = median(per_tick_ms)
    bytes_median = median(per_call_bytes)
    count_median = median(per_call_count)
    println("kernel calculate_norm_perception!")
    println("cpu ", repr(Sys.cpu_info()[1].model))
    println("hardware_threads ", repr(Sys.CPU_THREADS))
    println("julia_threads ", repr(Threads.nthreads()))
    println("julia_version ", repr(string(VERSION)))
    println("agents_per_gender ", repr(agents_per_gender))
    println("ticks ", repr(ticks))
    println("repetitions ", repr(reps))
    println("median_ms_per_tick ", repr(median_ms))
    println("kernel_sum_ticks_s_median ", repr(kernel_median_s))
    println("kernel_sum_ticks_s_min ", repr(minimum(kernel)))
    println("kernel_sum_ticks_s_max ", repr(maximum(kernel)))
    println("kernel_sum_ticks_s_mean ", repr(sum(kernel) / length(kernel)))
    println("alloc_bytes_per_call_median ", repr(bytes_median))
    println("alloc_count_per_call_median ", repr(count_median))
    println("setup_s_median ", repr(median(setup)))
    println("raw_repetitions")
    println("rep,kernel_s,ms_per_tick,alloc_bytes_per_call,alloc_count_per_call,setup_s")
    for (i, pass) in enumerate(passes)
        println(join((
            repr(i),
            repr(pass.kernel_s),
            repr((pass.kernel_s / ticks) * 1.0e3),
            repr(Float64(pass.alloc_bytes) / ticks),
            repr(Float64(pass.alloc_count) / ticks),
            repr(pass.setup_s),
        ), ","))
    end
    println(join((
        "RESULT",
        "threads=$(Threads.nthreads())",
        "agents_per_gender=$(agents_per_gender)",
        "ticks=$(ticks)",
        "reps=$(reps)",
        "median_ms=$(median_ms)",
        "bytes=$(bytes_median)",
        "objects=$(count_median)",
    ), " "))
    return nothing
end

main(ARGS)
