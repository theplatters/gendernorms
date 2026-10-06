# Read-only profiling of the current Julia implementation. Uses the workload
# and warmup policy of bargaining_kernel.jl (MDR-0011, ADR-0013), the production
# search of MDR-0016, and the tick order of MDR-0022. No package instrumentation,
# dependency changes, or solver changes. Outputs are written outside the repo.
#
# Usage: julia --startup-file=no --project=. benchmark/profile_current.jl \
#     [output_directory] [timings|cpu|allocs|all] [workloads] [reps] [profile_seconds]
# Run one thread count at a time, without concurrent heavy jobs.

module BargainingKernelBench
    include("bargaining_kernel.jl")
end

using GenderNorms
using Profile
using Statistics

const GN = GenderNorms
const STAGES = (:shocks, :norms, :bargaining, :lags, :observers, :preferences)
const SOURCE_DIRECTORY = abspath(joinpath(@__DIR__, "..", "src"))

"""
    csv_cell(value)

Escape one CSV field, including quotes and commas, returning a string.
"""
csv_cell(value) = "\"" * replace(string(value), "\"" => "\"\"") * "\""

"""
    profile_spec(name, ticks)

Build a seed-1 kernel workload, extended with `ws_<N>` and the utility
variants `additive`, `multiplicative`, `multiplicative_weighted`, and
`ces_0.3` at 500 households. Returns a validated run specification.
"""
function profile_spec(name::String, ticks::Int)
    population = match(r"^ws_([0-9]+)$", name)
    utility = name in ("additive", "multiplicative", "multiplicative_weighted", "ces_0.3")
    raw = BargainingKernelBench.workload_spec(
        population !== nothing || utility ? "ws_500" : name, ticks
    )
    if population !== nothing
        raw["model"]["agents_per_gender"] = parse(Int, population.captures[1])
    elseif utility
        raw["model"]["utility"] = name == "ces_0.3" ?
            Dict{String, Any}("type" => "ces", "beta" => 0.3) :
            Dict{String, Any}("type" => name)
    end
    return GN.parse_spec(raw)
end

"""
    stage_call!(stage, world, utility, tick)

Execute one system of the production tick, returning nothing. The order
in `STAGES` matches `step_model!` (MDR-0022).
"""
function stage_call!(stage::Symbol, world, utility, tick::Int)
    if stage === :shocks
        GN.update_shocks!(world, tick)
    elseif stage === :norms
        GN.calculate_norm_perception!(world, utility)
    elseif stage === :bargaining
        GN.set_theta!(world, utility)
    elseif stage === :lags
        GN.update_old_working_time_and_transfer!(world)
    elseif stage === :observers
        GN.update_observer_stats!(world)
    elseif stage === :preferences
        GN.update_preferences(world)
    else
        throw(ArgumentError("unknown stage: $stage"))
    end
    return nothing
end

"""
    stage_pass(spec)

Measure setup and every tick system on a fresh seeded world with `time_ns`
and GC counter deltas. Setup is separate, and allocations of the measurement
arrays are outside the timed sections. Returns per-stage totals and setup time.
"""
function stage_pass(spec)
    elapsed = zeros(length(STAGES))
    bytes = zeros(Int, length(STAGES))
    counts = zeros(Int, length(STAGES))
    gc_elapsed = zeros(length(STAGES))
    setup_start = time_ns()
    world = GN.create_world(spec)
    setup_s = (time_ns() - setup_start) / 1.0e9
    utility = spec.model_config.utility
    for tick in 0:(spec.runtime.ticks - 1), (i, stage) in enumerate(STAGES)
        before = Base.gc_num()
        start = time_ns()
        stage_call!(stage, world, utility, tick)
        elapsed[i] += (time_ns() - start) / 1.0e9
        diff = Base.GC_Diff(Base.gc_num(), before)
        bytes[i] += Int(diff.allocd)
        counts[i] += Int(Base.gc_alloc_count(diff))
        gc_elapsed[i] += diff.total_time / 1.0e9
    end
    return (; elapsed, bytes, counts, gc_elapsed, setup_s)
end

"""
    write_timings(directory, names, reps)

Write raw and summary CSVs for 20-tick stage passes, with two discarded
warmups per workload and no forced GC. Summary values are repetition medians.
"""
function write_timings(directory::String, names, reps::Int)
    open(joinpath(directory, "stages_raw.csv"), "w") do raw
        open(joinpath(directory, "stages.csv"), "w") do summary
            println(raw, "workload,threads,ticks,rep,stage,seconds,bytes,allocations,gc_seconds")
            println(summary, "workload,threads,ticks,stage,median_s,iqr_s,median_bytes,median_allocations,median_gc_s")
            for name in names
                spec = profile_spec(name, 20)
                stage_pass(spec)
                stage_pass(spec)
                passes = [stage_pass(spec) for _ in 1:reps]
                for (rep, pass) in enumerate(passes), (i, stage) in enumerate(STAGES)
                    println(
                        raw, join(
                            (
                                name, Threads.nthreads(), 20, rep, stage,
                                pass.elapsed[i], pass.bytes[i], pass.counts[i], pass.gc_elapsed[i],
                            ), ","
                        )
                    )
                end
                for (i, stage) in enumerate(STAGES)
                    values = [pass.elapsed[i] for pass in passes]
                    println(
                        summary, join(
                            (
                                name, Threads.nthreads(), 20, stage, median(values),
                                quantile(values, 0.75) - quantile(values, 0.25),
                                median([pass.bytes[i] for pass in passes]),
                                median([pass.counts[i] for pass in passes]),
                                median([pass.gc_elapsed[i] for pass in passes]),
                            ), ","
                        )
                    )
                end
                println("timings: ", name)
                flush(summary)
            end
        end
    end
    return nothing
end

"""
    profile_runs(spec, seconds)

Repeat fresh seeded production trajectories for at least `seconds` of wall
time. Used only for sampling, never as the uninstrumented timing baseline.
"""
function profile_runs(spec, seconds::Float64)
    deadline = time_ns() + round(Int, seconds * 1.0e9)
    while time_ns() < deadline
        world = GN.create_world(spec)
        for tick in 0:(spec.runtime.ticks - 1)
            GN.step_model!(GN.GenderNormsModel, world, spec.model_config, tick)
        end
    end
    return nothing
end

"""
    write_cpu_profile(directory, name, seconds)

Collect a warmed single-thread sampling profile, write Julia flat/tree
reports, and aggregate inclusive function counts and leaf locations over
stacks containing `step_model!` only (excluding setup and profiler overhead).
Inclusive percentages overlap and must not be summed.
"""
function write_cpu_profile(directory::String, name::String, seconds::Float64)
    spec = profile_spec(name, 20)
    profile_runs(spec, 0.1)
    Profile.init(n = 10^7, delay = 0.0005)
    Profile.clear()
    Profile.@profile profile_runs(spec, seconds)
    open(joinpath(directory, name * "_cpu_flat.txt"), "w") do io
        Profile.print(
            IOContext(io, :displaysize => (10000, 240));
            format = :flat, sortedby = :count, mincount = 10, C = false
        )
    end
    open(joinpath(directory, name * "_cpu_tree.txt"), "w") do io
        Profile.print(
            IOContext(io, :displaysize => (10000, 240));
            format = :tree, mincount = 10, C = false
        )
    end
    data, dictionary = Profile.retrieve(include_meta = false)
    inclusive = Dict{String, Int}()
    leaves = Dict{String, Int}()
    stack = Base.StackTraces.StackFrame[]
    samples = 0
    for ip in data
        if ip != 0
            append!(stack, dictionary[ip])
            continue
        end
        if any(frame -> frame.func === :step_model!, stack)
            samples += 1
            for name in Set(string(frame.func) for frame in stack if !frame.from_c)
                inclusive[name] = get(inclusive, name, 0) + 1
            end
            leaf = findfirst(frame -> !frame.from_c, stack)
            if leaf !== nothing
                frame = stack[leaf]
                location = string(frame.file, ":", frame.line, ":", frame.func)
                leaves[location] = get(leaves, location, 0) + 1
            end
        end
        empty!(stack)
    end
    for (suffix, counts) in (("functions", inclusive), ("leaves", leaves))
        open(joinpath(directory, name * "_cpu_" * suffix * ".csv"), "w") do io
            println(io, "name,samples,total_tick_samples,percent")
            for (key, count) in sort!(collect(counts); by = last, rev = true)
                println(io, csv_cell(key), ",", count, ",", samples, ",", 100 * count / samples)
            end
        end
    end
    println("cpu: ", name, " (", samples, " tick samples)")
    return nothing
end

"""
    write_allocation_profile(directory, name)

Record every allocation of one warmed 20-tick trajectory, excluding setup.
Write full stacks and totals grouped by the innermost package source location
and allocation type. Profiler sizes exclude some GC bookkeeping; use the
stage GC counter deltas for total bytes. Does not time instrumented code.
"""
function write_allocation_profile(directory::String, name::String)
    spec = profile_spec(name, 20)
    profile_runs(spec, 0.1)
    world = GN.create_world(spec)
    Profile.Allocs.clear()
    Profile.Allocs.@profile sample_rate = 1.0 begin
        for tick in 0:(spec.runtime.ticks - 1)
            GN.step_model!(GN.GenderNormsModel, world, spec.model_config, tick)
        end
    end
    results = Profile.Allocs.fetch()
    counts = Dict{Tuple{String, String}, Tuple{Int, Int}}()
    open(joinpath(directory, name * "_allocation_stacks.txt"), "w") do io
        for allocation in results.allocs
            own = findfirst(frame -> startswith(string(frame.file), SOURCE_DIRECTORY * "/"), allocation.stacktrace)
            frame = own === nothing ? nothing : allocation.stacktrace[own]
            location = frame === nothing ? "outside_package" : string(frame.file, ":", frame.line, ":", frame.func)
            key = (location, string(allocation.type))
            count, bytes = get(counts, key, (0, 0))
            counts[key] = (count + 1, bytes + allocation.size)
        end
        for (key, (count, bytes)) in sort!(collect(counts); by = pair -> pair.second[2], rev = true)
            println(io, count, " allocations / ", bytes, " bytes: ", key)
            example = findfirst(results.allocs) do allocation
                string(allocation.type) == key[2] && any(
                    frame -> string(frame.file, ":", frame.line, ":", frame.func) == key[1], allocation.stacktrace
                )
            end
            if example !== nothing
                for frame in results.allocs[example].stacktrace
                    println(io, "  ", frame)
                end
            end
        end
    end
    open(joinpath(directory, name * "_allocations.csv"), "w") do io
        println(io, "location,type,count,bytes")
        for ((location, type), (count, bytes)) in sort!(collect(counts); by = pair -> pair.second[2], rev = true)
            println(io, csv_cell(location), ",", csv_cell(type), ",", count, ",", bytes)
        end
    end
    println("allocs: ", name, " (", length(results.allocs), " allocations)")
    Profile.Allocs.clear()
    return nothing
end

"""
    main(args)

Run the requested profiling sections and write artifacts to the chosen
directory. CPU and allocation sections require one Julia worker thread;
stage timings also support multithreaded runs. Returns nothing.
"""
function main(args::Vector{String})
    length(args) <= 5 || error("expected at most five arguments")
    directory = length(args) >= 1 ? args[1] : "/tmp/opencode/gendernorms-current-profile"
    section = length(args) >= 2 ? args[2] : "all"
    names = length(args) >= 3 ? String.(split(args[3], ',')) : ["ws_500", "heterogeneous"]
    reps = length(args) >= 4 ? parse(Int, args[4]) : 15
    seconds = length(args) >= 5 ? parse(Float64, args[5]) : 5.0
    section in ("timings", "cpu", "allocs", "all") || error("unknown section: $section")
    reps >= 1 && isfinite(seconds) && seconds > 0 || error("reps and seconds must be positive")
    section != "timings" && Threads.nthreads() != 1 && error("CPU/allocation profiles require one thread")
    mkpath(directory)
    open(joinpath(directory, "environment_" * section * ".txt"), "w") do io
        println(io, "Julia ", VERSION)
        println(io, "CPU ", Sys.cpu_info()[1].model)
        println(io, "Worker threads ", Threads.nthreads())
        println(io, "Arguments ", repr(args))
    end
    section in ("timings", "all") && write_timings(directory, names, reps)
    for name in names
        section in ("cpu", "all") && write_cpu_profile(directory, name, seconds)
        section in ("allocs", "all") && write_allocation_profile(directory, name)
    end
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
