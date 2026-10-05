# Kernel benchmark for the household bargaining loop `set_theta!`
# (`src/systems/household_bargaining.jl`, port of NetLogo `set-theta` and
# `calculate-payoff`, ODD section Transfer bargaining). Times only the
# `set_theta!` calls of the `step_model!` tick order (`MDR-0022`) on
# plain spec dictionaries (`parse_spec`, see `ADR-0012`), with one fresh
# `create_world` per repetition (identical initial states across
# repetitions), and reports the sum over ticks per repetition as
# median/min/max/IQR over repetitions plus the allocation totals of the
# timed section. End-to-end `GenderNorms.run` timings are reported
# separately. Every result block also carries the raw per-repetition
# table (one line per measured repetition: kernel sum over ticks, timed
# allocation totals, setup, end-to-end), and a combined raw CSV is
# printed after the summary CSV, so medians and IQRs can be recomputed
# offline. Methodology: `MDR-0011` and `ADR-0013`; the benchmark
# measures a kernel of this package and does not change model behavior.
# The prints below are the script's intended program output, not debug
# output (same policy as `benchmark/threading_speedup.jl`).
#
# Usage:
#   JULIA_NUM_THREADS=1 julia --project=. benchmark/bargaining_kernel.jl [workloads] [ticks] [repetitions]
#   JULIA_NUM_THREADS=8 julia --project=. benchmark/bargaining_kernel.jl [workloads] [ticks] [repetitions]
#
# `workloads` is a comma-separated list of workload names or `all`
# (default `all`): ws_500 (representative), ws_100, homogeneous_mixing,
# no_network, homophily, heterogeneous. `ticks` defaults to 20 and
# `repetitions` to 15. Run one thread count at a time and do not run
# other heavy jobs while timing.

using GenderNorms
using Statistics

const GN = GenderNorms

"""
    WORKLOAD_NAMES

Workload names of this driver in default run order. `ws_500` is the
representative workload (see the workload table in `benchmark/README.md`);
`heterogeneous` pairs the `ws_500` network with a gendered wage gap and
high initial conformism so households differ strongly.
"""
const WORKLOAD_NAMES = ("ws_500", "ws_100", "homogeneous_mixing", "no_network", "homophily", "heterogeneous")

"""
    network_table(name::String)

`[model.network]` table of the workload `name` (keys of
`_parse_network_table`, see `src/runtime/gender_norms_model.jl`):
`watts_strogatz` with `neighbors_per_side` 2 and `rewiring` 0.1 for
`ws_500`, `ws_100`, and `heterogeneous` (the fixed configuration of
`benchmark/threading_speedup.jl`), `homogeneous_mixing`, `none`,
and `homophily` with `m` 2 (the mapped `preferential-attachment-min-degree`
of `benchmark/README.md`). Returns the dictionary.
"""
function network_table(name::String)
    if name in ("ws_500", "ws_100", "heterogeneous")
        return Dict{String, Any}("type" => "watts_strogatz", "neighbors_per_side" => 2, "rewiring" => 0.1)
    end
    if name == "homogeneous_mixing"
        return Dict{String, Any}("type" => "homogeneous_mixing")
    end
    if name == "no_network"
        return Dict{String, Any}("type" => "none")
    end
    if name == "homophily"
        return Dict{String, Any}("type" => "homophily", "m" => 2)
    end
    error("unknown workload $(repr(name))")
end

"""
    workload_spec(name::String, ticks::Int)

Run specification table of the workload `name` (the shape accepted by
`GenderNorms.parse_spec`, see `ADR-0012`): seed 1, CES utility with
`beta` 0.5, 500 agents per gender (100 for `ws_100`), and the network of
`network_table`. `heterogeneous` additionally sets the gendered trait
means `mean_wage` to 2.0/0.5 (men/women) and `initial_conformism` to
50.0/50.0, the high-conformism end of the benchmark matrix
(`benchmark/README.md`), so households differ strongly. Returns the
dictionary.
"""
function workload_spec(name::String, ticks::Int)
    name in WORKLOAD_NAMES || error("unknown workload $(repr(name))")
    agents_per_gender = name == "ws_100" ? 100 : 500
    model = Dict{String, Any}(
        "name" => "gender_norms",
        "agents_per_gender" => agents_per_gender,
        "network" => network_table(name),
        "utility" => Dict{String, Any}("type" => "ces", "beta" => 0.5),
    )
    if name == "heterogeneous"
        model["mean_wage"] = Dict{String, Any}("men" => 2.0, "women" => 0.5)
        model["initial_conformism"] = Dict{String, Any}("men" => 50.0, "women" => 50.0)
    end
    return Dict{String, Any}(
        "run" => Dict{String, Any}("name" => "bargaining-kernel-" * name, "seed" => 1),
        "model" => model,
        "runtime" => Dict{String, Any}("ticks" => ticks),
    )
end

"""
    measure_pass(spec_dict::Dict{String,Any}, ticks::Int)

One measurement pass of this driver. Builds the `RunSpec` with
`parse_spec`, times `create_world` (setup, outside the reported kernel
numbers), then drives `ticks` ticks manually in the exact `step_model!`
order of `MDR-0022` (`update_shocks!`, `calculate_norm_perception!`,
`set_theta!`, `update_old_working_time_and_transfer!`,
`update_observer_stats!`, `update_preferences`), timing only the
`set_theta!` calls with `time_ns()` and taking `Base.gc_num()` deltas
around exactly those calls. Then times one `GenderNorms.run` on a fresh
world from the same specification (end-to-end, reported separately).
Returns a `NamedTuple` with `kernel_s` (sum of the `set_theta!` times
over the ticks), `alloc_bytes` and `alloc_count` (totals of the timed
`set_theta!` sections), `setup_s`, and `e2e_s`.
"""
function measure_pass(spec_dict::Dict{String, Any}, ticks::Int)
    spec = GN.parse_spec(spec_dict)
    config = spec.model_config
    setup_start = time_ns()
    world = GN.create_world(spec)
    setup_s = (time_ns() - setup_start) / 1.0e9
    kernel_s = 0.0
    alloc_bytes = 0
    alloc_count = 0
    for tick in 0:(ticks - 1)
        GN.update_shocks!(world, tick)
        GN.calculate_norm_perception!(world, config.utility)
        alloc_start = Base.gc_num()
        kernel_start = time_ns()
        GN.set_theta!(world, config.utility)
        kernel_s += (time_ns() - kernel_start) / 1.0e9
        alloc_diff = Base.GC_Diff(Base.gc_num(), alloc_start)
        alloc_bytes += Int(alloc_diff.allocd)
        alloc_count += Int(Base.gc_alloc_count(alloc_diff))
        GN.update_old_working_time_and_transfer!(world)
        GN.update_observer_stats!(world)
        GN.update_preferences(world)
    end
    e2e_world = GN.create_world(spec)
    e2e_start = time_ns()
    e2e_result = GN.run(e2e_world)
    e2e_s = (time_ns() - e2e_start) / 1.0e9
    GN.is_success(e2e_result) || error("end-to-end run failed: $(e2e_result.error)")
    return (; kernel_s, alloc_bytes, alloc_count, setup_s, e2e_s)
end

"""
    iqr(values::Vector{Float64})

Interquartile range of `values`: the 75th percentile minus the 25th
percentile, with `Statistics.quantile` linear interpolation. Returns a
`Float64`.
"""
iqr(values::Vector{Float64}) = quantile(values, 0.75) - quantile(values, 0.25)

"""
    benchmark_workload(name::String, ticks::Int, reps::Int)

Benchmark one workload. Runs one discarded tiny pass (2 agents per
gender, 1 tick) and one discarded full-size pass for JIT warmup (the
report excludes all compilation and world construction), then `reps`
timed passes, each from a fresh `create_world` on the same specification
and seed (identical initial states across repetitions; no GC is forced
between repetitions, mirroring `MDR-0011`). Prints one result block for
the workload with full-precision `repr` numbers, including the raw
per-repetition table of the measured passes, and returns the CSV row
fields of the workload as a `NamedTuple` plus `raw`, the per-repetition
`NamedTuple` vector (`rep`, `kernel_s`, `alloc_bytes`, `alloc_count`,
`setup_s`, `e2e_s`) of the measured passes.
"""
function benchmark_workload(name::String, ticks::Int, reps::Int)
    spec_dict = workload_spec(name, ticks)
    tiny_dict = workload_spec(name, 1)
    tiny_dict["model"]["agents_per_gender"] = 2
    measure_pass(tiny_dict, 1)          # discarded JIT warmup, tiny workload
    measure_pass(spec_dict, ticks)      # discarded JIT warmup, full-size workload
    passes = [measure_pass(spec_dict, ticks) for _ in 1:reps]
    raw = [
        (;
                rep = i,
                kernel_s = pass.kernel_s,
                alloc_bytes = pass.alloc_bytes,
                alloc_count = pass.alloc_count,
                setup_s = pass.setup_s,
                e2e_s = pass.e2e_s,
            ) for (i, pass) in enumerate(passes)
    ]
    kernel = [pass.kernel_s for pass in passes]
    e2e = [pass.e2e_s for pass in passes]
    setup = [pass.setup_s for pass in passes]
    alloc_bytes_median = median([Float64(pass.alloc_bytes) for pass in passes])
    alloc_count_median = median([Float64(pass.alloc_count) for pass in passes])
    households = spec_dict["model"]["agents_per_gender"]
    row = (
        workload = name,
        threads = Threads.nthreads(),
        ticks = ticks,
        reps = reps,
        households = households,
        kernel_median_s = median(kernel),
        kernel_iqr_s = iqr(kernel),
        kernel_min_s = minimum(kernel),
        kernel_max_s = maximum(kernel),
        kernel_mean_s = mean(kernel),
        alloc_bytes = alloc_bytes_median,
        alloc_count = alloc_count_median,
        alloc_bytes_per_tick = alloc_bytes_median / ticks,
        alloc_count_per_tick = alloc_count_median / ticks,
        alloc_bytes_per_household_tick = alloc_bytes_median / ticks / households,
        alloc_count_per_household_tick = alloc_count_median / ticks / households,
        setup_median_s = median(setup),
        e2e_median_s = median(e2e),
        raw = raw,
    )
    println("workload ", repr(name))
    println("  agents_per_gender ", repr(households))
    println("  households ", repr(households))
    println("  ticks ", repr(ticks))
    println("  repetitions ", repr(reps))
    println("  threads ", repr(Threads.nthreads()))
    println("  kernel_sum_ticks_s_median ", repr(row.kernel_median_s))
    println("  kernel_sum_ticks_s_iqr ", repr(row.kernel_iqr_s))
    println("  kernel_sum_ticks_s_min ", repr(row.kernel_min_s))
    println("  kernel_sum_ticks_s_max ", repr(row.kernel_max_s))
    println("  kernel_sum_ticks_s_mean ", repr(row.kernel_mean_s))
    println("  kernel_alloc_bytes_median ", repr(row.alloc_bytes))
    println("  kernel_alloc_count_median ", repr(row.alloc_count))
    println("  kernel_alloc_bytes_per_tick ", repr(row.alloc_bytes_per_tick))
    println("  kernel_alloc_count_per_tick ", repr(row.alloc_count_per_tick))
    println("  kernel_alloc_bytes_per_household_tick ", repr(row.alloc_bytes_per_household_tick))
    println("  kernel_alloc_count_per_household_tick ", repr(row.alloc_count_per_household_tick))
    println("  setup_s_median ", repr(row.setup_median_s))
    println("  e2e_run_s_median ", repr(row.e2e_median_s))
    println("  raw_repetitions")
    println("  ", raw_csv_header())
    for entry in row.raw
        println("  ", raw_csv_row(row, entry))
    end
    return row
end

"""
    csv_header()

Column names of the machine-readable result table, one row per workload
and run (thread count). Returns the header string.
"""
csv_header() = "workload,threads,ticks,repetitions,households," *
    "kernel_median_s,kernel_iqr_s,kernel_min_s,kernel_max_s,kernel_mean_s," *
    "alloc_bytes,alloc_count,alloc_bytes_per_tick,alloc_count_per_tick," *
    "alloc_bytes_per_household_tick,alloc_count_per_household_tick," *
    "setup_median_s,e2e_median_s"

"""
    csv_row(row)

Machine-readable CSV line of one `benchmark_workload` result row. The
floats use `repr` for full precision. Returns the line without trailing
newline.
"""
function csv_row(row)
    return join(
        (
            row.workload,
            repr(row.threads),
            repr(row.ticks),
            repr(row.reps),
            repr(row.households),
            repr(row.kernel_median_s),
            repr(row.kernel_iqr_s),
            repr(row.kernel_min_s),
            repr(row.kernel_max_s),
            repr(row.kernel_mean_s),
            repr(row.alloc_bytes),
            repr(row.alloc_count),
            repr(row.alloc_bytes_per_tick),
            repr(row.alloc_count_per_tick),
            repr(row.alloc_bytes_per_household_tick),
            repr(row.alloc_count_per_household_tick),
            repr(row.setup_median_s),
            repr(row.e2e_median_s),
        ), ","
    )
end

"""
    raw_csv_header()

Column names of the machine-readable raw per-repetition table, one line
per measured repetition of every workload and run (thread count):
workload identity, run shape, repetition index, then the raw measured
values of that repetition (kernel sum over ticks, timed allocation
totals, setup, end-to-end). Returns the header string.
"""
raw_csv_header() = "workload,threads,ticks,households,rep," *
    "kernel_s,alloc_bytes,alloc_count,setup_s,e2e_s"

"""
    raw_csv_row(row, entry)

Machine-readable CSV line of one measured repetition `entry` (the `raw`
vector of a `benchmark_workload` result row) under the identity fields
of that row. The floats use `repr` for full precision. Returns the line
without trailing newline.
"""
function raw_csv_row(row, entry)
    return join(
        (
            row.workload,
            repr(row.threads),
            repr(row.ticks),
            repr(row.households),
            repr(entry.rep),
            repr(entry.kernel_s),
            repr(entry.alloc_bytes),
            repr(entry.alloc_count),
            repr(entry.setup_s),
            repr(entry.e2e_s),
        ), ","
    )
end

"""
    main(args::Vector{String})

Run the kernel benchmark. Takes the positional arguments
`[workloads] [ticks] [repetitions]`: `workloads` is a comma-separated
list of workload names or `all` (default `all`), `ticks` defaults to 20,
and `repetitions` to 15. Prints the environment (CPU, hardware threads,
Julia threads, Julia version), one result block per workload with
full-precision numbers and its raw per-repetition table, the
machine-readable CSV table (header plus one row per workload), and the
machine-readable raw per-repetition table (`raw_csv`, header plus one
line per measured repetition). Returns nothing.
"""
function main(args::Vector{String})
    selection = length(args) >= 1 ? split(args[1], ",") : collect(WORKLOAD_NAMES)
    ticks = length(args) >= 2 ? parse(Int, args[2]) : 20
    reps = length(args) >= 3 ? parse(Int, args[3]) : 15
    (ticks >= 1 && reps >= 1) || error("ticks and repetitions must be >= 1")
    names = String[]
    for entry in selection
        name = String(entry)
        if name == "all"
            append!(names, WORKLOAD_NAMES)
            continue
        end
        name in WORKLOAD_NAMES || error("unknown workload $(repr(name))")
        push!(names, name)
    end
    println("cpu ", repr(Sys.cpu_info()[1].model))
    println("hardware_threads ", repr(Sys.CPU_THREADS))
    println("julia_threads ", repr(Threads.nthreads()))
    println("julia_version ", repr(string(VERSION)))
    rows = [benchmark_workload(name, ticks, reps) for name in names]
    println("csv")
    println(csv_header())
    for row in rows
        println(csv_row(row))
    end
    println("raw_csv")
    println(raw_csv_header())
    for row in rows
        for entry in row.raw
            println(raw_csv_row(row, entry))
        end
    end
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
