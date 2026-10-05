# Reproducible validation of `MDR-0015` / `ADR-0020`: identical-state
# quality, 25-tick trajectories, and kernel cost against retained discovery.
# NetLogo `set-theta` / `calculate-payoff`, ODD section Transfer bargaining.
# Prints are intended benchmark output (`MDR-0011`, `ADR-0013`).
# Usage: JULIA_NUM_THREADS=1 julia --project=. benchmark/anchor_local_validation.jl
#          [output-directory] [quality|trajectories|timing|all]

using Ark
using GenderNorms
using Statistics

module BargainingKernelBench
include("bargaining_kernel.jl")
end

const GN = GenderNorms
const VALIDATION_WORKLOADS = ("ws_500", "heterogeneous", "low_conformism")

"""
    validation_spec(name::String, ticks::Int)

Reuse the kernel harness's exact seed-1 workload; low_conformism changes
only the two initial conformism means to zero. Return the resolved spec.
"""
function validation_spec(name::String, ticks::Int)
    raw = BargainingKernelBench.workload_spec(name == "low_conformism" ? "ws_500" : name, ticks)
    if name == "low_conformism"
        raw["model"]["initial_conformism"] = Dict{String,Any}("men" => 0.0, "women" => 0.0)
    end
    return GN.parse_spec(raw)
end

"""
    household_args(world, i::Int, config)

Extract the identical household state and lagged norms seen by set_theta!.
Return the six pure bargaining arguments, in their call order.
"""
function household_args(world, i::Int, config)
    net = Ark.get_resource(world, GN.SocialNetwork)
    woman = net.women_entities[i]
    wage_w, time_w, transfer_w, conformism_w, preference_w, spouse = Ark.get_components(
        world, woman, (GN.Wage, GN.WorkingTime, GN.TransferToWoman, GN.Conformism,
            GN.PreferencePrivate, GN.Spouse),
    )
    wage_m, time_m, conformism_m, preference_m = Ark.get_components(
        world, spouse.entity, (GN.Wage, GN.WorkingTime, GN.Conformism, GN.PreferencePrivate),
    )
    man_vertex = findfirst(isequal(spouse.entity), net.men_entities)
    nw = GN.norm_means(world, net, i, true, nothing, Ark.Entity[])
    nm = GN.norm_means(world, net, man_vertex, false, nothing, Ark.Entity[])
    pw = GN.payoff_params(wage_w.current, wage_m.current, preference_w.current,
        conformism_w.amount, nw, GN.Female())
    pm = GN.payoff_params(wage_m.current, wage_w.current, preference_m.current,
        conformism_m.amount, nm, GN.Male())
    return (time_w.current, time_m.current, transfer_w.current, pw, pm, config.utility)
end

"""
    payoff_context(args)

Recompute outside utilities and the status-equilibrium warm start without
altering objective semantics. Return the tuple used by equilibrium_payoff.
"""
function payoff_context(args)
    hw_init, hm_init, theta_init, pw, pm, config = args
    hw_out, hm_out = GN.mutual_best_response(hw_init, hm_init, 0.0, pw, pm, config)
    uw = GN.individual_utility(hw_out, hm_out, 0.0, pw, config)
    um = GN.individual_utility(hm_out, hw_out, 0.0, pm, config)
    theta0 = clamp(theta_init, -1.0, 1.0)
    hw, hm = theta0 === 0.0 ? (hw_out, hm_out) :
        GN.mutual_best_response(hw_init, hm_init, theta0, pw, pm, config)
    return (hw, hm, uw, um, pw, pm, config)
end

"""
    bundle_payoff(bundle, context)

Cross-evaluate a committed bundle with the identical-state outside options,
using its committed hours rather than choosing a different fixed point.
"""
function bundle_payoff(bundle, context)
    _, _, uw, um, pw, pm, config = context
    return GN.nash_product(bundle..., uw, um, pw, pm, config)
end

"""
    fine_grid_best(theta0::Float64, context)

Find the maximum of the unchanged objective, certificate bypassed, on
1e-4 grids over +/-0.02 of both anchors and 2.5e-4 over the domain.
Include the status quo itself and use its fixed warm start everywhere.
"""
function fine_grid_best(theta0::Float64, context)
    points = Set{Float64}([theta0, 0.0])
    union!(points, -1.0:2.5e-4:1.0)
    for anchor in (0.0, theta0), k in -200:200
        push!(points, clamp(anchor + k * 1.0e-4, -1.0, 1.0))
    end
    best_theta, best_payoff = NaN, -Inf
    for theta in sort!(collect(points))
        value = first(GN.equilibrium_payoff(theta, context...))
        if isfinite(value) && value > best_payoff
            best_theta, best_payoff = theta, value
        end
    end
    return best_theta, best_payoff
end

"""
    advance!(world, config, tick::Int, search::Symbol)

Drive the exact MDR-0010 model schedule, selecting only the transfer driver.
"""
function advance!(world, config, tick::Int, search::Symbol)
    GN.update_shocks!(world, tick)
    GN.calculate_norm_perception!(world, config.utility)
    GN.set_theta!(world, config.utility; search=search)
    GN.update_old_working_time_and_transfer!(world)
    GN.update_global_working_times!(world)
    GN.update_preferences(world)
    return nothing
end

"""
    payoff_deficit(reference::Float64, candidate::Float64)

Non-negative loss relative to a finite reference; return Inf for an
infeasible candidate and zero when the reference is infeasible.
"""
payoff_deficit(reference::Float64, candidate::Float64) =
    !isfinite(reference) ? 0.0 : (!isfinite(candidate) ? Inf : max(0.0, reference - candidate))

"""
    quality_rows()

Compare both solvers and a finer grid on 44 households at states tick
0/1/5 of each discovery trajectory (396 identical-state comparisons).
Also record the production cache count and actual search-solve records.
"""
function quality_rows()
    rows = NamedTuple[]
    indices = sort!(unique(vcat(collect(1:12:493), [100, 387])))
    for name in VALIDATION_WORKLOADS
        spec = validation_spec(name, 6)
        world = GN.create_world(spec)
        config = spec.model_config
        for state in 0:5
            if state in (0, 1, 5)
                for i in indices
                    args = household_args(world, i, config)
                    context = payoff_context(args)
                    scratch = GN.TransferSearchScratch()
                    local_bundle = GN.bargain_transfer(scratch, args...)
                    discovery_bundle = GN.bargain_transfer(args...; search=:discovery)
                    local_payoff = bundle_payoff(local_bundle, context)
                    discovery_payoff = bundle_payoff(discovery_bundle, context)
                    theta0 = clamp(args[3], -1.0, 1.0)
                    fine_theta, fine_payoff = fine_grid_best(theta0, context)
                    status_payoff = bundle_payoff((theta0, context[1], context[2]), context)
                    calls = length(scratch.cache)
                    search_solves = max(0, count(v -> isfinite(v.hw), values(scratch.cache)) - 1)
                    calls <= GN.TRANSFER_SEARCH_MAX_EVALS || error("production budget exceeded")
                    fallback = isequal(local_bundle, (theta0, context[1], context[2]))
                    fallback || (isfinite(local_payoff) && local_payoff > status_payoff) ||
                        error("invalid production commit")
                    push!(rows, (; workload=name, state, household=i, status_payoff,
                        local_theta=local_bundle[1], discovery_theta=discovery_bundle[1],
                        local_payoff, discovery_payoff, fine_theta, fine_payoff,
                        discovery_deficit=payoff_deficit(discovery_payoff, local_payoff),
                        fine_deficit=payoff_deficit(fine_payoff, local_payoff),
                        bitwise=isequal(local_bundle, discovery_bundle), calls, search_solves))
                end
            end
            state < 5 && advance!(world, config, state, :discovery)
        end
    end
    return rows
end

"""
    household_snapshot(world)

Return transfers and both spouses' committed hours in network household order.
"""
function household_snapshot(world)
    net = Ark.get_resource(world, GN.SocialNetwork)
    return map(net.women_entities) do woman
        time_w, transfer, spouse = Ark.get_components(
            world, woman, (GN.WorkingTime, GN.TransferToWoman, GN.Spouse))
        time_m, = Ark.get_components(world, spouse.entity, (GN.WorkingTime,))
        (transfer.current, time_w.current, time_m.current)
    end
end

"""
    snapshot_digest(snapshot)

Stable FNV-style digest over Float64 bit patterns, not Julia's session hash.
"""
function snapshot_digest(snapshot)
    digest = UInt64(0xcbf29ce484222325)
    for household in snapshot, value in household
        digest = xor(digest, reinterpret(UInt64, value)) * UInt64(0x100000001b3)
    end
    return string(digest; base=16, pad=16)
end

"""
    trajectory_rows()

Record aggregate and per-household trajectory deltas over 25 ticks for
each independently evolving local and discovery world, including stable
digests for repeat and cross-thread checks. Changed households are also
compared against discovery on their exact pre-tick LOCAL state, separating
search losses from trajectory divergence. Return aggregate and change rows.
"""
function trajectory_rows()
    rows = NamedTuple[]
    changes = NamedTuple[]
    for name in VALIDATION_WORKLOADS
        spec = validation_spec(name, 25)
        local_world = GN.create_world(spec)
        discovery_world = GN.create_world(spec)
        config = spec.model_config
        for tick in 0:24
            local_args = [household_args(local_world, i, config) for i in 1:500]
            advance!(local_world, config, tick, :local)
            advance!(discovery_world, config, tick, :discovery)
            local_state = household_snapshot(local_world)
            discovery_state = household_snapshot(discovery_world)
            lt, dt = first.(local_state), first.(discovery_state)
            delta = abs.(lt .- dt)
            push!(rows, (; workload=name, tick,
                local_sum=sum(lt), discovery_sum=sum(dt),
                local_nonzero=count(!iszero, lt) / length(lt),
                discovery_nonzero=count(!iszero, dt) / length(dt),
                differing=count(i -> !isequal(lt[i], dt[i]), eachindex(lt)),
                mean_abs_delta=mean(delta), max_abs_delta=maximum(delta),
                local_digest=snapshot_digest(local_state),
                discovery_digest=snapshot_digest(discovery_state)))
            for i in eachindex(lt)
                isequal(lt[i], dt[i]) && continue
                args = local_args[i]
                context = payoff_context(args)
                reference_bundle = GN.bargain_transfer(args...; search=:discovery)
                local_payoff = bundle_payoff(local_state[i], context)
                shared_reference_payoff = bundle_payoff(reference_bundle, context)
                push!(changes, (; workload=name, tick, household=i,
                    local_theta=lt[i], discovery_trajectory_theta=dt[i], abs_delta=delta[i],
                    shared_reference_theta=reference_bundle[1], local_payoff,
                    shared_reference_payoff,
                    shared_state_deficit=payoff_deficit(shared_reference_payoff, local_payoff),
                    bitwise_shared=isequal(local_state[i], reference_bundle)))
            end
        end
    end
    return (; rows, changes)
end

"""
    kernel_pass(spec, ticks::Int, search::Symbol)

Fresh-world, warmed-kernel measurement with the existing harness's phase
boundaries. Return summed set_theta! time and allocations over the ticks.
"""
function kernel_pass(spec, ticks::Int, search::Symbol)
    world = GN.create_world(spec)
    config = spec.model_config
    kernel_s = 0.0
    bytes = 0
    for tick in 0:(ticks - 1)
        GN.update_shocks!(world, tick)
        GN.calculate_norm_perception!(world, config.utility)
        gc_before = Base.gc_num()
        start = time_ns()
        GN.set_theta!(world, config.utility; search=search)
        kernel_s += (time_ns() - start) / 1.0e9
        bytes += Int(Base.GC_Diff(Base.gc_num(), gc_before).allocd)
        GN.update_old_working_time_and_transfer!(world)
        GN.update_global_working_times!(world)
        GN.update_preferences(world)
    end
    return (; kernel_s, bytes)
end

"""
    timing_rows()

Measure each solver sequentially on an idle machine: one full-size discarded
warmup and five fresh-world repetitions, 500 households over 20 ticks.
"""
function timing_rows()
    rows = NamedTuple[]
    for name in VALIDATION_WORKLOADS, search in (:local, :discovery)
        spec = validation_spec(name, 20)
        kernel_pass(spec, 20, search)
        passes = [kernel_pass(spec, 20, search) for _ in 1:5]
        times = [p.kernel_s for p in passes]
        push!(rows, (; workload=name, search=string(search), threads=Threads.nthreads(),
            ticks=20, repetitions=5, households=500, median_s=median(times),
            iqr_s=quantile(times, 0.75) - quantile(times, 0.25),
            min_s=minimum(times), max_s=maximum(times),
            bytes_per_household_tick=median([p.bytes for p in passes]) / 10000))
    end
    return rows
end

"""
    write_rows(path::String, rows)

Write the numeric, boolean, and fixed-label NamedTuple records as CSV.
"""
function write_rows(path::String, rows)
    open(path, "w") do io
        println(io, join(string.(keys(first(rows))), ','))
        for row in rows
            println(io, join(string.(values(row)), ','))
        end
    end
    println(path)
    return nothing
end

"""
    main(args)

Write reproducible validation tables to the requested directory. The
optional section isolates timings from expensive quality work; the default
is all. Output includes the environment and table paths.
"""
function main(args)
    output = length(args) >= 1 ? args[1] : joinpath("/tmp/opencode", "anchor-local-validation")
    section = length(args) >= 2 ? args[2] : "all"
    section in ("all", "quality", "trajectories", "timing") || error("unknown section $section")
    mkpath(output)
    println("Julia ", VERSION, ", threads ", Threads.nthreads(), ", CPU ", Sys.cpu_info()[1].model)
    if section in ("all", "quality")
        write_rows(joinpath(output, "anchor_quality.csv"), quality_rows())
    end
    if section in ("all", "trajectories")
        trajectories = trajectory_rows()
        write_rows(joinpath(output, "anchor_trajectories.csv"), trajectories.rows)
        write_rows(joinpath(output, "anchor_trajectory_changes.csv"), trajectories.changes)
    end
    if section in ("all", "timing")
        write_rows(joinpath(output, "anchor_timing.csv"), timing_rows())
    end
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
