# Offline discovery-contract tests for the tiered sample set and the
# evaluation-cache discipline of `MDR-0014` and `ADR-0019` (the
# sample-set semantics of `MDR-0012`/`MDR-0013` change intentionally;
# the bitwise identity oracle of `ADR-0017` is retired with that
# role). Asserted: the Stage A set is exactly the documented tiered
# enumeration and a strict subset of the frozen `MDR-0013` reference
# set (`test/reference_transfer_search.jl`, now the quality-comparison
# baseline), the per-region resolution of `MDR-0014` (1e-4 within the
# fine anchor windows, the 1e-3 coarse lattice elsewhere), the cache
# discipline of `ADR-0019` (slab-covered samples keep their exact
# `-Inf` payoff in the sampled sequence and stay out of the cache; only
# evaluated transfers are cached), the retained exactness of the
# interval prefilter (it removes no solve and changes no result on the
# same sample set), bitwise commit identity with the frozen reference
# on the fixture households (their bands sit in the fine window, where
# both searches sample and bracket identically), commit validity and
# repeat determinism on constructed boundary cases, and scratch reuse
# statelessness. The band-discovery guarantee of `MDR-0014` is encoded
# in `test/test_transfer_search.jl`; objective-level bitwise checks
# live in `test/test_bargaining_equivalence.jl` and
# `test/test_bargain_certificate.jl`.

using GenderNorms
using Test
using TOML

const GN = GenderNorms

# `test/reference_transfer_search.jl` is the frozen `MDR-0013` staged
# search (the reference of the `MDR-0014` comparison); the guard keeps
# this file runnable on its own.
if !isdefined(@__MODULE__, :bargain_transfer_search_reference)
    include("reference_transfer_search.jl")
end

"""
    reduction_t64(text::AbstractString)::Float64

Read one fixture float of `test/fixtures/transfer_feasibility_households.toml`
(the fixture encodes every `Float64` as a quoted Julia `repr` string).
"""
reduction_t64(text::AbstractString)::Float64 = parse(Float64, text)

"""
    reduction_stage_a(theta0::Float64)

The documented tiered Stage A evaluation set of `GN._transfer_search!`
for a status quo `theta0`, recomputed independently in the test: the
anchors, the fine anchor windows at `GN.TRANSFER_FINE_STEP`, and the
coarse grid at `GN.TRANSFER_COARSE_STEP`, minus the seeded `theta0`.
Returns the ordered sequence (the driver's order is a permutation of
this only through the cache-deduplicated enumeration; the tests
compare sets and per-region membership).
"""
function reduction_stage_a(theta0::Float64)::Vector{Float64}
    raw = Float64[-1.0, 0.0, theta0, 1.0]
    for anchor in (0.0, theta0)
        for k in 1:GN.TRANSFER_FINE_STEPS
            push!(raw, clamp(anchor + k * GN.TRANSFER_FINE_STEP, -1.0, 1.0))
            push!(raw, clamp(anchor - k * GN.TRANSFER_FINE_STEP, -1.0, 1.0))
        end
    end
    append!(raw, -1.0:GN.TRANSFER_COARSE_STEP:1.0)
    expected = Float64[]
    seen = Set{Float64}([theta0])
    for theta in raw
        theta in seen && continue
        push!(seen, theta)
        push!(expected, theta)
    end
    return expected
end

"""
    reduction_reference_stage_a(theta0::Float64)

The frozen `MDR-0013` reference Stage A set for a status quo `theta0`
(the local value copies of `test/reference_transfer_search.jl`),
recomputed independently: anchors, the `+/- 0.02` anchor
neighbourhoods at 1e-4, and the coarse grid. Used for the subset
claim of `MDR-0014`.
"""
function reduction_reference_stage_a(theta0::Float64)::Vector{Float64}
    raw = Float64[-1.0, 0.0, theta0, 1.0]
    for anchor in (0.0, theta0)
        for k in 1:200
            push!(raw, clamp(anchor + k * 1.0e-4, -1.0, 1.0))
            push!(raw, clamp(anchor - k * 1.0e-4, -1.0, 1.0))
        end
    end
    append!(raw, -1.0:1.0e-3:1.0)
    expected = Float64[]
    seen = Set{Float64}([theta0])
    for theta in raw
        theta in seen && continue
        push!(seen, theta)
        push!(expected, theta)
    end
    return expected
end

# Evaluation counters of one instrumented search run (the exact
# `evaluate_transfer` body of `bargain_transfer`, see `MDR-0014`).
mutable struct ReductionCounters
    pointwise_certs::Int
    interval_certs::Int
    solves::Int
end

"""
    reduction_evaluator(requests, counters, uw_out, um_out, hw_status, hm_status, pw, pm, config)

Recorded transfer objective for the contract runs: records every
requested transfer in `requests` and counts pointwise certificate
decisions and solves in `counters`. The body is the exact
`evaluate_transfer` objective of `bargain_transfer`.
"""
function reduction_evaluator(
    requests::Vector{Float64}, counters::ReductionCounters,
    uw_out::Float64, um_out::Float64, hw_status::Float64, hm_status::Float64,
    pw::GN.AgentPayoffParams, pm::GN.AgentPayoffParams, config,
)
    return function (theta::Float64)
        push!(requests, theta)
        if GN._objective_prunable(theta, uw_out, um_out, pw, pm, config)
            counters.pointwise_certs += 1
            return GN.TransferObjectiveValue(NaN, NaN, -Inf, NaN, NaN)
        end
        payoff, hw, hm =
            GN.equilibrium_payoff(theta, hw_status, hm_status, uw_out, um_out, pw, pm, config)
        counters.solves += 1
        gain_w = GN.individual_utility(hw, hm, theta, pw, config) - uw_out
        gain_m = GN.individual_utility(hm, hw, theta, pm, config) - um_out
        return GN.TransferObjectiveValue(gain_w, gain_m, payoff, hw, hm)
    end
end

"""
    reduction_run(case; with_slabs::Bool)

One instrumented `GN._transfer_search!` run on a household case
`(hw_init, hm_init, theta_init, pw, pm, config)`: seeds the cache at
`theta0` exactly as `bargain_transfer` does and drives the search with
or without the interval prefilter. Returns the NamedTuple `(best,
cache, samples, requests, counters, theta0, status_payoff)`.
"""
function reduction_run(case::NamedTuple; with_slabs::Bool)
    (; hw_init, hm_init, theta_init, pw, pm, config) = case
    theta0 = clamp(theta_init, -1.0, 1.0)
    hw_out, hm_out = GN.mutual_best_response(hw_init, hm_init, 0.0, pw, pm, config)
    uw_out = GN.individual_utility(hw_out, hm_out, 0.0, pw, config)
    um_out = GN.individual_utility(hm_out, hw_out, 0.0, pm, config)
    hw_status, hm_status = theta0 === 0.0 ? (hw_out, hm_out) :
        GN.mutual_best_response(hw_init, hm_init, theta0, pw, pm, config)
    status_payoff = GN.nash_product(theta0, hw_status, hm_status, uw_out, um_out, pw, pm, config)
    gain_w0 = GN.individual_utility(hw_status, hm_status, theta0, pw, config) - uw_out
    gain_m0 = GN.individual_utility(hm_status, hw_status, theta0, pm, config) - um_out
    seed = GN.TransferObjectiveValue(gain_w0, gain_m0, status_payoff, hw_status, hm_status)
    scratch = GN.TransferSearchScratch()
    scratch.cache[theta0] = seed
    requests = Float64[]
    counters = ReductionCounters(0, 0, 0)
    evaluator = reduction_evaluator(
        requests, counters, uw_out, um_out, hw_status, hm_status, pw, pm, config
    )
    slab_prunable = nothing
    if with_slabs
        slab_prunable = (lo::Float64, hi::Float64) -> begin
            counters.interval_certs += 1
            GN._objective_interval_prunable(lo, hi, uw_out, um_out, pw, pm, config)
        end
    end
    best = GN._transfer_search!(scratch, slab_prunable, evaluator, theta0, GN.TRANSFER_REFINE_TOL)
    return (
        best=best,
        cache=scratch.cache,
        samples=copy(scratch.samples),
        requests=requests,
        counters=counters,
        theta0=theta0,
        status_payoff=status_payoff,
    )
end

@testset "transfer search reduction: tiered sample set and subset" begin
    # The Stage A set is exactly the documented tiered enumeration, a
    # strict subset of the frozen `MDR-0013` reference set, and every
    # sampled transfer is an anchor, a fine-window lattice point, or a
    # coarse lattice point (the per-region resolution of `MDR-0014`).
    # A wholly infeasible manufactured objective keeps the run to its
    # Stage A samples.
    for theta0 in (0.0, -0.0, 0.3, -1.0, 1.0, 0.123456789)
        stage_a = reduction_stage_a(theta0)
        reference = reduction_reference_stage_a(theta0)
        cache = Dict{Float64,GN.TransferObjectiveValue}()
        cache[theta0] = GN.TransferObjectiveValue(NaN, NaN, -Inf, NaN, NaN)
        scratch = GN.TransferSearchScratch(cache)
        best = GN._transfer_search!(
            scratch,
            nothing,
            theta -> GN.TransferObjectiveValue(NaN, NaN, -Inf, NaN, NaN),
            theta0,
            GN.TRANSFER_REFINE_TOL,
        )
        @test isnan(best)
        sampled = sort(collect(Set(first(s) for s in scratch.samples)))
        @test isequal(sampled, sort(collect(Set(vcat(stage_a, [theta0])))))
        @test Set(stage_a) ⊆ Set(reference)
        @test Set(stage_a) != Set(reference)  # the reduction is real
        for theta in sampled
            isequal(theta, theta0) && continue
            on_coarse = any(isequal(theta), -1.0:GN.TRANSFER_COARSE_STEP:1.0)
            on_fine = false
            for anchor in (0.0, theta0), k in 1:GN.TRANSFER_FINE_STEPS
                if isequal(theta, clamp(anchor + k * GN.TRANSFER_FINE_STEP, -1.0, 1.0)) ||
                        isequal(theta, clamp(anchor - k * GN.TRANSFER_FINE_STEP, -1.0, 1.0))
                    on_fine = true
                end
            end
            @test on_coarse || on_fine
        end
    end
end

@testset "transfer search reduction: cache discipline and prefilter exactness" begin
    # Constructed boundary cases (the `ADR-0017` case families) run
    # with and without the interval prefilter on the same sample set:
    # the prefilter removes no solve and changes no sampled payoff or
    # commit, slab-covered samples keep their exact `-Inf` payoff in
    # the sampled sequence and stay out of the cache, and only
    # evaluated transfers are cached (every cache key was requested
    # exactly once, plus the seeded status quo).
    cases = NamedTuple[]
    function add_case(config, wage_self, wage_spouse, alpha, conformism, n_theta, theta_init)
        pw = GN.AgentPayoffParams(
            wage_self=wage_self, wage_spouse=wage_spouse, alpha=alpha, conformism=conformism,
            N_h=0.5, N_theta=n_theta, N_h_spouse=0.5, is_woman=true,
        )
        pm = GN.AgentPayoffParams(
            wage_self=wage_spouse, wage_spouse=wage_self, alpha=alpha, conformism=conformism,
            N_h=0.5, N_theta=n_theta, N_h_spouse=0.5, is_woman=false,
        )
        push!(cases, (hw_init=0.5, hm_init=0.4, theta_init=theta_init, pw=pw, pm=pm, config=config))
    end
    for beta in (1.0e-12, 1.0e-3, 0.5, 1.5), alpha in (0.0, 1.0),
        theta_init in (0.0, -0.0, 0.123456789)
        add_case(
            GN.UtilityConfig(func=GN.CES(beta=beta)), 1.0, 40.0, alpha, 50.0, 0.25, theta_init
        )
    end
    for (w_self, w_spouse) in ((0.0, 0.0), (1.0e-8, 1.0), (40.0, 1.0), (1.0, 40.0)),
        theta_init in (0.0, 0.3)
        add_case(GN.UtilityConfig(func=GN.CES(beta=0.5)), w_self, w_spouse, 0.5, 10.0, 0.0, theta_init)
    end
    for conformism in (0.0, 50.0, 1.0e4), n_theta in (-0.7, 0.25), theta_init in (0.123456789,)
        add_case(GN.UtilityConfig(func=GN.CES(beta=0.5)), 1.0, 1.5, 0.5, conformism, n_theta, theta_init)
    end
    excluded_total = 0
    interval_total = 0
    pointwise_total = 0
    for (i, case) in enumerate(cases)
        on = reduction_run(case; with_slabs=true)
        off = reduction_run(case; with_slabs=false)
        interval_total += on.counters.interval_certs
        pointwise_total += on.counters.pointwise_certs
        # Same sample set, same sampled payoffs, and same commit with
        # and without the prefilter (the interval certificate removes
        # no solve and changes no cached value: pointwise parity,
        # `ADR-0017`; the prefiltered run only skips `evaluate!` calls
        # the pointwise certificate would prune to the same `-Inf`).
        @test isequal(on.best, off.best)
        @test isequal(first.(on.samples), first.(off.samples))
        @test isequal(last.(on.samples), last.(off.samples))
        @test on.counters.solves == off.counters.solves
        # Cache discipline (`ADR-0019`): exactly the requested
        # transfers plus the seeded status quo are cached.
        @test Set(keys(on.cache)) == Set(on.requests) ∪ Set([on.theta0])
        # Sampled sequence: strictly sorted, `isequal`-distinct
        # transfers, every finite payoff cached with the same value.
        thetas = first.(on.samples)
        @test issorted(thetas; lt=isless)
        @test all(i -> !isequal(thetas[i], thetas[i + 1]), 1:(length(thetas) - 1))
        for (theta, payoff) in on.samples
            if isfinite(payoff)
                @test haskey(on.cache, theta) && isequal(on.cache[theta].payoff, payoff)
            end
        end
        # A sampled transfer absent from the cache was covered by the
        # prefilter and never evaluated: its payoff is the exact `-Inf`
        # sentinel and it was not requested.
        excluded = 0
        for (theta, payoff) in on.samples
            if !haskey(on.cache, theta)
                @test isequal(payoff, -Inf)
                @test !(theta in on.requests)
                excluded += 1
            end
        end
        excluded_total += excluded
    end
    # Non-vacuity: the prefilter must actually exclude objective calls
    # somewhere in these cases, and both certificate paths must run.
    @test excluded_total > 0
    @test interval_total > 0
    @test pointwise_total > 0
end

@testset "transfer search reduction: fixture households match the reference" begin
    # The three regression fixture households (benchmark households
    # 85, 100, 387) have their feasible bands inside the fine anchor
    # windows, where the tiered set and the frozen `MDR-0013` set
    # sample and bracket identically, so the committed `(theta, hw,
    # hm)` must match the reference bitwise.
    fixture = TOML.parsefile(
        joinpath(@__DIR__, "fixtures", "transfer_feasibility_households.toml")
    )
    @test length(fixture["household"]) == 3
    for h in fixture["household"]
        config = GN.UtilityConfig(func=GN.CES(beta=reduction_t64(h["beta"])))
        pw = GN.AgentPayoffParams(
            wage_self=reduction_t64(h["pw_wage_self"]),
            wage_spouse=reduction_t64(h["pw_wage_spouse"]),
            alpha=reduction_t64(h["pw_alpha"]),
            conformism=reduction_t64(h["pw_conformism"]),
            N_h=reduction_t64(h["pw_N_h"]),
            N_theta=reduction_t64(h["pw_N_theta"]),
            N_h_spouse=reduction_t64(h["pw_N_h_spouse"]),
            is_woman=true,
        )
        pm = GN.AgentPayoffParams(
            wage_self=reduction_t64(h["pm_wage_self"]),
            wage_spouse=reduction_t64(h["pm_wage_spouse"]),
            alpha=reduction_t64(h["pm_alpha"]),
            conformism=reduction_t64(h["pm_conformism"]),
            N_h=reduction_t64(h["pm_N_h"]),
            N_theta=reduction_t64(h["pm_N_theta"]),
            N_h_spouse=reduction_t64(h["pm_N_h_spouse"]),
            is_woman=false,
        )
        hw_init, hm_init, theta_init =
            reduction_t64(h["hw_init"]), reduction_t64(h["hm_init"]), reduction_t64(h["theta_init"])
        live = GN.bargain_transfer(hw_init, hm_init, theta_init, pw, pm, config; search=:discovery)
        reference = bargain_transfer_search_reference(hw_init, hm_init, theta_init, pw, pm, config)
        @test isequal(live[1], reference[1])
        @test isequal(live[2], reference[2])
        @test isequal(live[3], reference[3])
    end
end

@testset "transfer search reduction: jagged-peak cases match the reference" begin
    # Solver fixture cases 171 and 182 are the known jagged-peak
    # counterexamples of the old unseeded-Brent baseline (it committed
    # a higher payoff than the frozen `MDR-0013` reference staged
    # search there; see `MDR-0014` and
    # `benchmark/search_reduction_validation.md` section 3): the tiered
    # search must match the reference commit bitwise on both, so a
    # future sampling/bracket change cannot regress either case
    # silently. Same machinery as the fixture-household block above,
    # driven on the identical 200-case solver fixture inputs of
    # `test/fixtures/bargaining_baseline.toml`.
    baseline = TOML.parsefile(
        joinpath(@__DIR__, "fixtures", "bargaining_baseline.toml")
    )
    solver_cases = baseline["solver"]["case"]
    @test length(solver_cases) == 200
    for id in (171, 182)
        case = only(filter(c -> c["id"] == id, solver_cases))
        utility = case["utility"]
        beta = reduction_t64(get(case, "beta", "0.5"))
        config = if utility == "additive"
            GN.UtilityConfig(func=GN.Additive())
        elseif utility == "ces"
            GN.UtilityConfig(func=GN.CES(beta=beta))
        elseif utility == "multiplicative"
            GN.UtilityConfig(func=GN.Multiplicative())
        elseif utility == "multiplicative_weighted"
            GN.UtilityConfig(func=GN.MultiplicativeWeighted())
        else
            error("unknown utility spec $(repr(utility))")
        end
        pw = GN.AgentPayoffParams(
            wage_self=reduction_t64(case["pw_wage_self"]),
            wage_spouse=reduction_t64(case["pw_wage_spouse"]),
            alpha=reduction_t64(case["pw_alpha"]),
            conformism=reduction_t64(case["pw_conformism"]),
            N_h=reduction_t64(case["pw_N_h"]),
            N_theta=reduction_t64(case["pw_N_theta"]),
            N_h_spouse=reduction_t64(case["pw_N_h_spouse"]),
            is_woman=true,
        )
        pm = GN.AgentPayoffParams(
            wage_self=reduction_t64(case["pm_wage_self"]),
            wage_spouse=reduction_t64(case["pm_wage_spouse"]),
            alpha=reduction_t64(case["pm_alpha"]),
            conformism=reduction_t64(case["pm_conformism"]),
            N_h=reduction_t64(case["pm_N_h"]),
            N_theta=reduction_t64(case["pm_N_theta"]),
            N_h_spouse=reduction_t64(case["pm_N_h_spouse"]),
            is_woman=false,
        )
        hw_init, hm_init, theta_init = reduction_t64(case["hw_init"]),
            reduction_t64(case["hm_init"]), reduction_t64(case["theta_init"])
        live = GN.bargain_transfer(hw_init, hm_init, theta_init, pw, pm, config; search=:discovery)
        reference = bargain_transfer_search_reference(hw_init, hm_init, theta_init, pw, pm, config)
        @test isequal(live[1], reference[1])
        @test isequal(live[2], reference[2])
        @test isequal(live[3], reference[3])
        uw_out, um_out = GN.outside_options(hw_init, hm_init, pw, pm, config)
        live_payoff = GN.nash_product(live[1], live[2], live[3], uw_out, um_out, pw, pm, config)
        reference_payoff = GN.nash_product(
            reference[1], reference[2], reference[3], uw_out, um_out, pw, pm, config
        )
        @test isequal(live_payoff, reference_payoff)
    end
end

@testset "transfer search reduction: scratch reuse is stateless" begin
    # One `TransferSearchScratch` reused across households and calls
    # must never leak state: the same household bargained on a shared
    # scratch, on a fresh scratch, and through the standalone entry
    # point commits bitwise-identical results.
    config = GN.UtilityConfig(func=GN.CES(beta=0.5))
    pw = GN.AgentPayoffParams(
        wage_self=1.0, wage_spouse=1.5, alpha=0.5, conformism=10.0,
        N_h=0.5, N_theta=0.25, N_h_spouse=0.5, is_woman=true,
    )
    pm = GN.AgentPayoffParams(
        wage_self=1.5, wage_spouse=1.0, alpha=0.5, conformism=10.0,
        N_h=0.5, N_theta=-0.5, N_h_spouse=0.5, is_woman=false,
    )
    scratch = GN.TransferSearchScratch()
    results = Tuple{Float64,Float64,Float64}[]
    for (hw_init, hm_init, theta_init) in (
        (0.5, 0.5, 0.0), (0.3, 0.7, 0.123456789), (0.0, 1.0, -0.0), (0.5, 0.5, 0.25),
    )
        push!(results, GN.bargain_transfer(scratch, hw_init, hm_init, theta_init, pw, pm, config))
        push!(results, GN.bargain_transfer(scratch, hw_init, hm_init, theta_init, pw, pm, config))
        push!(results, GN.bargain_transfer(hw_init, hm_init, theta_init, pw, pm, config))
    end
    for i in 1:3:length(results)
        @test isequal(results[i], results[i + 1])
        @test isequal(results[i], results[i + 2])
    end
end

# Fill one `TransferSearchScratch` back to the sample and cache sizes of
# a previous (grown) search; the buffer growth of `push!` and `setindex!`
# is what `scratch_refill_allocs!` measures.
function scratch_refill!(scratch::GN.TransferSearchScratch, nsamples::Int, ncache::Int)
    for i in 1:nsamples
        push!(scratch.samples, (Float64(i), 0.0))
    end
    for i in 1:ncache
        scratch.cache[Float64(i)] = GN.TransferObjectiveValue(0.0, 0.0, 0.0, 0.0, 0.0)
    end
    return nothing
end

scratch_refill_allocs!(scratch::GN.TransferSearchScratch, nsamples::Int, ncache::Int)::Int =
    @allocated scratch_refill!(scratch, nsamples, ncache)

@testset "transfer search reduction: scratch growth keeps reusable capacity" begin
    # A `:discovery` search grows `samples` (the full `_transfer_sample!`
    # enumeration) and `cache` far beyond the fresh-scratch capacity
    # hints; `_reset_scratch!` must keep the grown buffers reusable:
    # refilling the previously reached sizes after a reset allocates
    # nothing (no vector growth and no dict rehash), and further
    # households on the grown scratch commit bitwise-identical results
    # to fresh-scratch runs (TASK-0025 item 9).
    config = GN.UtilityConfig(func=GN.CES(beta=0.5))
    pw = GN.AgentPayoffParams(
        wage_self=1.0, wage_spouse=1.5, alpha=0.5, conformism=10.0,
        N_h=0.5, N_theta=0.25, N_h_spouse=0.5, is_woman=true,
    )
    pm = GN.AgentPayoffParams(
        wage_self=1.5, wage_spouse=1.0, alpha=0.5, conformism=10.0,
        N_h=0.5, N_theta=-0.5, N_h_spouse=0.5, is_woman=false,
    )
    scratch = GN.TransferSearchScratch()
    GN.bargain_transfer(scratch, 0.5, 0.5, 0.123456789, pw, pm, config; search=:discovery)
    grown_samples = length(scratch.samples)
    grown_cache = length(scratch.cache)
    @test grown_samples > GN.TRANSFER_SAMPLE_CAPACITY
    @test grown_cache > GN.TRANSFER_CACHE_CAPACITY
    GN._reset_scratch!(scratch)
    @test isempty(scratch.samples)
    @test isempty(scratch.cache)
    # Compile the probe before measuring it.
    scratch_refill_allocs!(scratch, 2, 1)
    GN._reset_scratch!(scratch)
    @test scratch_refill_allocs!(scratch, grown_samples, grown_cache) == 0
    # A second full reset cycle keeps the grown capacity reusable.
    GN._reset_scratch!(scratch)
    @test scratch_refill_allocs!(scratch, grown_samples, grown_cache) == 0
    GN._reset_scratch!(scratch)
    for (hw_init, hm_init, theta_init) in (
        (0.3, 0.7, 0.123456789), (0.0, 1.0, -0.0), (0.5, 0.5, 0.25),
    )
        shared = GN.bargain_transfer(
            scratch, hw_init, hm_init, theta_init, pw, pm, config; search=:discovery
        )
        shared_again = GN.bargain_transfer(
            scratch, hw_init, hm_init, theta_init, pw, pm, config; search=:discovery
        )
        fresh = GN.bargain_transfer(hw_init, hm_init, theta_init, pw, pm, config; search=:discovery)
        @test isequal(shared, fresh)
        @test isequal(shared_again, fresh)
    end
end
