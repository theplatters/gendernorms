# Scheduling sweeps for the household bargaining kernel `set_theta!`
# (`src/systems/household_bargaining.jl`, see `ADR-0023`): chunk-size
# sweep (`chunk` keyword), scheduling-mechanism variant comparison
# (`schedule` keyword: `:parallel` = bounded worker tasks over a shared
# atomic chunk cursor, `:queue` = bounded worker tasks over a shared
# work queue), and the serial-crossover sweep (`ws_<N>` populations
# with forced `:serial` / `:parallel` and `:auto` spot checks). The
# measurement methodology is exactly the one of
# `benchmark/bargaining_kernel.jl` (`MDR-0011`, `ADR-0013`): seed-1
# workload specs, one discarded tiny and one discarded full-size JIT
# warmup pass per configuration, one fresh `create_world` per measured
# repetition (identical initial states across repetitions), 20 ticks
# per pass with only the `set_theta!` calls of the `MDR-0022` tick
# order timed via `time_ns()` and `Base.gc_num()` deltas taken around
# exactly those calls, and one `GenderNorms.run` end-to-end timing per
# repetition reported separately. Workload specs come from
# `BargainingKernelBench.workload_spec` (the same module contract
# `benchmark/anchor_local_validation.jl` uses), extended additively
# with `ws_<N>` (seed 1, Watts-Strogatz `neighbors_per_side` 2,
# `rewiring` 0.1, CES `beta` 0.5, `N` agents per gender = `N`
# households); the fixed workload names and their seed contract are
# unchanged. The prints below are the script's intended program
# output, not debug output (same policy as
# `benchmark/bargaining_kernel.jl`).
#
# Usage (one thread count and one tree at a time; do not run other
# heavy jobs while timing):
#   JULIA_NUM_THREADS=N julia --project=. benchmark/scheduling_sweep.jl \
#       [workloads] [ticks] [reps] [chunks] [schedules] [search]
#
# - `workloads`: comma-separated workload names (`ws_500`,
#   `heterogeneous`, `ws_100`, ... of `BargainingKernelBench`, or
#   `ws_<N>`), default `ws_500`.
# - `ticks` default 20, `reps` default 15.
# - `chunks`: comma-separated positive chunk sizes, default
#   `4,8,16,32`.
# - `schedules`: comma-separated subset of `auto,serial,parallel,queue`
#   (default `auto`); `serial`, `parallel`, and `auto` run against the
#   current tree, `queue` requires a tree whose `set_theta!` implements
#   the shared-work-queue worker variant (see
#   `benchmark/scheduling_tuning.md`; the throwaway measurement tree
#   is /tmp/opencode/gendernorms-queue). The variant switch is the
#   `schedule` symbol itself, so this file runs unchanged against the
#   current tree for the schedules it supports.
# - `search`: `local` or `discovery`, default `local`.
#
# Configurations run in the order workload -> chunk -> schedule with
# full-precision `repr` numbers; every configuration prints its raw
# per-repetition table, and combined `csv` / `raw_csv` blocks are
# printed at the end so medians and IQRs can be recomputed offline.

module BargainingKernelBench
    include("bargaining_kernel.jl")
end

using GenderNorms
using Statistics

const GN = GenderNorms

"""
        sweep_workload_spec(name::String, ticks::Int)

Run specification table of the sweep workload `name` in the shape
accepted by `GenderNorms.parse_spec` (see `ADR-0012`). `ws_<N>` builds
the seed-1 Watts-Strogatz family workload of `BargainingKernelBench`
(`neighbors_per_side` 2, `rewiring` 0.1, CES `beta` 0.5) with `N`
agents per gender = `N` households; every other name delegates to
`BargainingKernelBench.workload_spec` unchanged. Returns the
dictionary.
"""
function sweep_workload_spec(name::String, ticks::Int)
    m = match(r"^ws_([0-9]+)$", name)
    if m !== nothing
        n = parse(Int, m.captures[1])
        n >= 1 || error("ws_<N> needs N >= 1, got $(repr(name))")
        return Dict{String, Any}(
            "run" => Dict{String, Any}("name" => "bargaining-kernel-" * name, "seed" => 1),
            "model" => Dict{String, Any}(
                "name" => "gender_norms",
                "agents_per_gender" => n,
                "network" => Dict{String, Any}(
                    "type" => "watts_strogatz", "neighbors_per_side" => 2, "rewiring" => 0.1
                ),
                "utility" => Dict{String, Any}("type" => "ces", "beta" => 0.5),
            ),
            "runtime" => Dict{String, Any}("ticks" => ticks),
        )
    end
    return BargainingKernelBench.workload_spec(name, ticks)
end

"""
        measure_pass(spec_dict::Dict{String,Any}, ticks::Int, chunk::Int, schedule::Symbol, search::Symbol)

One measurement pass of this driver, identical to
`BargainingKernelBench.measure_pass` except that `set_theta!` receives
the sweep keywords `chunk`, `schedule`, and `search`. Builds the
`RunSpec` with `parse_spec`, times `create_world` (setup, outside the
reported kernel numbers), then drives `ticks` ticks manually in the
exact `step_model!` order of `MDR-0022` (`update_shocks!`,
`calculate_norm_perception!`, `set_theta!`,
`update_old_working_time_and_transfer!`,
`update_observer_stats!`, `update_preferences`), timing only the
`set_theta!` calls with `time_ns()` and taking `Base.gc_num()` deltas
around exactly those calls. Then times one `GenderNorms.run` on a
fresh world from the same specification with the tree default
`set_theta!` configuration (end-to-end, reported separately from the
kernel numbers). Returns a `NamedTuple` with `kernel_s` (sum of the
`set_theta!` times over the ticks), `alloc_bytes` and `alloc_count`
(totals of the timed `set_theta!` sections), `setup_s`, and `e2e_s`.
"""
function measure_pass(
        spec_dict::Dict{String, Any}, ticks::Int, chunk::Int, schedule::Symbol, search::Symbol
    )
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
        GN.set_theta!(world, config.utility; chunk = chunk, schedule = schedule, search = search)
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
        benchmark_config(name::String, ticks::Int, reps::Int, chunk::Int, schedule::Symbol, search::Symbol)

Benchmark one sweep configuration (workload `name`, `chunk` size, and
forced `schedule` / `search`). Runs one discarded tiny pass (2 agents
per gender, 1 tick) and one discarded full-size pass for JIT warmup
(the report excludes all compilation and world construction), then
`reps` timed passes, each from a fresh `create_world` on the same
specification and seed (identical initial states across repetitions;
no GC is forced between repetitions, mirroring `MDR-0011`). Prints one
result block for the configuration with full-precision `repr` numbers,
including the raw per-repetition table of the measured passes, and
returns the CSV row fields of the configuration as a `NamedTuple` plus
`raw`, the per-repetition `NamedTuple` vector (`rep`, `kernel_s`,
`alloc_bytes`, `alloc_count`, `setup_s`, `e2e_s`) of the measured
passes.
"""
function benchmark_config(
        name::String, ticks::Int, reps::Int, chunk::Int, schedule::Symbol, search::Symbol
    )
    spec_dict = sweep_workload_spec(name, ticks)
    tiny_dict = sweep_workload_spec(name, 1)
    tiny_dict["model"]["agents_per_gender"] = 2
    measure_pass(tiny_dict, 1, chunk, schedule, search)          # discarded JIT warmup, tiny workload
    measure_pass(spec_dict, ticks, chunk, schedule, search)      # discarded JIT warmup, full-size workload
    passes = [measure_pass(spec_dict, ticks, chunk, schedule, search) for _ in 1:reps]
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
    alloc_bytes_values = [Float64(pass.alloc_bytes) for pass in passes]
    alloc_count_values = [Float64(pass.alloc_count) for pass in passes]
    alloc_bytes_median = median(alloc_bytes_values)
    alloc_count_median = median(alloc_count_values)
    households = spec_dict["model"]["agents_per_gender"]
    row = (
        workload = name,
        schedule = schedule,
        chunk = chunk,
        search = search,
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
        alloc_bytes_iqr = iqr(alloc_bytes_values),
        alloc_count = alloc_count_median,
        alloc_count_iqr = iqr(alloc_count_values),
        alloc_bytes_per_tick = alloc_bytes_median / ticks,
        alloc_count_per_tick = alloc_count_median / ticks,
        alloc_bytes_per_household_tick = alloc_bytes_median / ticks / households,
        alloc_count_per_household_tick = alloc_count_median / ticks / households,
        setup_median_s = median(setup),
        e2e_median_s = median(e2e),
        e2e_iqr_s = iqr(e2e),
        raw = raw,
    )
    println("config")
    println("  workload ", repr(name))
    println("  schedule ", repr(String(schedule)))
    println("  chunk ", repr(chunk))
    println("  search ", repr(String(search)))
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
    println("  kernel_alloc_bytes_iqr ", repr(row.alloc_bytes_iqr))
    println("  kernel_alloc_count_median ", repr(row.alloc_count))
    println("  kernel_alloc_count_iqr ", repr(row.alloc_count_iqr))
    println("  kernel_alloc_bytes_per_tick ", repr(row.alloc_bytes_per_tick))
    println("  kernel_alloc_count_per_tick ", repr(row.alloc_count_per_tick))
    println("  kernel_alloc_bytes_per_household_tick ", repr(row.alloc_bytes_per_household_tick))
    println("  kernel_alloc_count_per_household_tick ", repr(row.alloc_count_per_household_tick))
    println("  setup_s_median ", repr(row.setup_median_s))
    println("  e2e_run_s_median ", repr(row.e2e_median_s))
    println("  e2e_run_s_iqr ", repr(row.e2e_iqr_s))
    println("  raw_repetitions")
    println("  ", raw_csv_header())
    for entry in row.raw
        println("  ", raw_csv_row(row, entry))
    end
    return row
end

"""
        csv_header()

Column names of the machine-readable result table, one row per
configuration (workload, schedule, chunk size) and run (thread count).
Returns the header string.
"""
csv_header() = "workload,schedule,chunk,search,threads,ticks,repetitions,households," *
    "kernel_median_s,kernel_iqr_s,kernel_min_s,kernel_max_s,kernel_mean_s," *
    "alloc_bytes,alloc_bytes_iqr,alloc_count,alloc_count_iqr," *
    "alloc_bytes_per_tick,alloc_count_per_tick," *
    "alloc_bytes_per_household_tick,alloc_count_per_household_tick," *
    "setup_median_s,e2e_median_s,e2e_iqr_s"

"""
        csv_row(row)

Machine-readable CSV line of one `benchmark_config` result row. The
floats use `repr` for full precision. Returns the line without trailing
newline.
"""
function csv_row(row)
    return join(
        (
            row.workload,
            row.schedule,
            repr(row.chunk),
            row.search,
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
            repr(row.alloc_bytes_iqr),
            repr(row.alloc_count),
            repr(row.alloc_count_iqr),
            repr(row.alloc_bytes_per_tick),
            repr(row.alloc_count_per_tick),
            repr(row.alloc_bytes_per_household_tick),
            repr(row.alloc_count_per_household_tick),
            repr(row.setup_median_s),
            repr(row.e2e_median_s),
            repr(row.e2e_iqr_s),
        ), ","
    )
end

"""
        raw_csv_header()

Column names of the machine-readable raw per-repetition table, one line
per measured repetition of every configuration and run (thread count):
configuration identity, run shape, repetition index, then the raw
measured values of that repetition (kernel sum over ticks, timed
allocation totals, setup, end-to-end). Returns the header string.
"""
raw_csv_header() = "workload,schedule,chunk,search,threads,ticks,households,rep," *
    "kernel_s,alloc_bytes,alloc_count,setup_s,e2e_s"

"""
        raw_csv_row(row, entry)

Machine-readable CSV line of one measured repetition `entry` (the `raw`
vector of a `benchmark_config` result row) under the identity fields of
that row. The floats use `repr` for full precision. Returns the line
without trailing newline.
"""
function raw_csv_row(row, entry)
    return join(
        (
            row.workload,
            row.schedule,
            repr(row.chunk),
            row.search,
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
        parse_csv_list(text::String)

Comma-separated command-line list split into nonempty stripped
entries. Returns the `Vector{String}`.
"""
function parse_csv_list(text::String)
    return [String(strip(entry)) for entry in split(text, ",") if !isempty(strip(entry))]
end

"""
        main(args::Vector{String})

Run the scheduling sweeps. Takes the positional arguments
`[workloads] [ticks] [reps] [chunks] [schedules] [search]` (see the
usage block at the top of this file). Prints the environment (CPU,
hardware threads, Julia threads, Julia version), one result block per
configuration in workload -> chunk -> schedule order with
full-precision numbers and its raw per-repetition table, the
machine-readable CSV table (header plus one row per configuration),
and the machine-readable raw per-repetition table (`raw_csv`, header
plus one line per measured repetition). Returns nothing.
"""
function main(args::Vector{String})
    names = length(args) >= 1 ? parse_csv_list(args[1]) : ["ws_500"]
    ticks = length(args) >= 2 ? parse(Int, args[2]) : 20
    reps = length(args) >= 3 ? parse(Int, args[3]) : 15
    chunks = length(args) >= 4 ? [parse(Int, entry) for entry in parse_csv_list(args[4])] : [4, 8, 16, 32]
    schedule_names = length(args) >= 5 ? parse_csv_list(args[5]) : ["auto"]
    search_name = length(args) >= 6 ? String(strip(args[6])) : "local"
    (ticks >= 1 && reps >= 1) || error("ticks and repetitions must be >= 1")
    all(chunk -> chunk >= 1, chunks) || error("chunk sizes must be >= 1")
    isempty(names) && error("at least one workload is required")
    isempty(chunks) && error("at least one chunk size is required")
    isempty(schedule_names) && error("at least one schedule is required")
    search_name in ("local", "discovery") ||
        error("search must be local or discovery, got $(repr(search_name))")
    search = Symbol(search_name)
    schedules = Symbol[]
    for entry in schedule_names
        schedule = Symbol(entry)
        schedule in (:auto, :serial, :parallel, :queue) ||
            error("schedule must be auto, serial, parallel, or queue, got $(repr(entry))")
        push!(schedules, schedule)
    end
    println("cpu ", repr(Sys.cpu_info()[1].model))
    println("hardware_threads ", repr(Sys.CPU_THREADS))
    println("julia_threads ", repr(Threads.nthreads()))
    println("julia_version ", repr(string(VERSION)))
    rows = []
    for name in names
        for chunk in chunks
            for schedule in schedules
                push!(rows, benchmark_config(name, ticks, reps, chunk, schedule, search))
            end
        end
    end
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
