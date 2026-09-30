# Production search contract of `MDR-0016` / `ADR-0021` (NetLogo
# `set-theta`, ODD section Transfer bargaining): the sparse adaptive
# feasibility-guided schedule with seeded Brent refinements. The
# discovery-contract tests remain separate; remote-band misses are
# asserted, not hidden.
#
# Schedule-independence note: the `LOCAL_*` constants below are the
# test's own literal copy of the production schedule (offsets, overlap,
# guidance floor, adaptive offset, refinement budgets). They are
# asserted equal to the production `GN.TRANSFER_*` constants in the
# schedule-constants testset, and the independent `local_stage_a` /
# `local_bracket` enumeration built from them (never through the
# driver's own enumeration helpers) is what the requested-probe
# assertions compare against.

using Ark
using GenderNorms
using Test
using TOML

const GN = GenderNorms

# Independent literal copy of the production schedule of `MDR-0016`
# (see the schedule-constants testset for the equality check against
# the `GN.TRANSFER_*` constants): the test enumeration uses these
# literals, never the driver's implementation code paths.
const LOCAL_EXPLORE_OFFSETS = (0.0001, 0.001, 0.003, 0.03, 0.1, 0.3)
const LOCAL_ANCHOR_OVERLAP = 0.002
const LOCAL_GUIDANCE_MIN = -2.0e-5
const LOCAL_ADAPTIVE_OFFSET = 0.0003
const LOCAL_GUIDANCE_REFINEMENTS = 1
const LOCAL_MAX_REFINEMENTS = 1
const LOCAL_REFINE_MAX_ITER = 6

"""
    local_record(payoff::Float64; gw::Float64=NaN, gm::Float64=NaN)

Manufactured `TransferObjectiveValue` of the synthetic contract searches:
solved gains and hours stay `NaN` (only `payoff` and the guidance gains are
read), and the guidance gains default to `NaN` (worst). A pruned production
record would carry certified bound gains as `gw`/`gm`; a solved one carries
its true gains (equal to its payoff in the manufactured cases).
"""
local_record(payoff::Float64; gw::Float64=NaN, gm::Float64=NaN) =
    GN.TransferObjectiveValue(NaN, NaN, payoff, NaN, NaN, gw, gm)

"""
    local_guidance(record_of, theta::Float64)

Independent evaluation of the driver's guidance value of `record_of(theta)`
at the default normalization scales 1.0: `min(guidance_w, guidance_m)`,
non-finite values worst.
"""
function local_guidance(record_of, theta::Float64)
    entry = record_of(theta)
    value = min(entry.guidance_w, entry.guidance_m)
    return isfinite(value) ? value : -Inf
end

"""
    local_stage_a(theta0::Float64, record_of)

Independently enumerate the production sample order from the
test-owned `LOCAL_*` literal parameters (never through the driver's
own enumeration helpers and never reading the `GN.TRANSFER_*`
implementation constants): the anchors `-1.0`, `0.0`, `theta0`, `1.0`;
the `LOCAL_EXPLORE_OFFSETS` ladder on both signs of one anchor
(`0.0`) when `abs(theta0) <= LOCAL_ANCHOR_OVERLAP`, otherwise of both
anchors; then the adaptive `LOCAL_ADAPTIVE_OFFSET` probes on exactly
those sides where guidance at `+/- 0.001` is `>= LOCAL_GUIDANCE_MIN`
and strictly exceeds guidance at `+/- 0.0001`. Exact duplicates and
the seeded status quo are removed (first occurrence kept).
"""
function local_stage_a(theta0::Float64, record_of)
    raw = Float64[-1.0, 0.0, theta0, 1.0]
    anchors = abs(theta0) <= LOCAL_ANCHOR_OVERLAP ? (0.0,) : (0.0, theta0)
    for anchor in anchors, offset in LOCAL_EXPLORE_OFFSETS
        push!(raw, clamp(anchor + offset, -1.0, 1.0))
        push!(raw, clamp(anchor - offset, -1.0, 1.0))
    end
    for anchor in anchors, sign in (1.0, -1.0)
        outer = clamp(anchor + sign * 0.001, -1.0, 1.0)
        inner = clamp(anchor + sign * 0.0001, -1.0, 1.0)
        gouter = local_guidance(record_of, outer)
        if gouter >= LOCAL_GUIDANCE_MIN && gouter > local_guidance(record_of, inner)
            push!(raw, clamp(anchor + sign * LOCAL_ADAPTIVE_OFFSET, -1.0, 1.0))
        end
    end
    seen = Set{Float64}([theta0])
    result = Float64[]
    for theta in raw
        theta in seen && continue
        push!(seen, theta)
        push!(result, theta)
    end
    return result
end

"""
    local_synthetic(theta0::Float64, record_of; tol::Float64=GN.TRANSFER_REFINE_TOL)

Record a manufactured production search with only the status quo seeded
(with the record `record_of(theta0)`, guidance included). Returns its
scratch, best transfer, ordered evaluator calls (new evaluations only), and
the independently enumerated Stage A set.
"""
function local_synthetic(theta0::Float64, record_of; tol::Float64=GN.TRANSFER_REFINE_TOL)
    scratch = GN.TransferSearchScratch()
    scratch.cache[theta0] = record_of(theta0)
    requested = Float64[]
    evaluator = theta -> begin
        push!(requested, theta)
        record_of(theta)
    end
    best = GN._transfer_local_search!(scratch, evaluator, theta0, tol)
    return (; scratch, best, requested, stage_a=local_stage_a(theta0, record_of))
end

"""
    local_bracket(sampled, representative)

Independently reconstruct a production refinement's sampled-neighbour
bracket, one-sided at the ends of the sampled sequence.
"""
function local_bracket(sampled, representative)
    j = findfirst(isequal(representative), sampled)
    return (sampled[max(1, j - 1)], sampled[min(length(sampled), j + 1)])
end

@testset "local transfer search: schedule constants and record budget" begin
    # The sparse adaptive schedule of `MDR-0016`: six exploration offsets
    # on both signs of one or two anchors, conditional adaptive probes,
    # and one refinement per stage with six iteration probes each.
    @test GN.TRANSFER_EXPLORE_OFFSETS == (0.0001, 0.001, 0.003, 0.03, 0.1, 0.3)
    @test GN.TRANSFER_ANCHOR_OVERLAP == 0.002
    @test GN.TRANSFER_GUIDANCE_MIN == -2.0e-5
    @test GN.TRANSFER_ADAPTIVE_OFFSET == 0.0003
    @test GN.TRANSFER_GUIDANCE_REFINEMENTS == 1
    @test GN.TRANSFER_MAX_REFINEMENTS == 1
    @test GN.TRANSFER_REFINE_MAX_ITER == 6
    # The test-owned literal schedule matches the production constants,
    # so the independent `local_stage_a` enumeration (built from the
    # `LOCAL_*` literals, never through the driver's helpers) pins the
    # same schedule the driver implements.
    @test LOCAL_EXPLORE_OFFSETS == GN.TRANSFER_EXPLORE_OFFSETS
    @test LOCAL_ANCHOR_OVERLAP == GN.TRANSFER_ANCHOR_OVERLAP
    @test LOCAL_GUIDANCE_MIN == GN.TRANSFER_GUIDANCE_MIN
    @test LOCAL_ADAPTIVE_OFFSET == GN.TRANSFER_ADAPTIVE_OFFSET
    @test LOCAL_GUIDANCE_REFINEMENTS == GN.TRANSFER_GUIDANCE_REFINEMENTS
    @test LOCAL_MAX_REFINEMENTS == GN.TRANSFER_MAX_REFINEMENTS
    @test LOCAL_REFINE_MAX_ITER == GN.TRANSFER_REFINE_MAX_ITER
    # Worst-case record count: the seeded status quo, three more anchors,
    # the ladder of both signs around both anchors, the adaptive probes of
    # both signs around both anchors, and the iteration probes of both
    # refinements (their seeds are cached Stage A points).
    @test GN.TRANSFER_SEARCH_MAX_EVALS == 4 +
        4 * length(GN.TRANSFER_EXPLORE_OFFSETS) + 4 +
        (GN.TRANSFER_GUIDANCE_REFINEMENTS + GN.TRANSFER_MAX_REFINEMENTS) *
        GN.TRANSFER_REFINE_MAX_ITER
    @test GN.TRANSFER_SEARCH_MAX_EVALS == 44
end

@testset "local transfer search: exact sampling, deduplication, and no grid" begin
    infeasible = theta -> local_record(-Inf)
    for theta0 in (0.0, -0.0, -1.0, 1.0, 0.3, 0.123456789)
        run = local_synthetic(theta0, infeasible)
        @test isequal(run.requested, run.stage_a)
        @test length(run.requested) == length(Set(run.requested))
        @test length(run.requested) + 1 <= 32
        @test Set(keys(run.scratch.cache)) == Set(vcat(run.stage_a, [theta0]))
        @test isnan(run.best)
        @test isempty(run.scratch.slabs)
        @test issorted(run.scratch.samples)
        @test length(run.scratch.samples) == length(run.scratch.cache)
        @test all(theta -> -1.0 <= theta <= 1.0, run.requested)
        # A discovery-grid transfer away from the anchors is not sampled.
        @test !(0.037 in keys(run.scratch.cache))
    end
    # The signed zero keeps its own status-quo record and 0.0 is sampled
    # as a distinct anchor (Dict `isequal` semantics).
    signed = local_synthetic(-0.0, infeasible)
    @test haskey(signed.scratch.cache, -0.0)
    @test haskey(signed.scratch.cache, 0.0)
    # One shared ladder when the anchors overlap, two ladders otherwise.
    # The ladder points are checked against the test-owned `LOCAL_*`
    # literals, not the driver's constants, so a driver-side offset
    # change moves only one side of the comparison and fails.
    close = local_synthetic(0.0015, infeasible)
    @test count(t -> abs(t) in LOCAL_EXPLORE_OFFSETS, close.requested) ==
        2 * length(LOCAL_EXPLORE_OFFSETS)
    apart = local_synthetic(0.3, infeasible)
    @test length(apart.requested) > length(close.requested)
end

@testset "local transfer search: adaptive probes fire on qualifying sides only" begin
    # The adaptive +/- TRANSFER_ADAPTIVE_OFFSET probe is sampled only on
    # sides where guidance at +/- 0.001 is above the guidance floor and
    # strictly exceeds guidance at +/- 0.0001 (the household-100 rescue
    # rule of `MDR-0016`).
    signal = theta -> begin
        if isequal(theta, 0.001)
            local_record(-Inf; gw=-1.0e-5, gm=-1.0e-5)
        elseif isequal(theta, -0.001)
            local_record(-Inf; gw=-1.0e-5, gm=-1.0e-5)
        elseif isequal(theta, 0.0001) || isequal(theta, -0.0001)
            local_record(-Inf; gw=-1.0e-5, gm=-3.0e-5)
        else
            local_record(-Inf)
        end
    end
    run = local_synthetic(0.0, signal)
    @test 0.0003 in run.stage_a
    @test -0.0003 in run.stage_a
    # Stage A is requested exactly and in order, before any refinement.
    @test isequal(run.requested[1:length(run.stage_a)], run.stage_a)
    # Below the floor or not improving over the near probe: no adaptive probe.
    weak = theta -> begin
        if isequal(theta, 0.001)
            local_record(-Inf; gw=-3.0e-5, gm=-3.0e-5)
        else
            local_record(-Inf)
        end
    end
    run = local_synthetic(0.0, weak)
    @test !(0.0003 in run.stage_a)
    @test !(-0.0003 in run.stage_a)
    @test isequal(run.requested, run.stage_a)
    # Not improving over the +/- 0.0001 probe: no adaptive probe either.
    flat = theta -> begin
        if abs(theta) == 0.001 || abs(theta) == 0.0001
            local_record(-Inf; gw=1.0, gm=1.0)
        else
            local_record(-Inf)
        end
    end
    run = local_synthetic(0.0, flat)
    @test !(0.0003 in run.stage_a)
    @test !(-0.0003 in run.stage_a)
end

@testset "local transfer search: one ranked guidance refinement per run" begin
    # Guidance-only peaks (the bound-gain signal of certified probes):
    # exactly one peak is refined, the highest-guidance representative,
    # with at most TRANSFER_REFINE_MAX_ITER new probes inside its
    # sampled-neighbour bracket. Nothing is feasible, so Stage C never
    # runs and no fabricated value appears.
    peaks = Dict{Float64,Float64}(
        -0.0001 => 8.0, 0.0001 => 8.0,
        -0.001 => 7.0, 0.001 => 7.0,
        -0.003 => 6.0, 0.003 => 5.0,
    )
    record_of = theta -> haskey(peaks, theta) ?
        local_record(-Inf; gw=peaks[theta], gm=peaks[theta]) : local_record(-Inf)
    run = local_synthetic(0.0, record_of)
    sampled = sort(vcat(run.stage_a, [0.0]))
    probes = run.requested[(length(run.stage_a) + 1):end]
    @test !isempty(probes)
    @test length(probes) <= GN.TRANSFER_REFINE_MAX_ITER
    # Ties in guidance break toward the smallest abs(theta - theta0), then
    # the smallest theta: -0.0001 is the refined peak.
    lo, hi = local_bracket(sampled, -0.0001)
    @test all(t -> lo <= t <= hi, probes)
    @test length(run.scratch.cache) <= GN.TRANSFER_SEARCH_MAX_EVALS
    @test isnan(run.best)
    # Every cached record is exactly the evaluator's value, and unrefined
    # peaks stay cached candidates: budget exhaustion fabricates nothing.
    @test all(t -> isequal(run.scratch.cache[t], record_of(t)), keys(run.scratch.cache))
    @test all(t -> haskey(run.scratch.cache, t), keys(peaks))
    again = local_synthetic(0.0, record_of)
    @test isequal(run.requested, again.requested)
    @test isequal(run.best, again.best)
end

@testset "local transfer search: one improving-payoff refinement per run" begin
    # Finite-payoff peaks with the status quo at 0.0: the guidance stage
    # refines the top guidance peak and the payoff stage refines the top
    # strictly improving cached candidate, six iteration probes each.
    peaks = Dict{Float64,Float64}(
        -0.0001 => 8.0, 0.0001 => 8.0,
        -0.001 => 7.0, 0.001 => 7.0,
        -0.003 => 6.0, 0.003 => 5.0,
    )
    record_of = theta -> begin
        if haskey(peaks, theta)
            local_record(peaks[theta]; gw=peaks[theta], gm=peaks[theta])
        elseif isequal(theta, 0.0)
            # The both-zero-gain status point is a candidate but never a peak.
            local_record(0.0; gw=0.0, gm=0.0)
        else
            local_record(-Inf)
        end
    end
    run = local_synthetic(0.0, record_of)
    probes = run.requested[(length(run.stage_a) + 1):end]
    @test !isempty(probes)
    @test length(probes) <= 2 * GN.TRANSFER_REFINE_MAX_ITER
    @test length(run.scratch.cache) <= GN.TRANSFER_SEARCH_MAX_EVALS
    # Unrefined peaks remain candidates: the best is the top cached payoff.
    @test isequal(run.best, -0.0001)
    @test all(t -> isequal(run.scratch.cache[t], record_of(t)), keys(run.scratch.cache))
end

@testset "local transfer search: guidance floor and the both-zero-gain point" begin
    # A tiny negative guidance peak above the floor is the almost-feasible
    # signal of `MDR-0016` and receives refinement; one below the floor
    # does not. The exact both-zero-gain zero point never refines but stays
    # a candidate.
    near = theta -> isequal(theta, 0.001) ?
        local_record(-Inf; gw=-1.0e-5, gm=-1.0e-5) : local_record(-Inf)
    run = local_synthetic(0.0, near)
    probes = run.requested[(length(run.stage_a) + 1):end]
    @test !isempty(probes)

    below = theta -> isequal(theta, 0.001) ?
        local_record(-Inf; gw=-3.0e-5, gm=-3.0e-5) : local_record(-Inf)
    run = local_synthetic(0.0, below)
    @test run.requested == run.stage_a

    zero = theta -> isequal(theta, 0.0) ?
        local_record(0.5; gw=0.0, gm=0.0) : local_record(-Inf)
    run = local_synthetic(0.0, zero)
    probes = run.requested[(length(run.stage_a) + 1):end]
    @test isempty(probes)
    @test isequal(run.best, 0.0)
end

@testset "local transfer search: bound guidance rescues a hidden band" begin
    # Household-100 shape: no sampled ladder point is feasible, but
    # solved probes with payoff `-Inf` and tiny negative guidance (one
    # gain slightly negative, the other positive, exactly the
    # production shape at household 100's Stage A probes) flank an
    # unprobed feasible band, and the guidance refinement walks into
    # it. Every record is production-realizable: outside the band one
    # gain is slightly negative so the payoff is `-Inf` with negative
    # guidance, inside both gains are non-negative so the finite payoff
    # is their product; positive guidance never pairs with `-Inf` and
    # the guidance crosses zero continuously at the band edges (a
    # one-off `-Inf` guidance cliff just below the band would shrink
    # the Brent bracket away from it; real gains decay smoothly).
    guide(theta) = 2.0e-6 - 200.0 * (theta - 0.0007)^2
    record_of = theta -> begin
        g = guide(theta)
        g >= 0.0 ? local_record(g; gw=g, gm=1.0) : local_record(-Inf; gw=g, gm=1.0)
    end
    run = local_synthetic(0.0, record_of)
    @test isfinite(run.best)
    @test 0.0006 < run.best < 0.0008
    @test run.scratch.cache[run.best].payoff > 0.0
    # The band is hidden between every sampled point of Stage A.
    @test all(t -> !isfinite(record_of(t).payoff), run.stage_a)
    # Production realizability of every cached record: a certified-style
    # or solved `-Inf` never carries positive guidance, and a finite
    # non-negative payoff always carries non-negative guidance.
    for theta in keys(run.scratch.cache)
        entry = run.scratch.cache[theta]
        g = min(entry.guidance_w, entry.guidance_m)
        if !isfinite(entry.payoff)
            @test !(g > 0.0)
        elseif entry.payoff >= 0.0
            @test g >= 0.0
        end
    end
    again = local_synthetic(0.0, record_of)
    @test isequal(run.requested, again.requested)
    @test isequal(run.best, again.best)
end

@testset "local transfer search: hard record cap in the worst case" begin
    # Off-grid status quo with both anchor ladders, all four adaptive
    # probes, one guidance refinement, and one payoff refinement forced
    # through all their iteration probes on uncached positions: the
    # derived worst case of TRANSFER_SEARCH_MAX_EVALS.
    theta0 = 0.123456789
    record_of = theta -> begin
        if isequal(theta, theta0 + 0.001)
            local_record(-Inf; gw=10.0, gm=10.0)
        elseif isequal(theta, -1.0)
            local_record(1.0; gw=1.0, gm=1.0)
        elseif theta in (0.001, -0.001, theta0 - 0.001, 0.0003, -0.0003, theta0 - 0.0003, theta0 + 0.0003)
            local_record(-Inf; gw=2.0, gm=2.0)
        elseif theta in (0.0001, -0.0001, theta0 - 0.0001, theta0 + 0.0001)
            local_record(-Inf; gw=1.0, gm=1.0)
        else
            local_record(-Inf)
        end
    end
    run = local_synthetic(theta0, record_of; tol=1.0e-100)
    @test length(run.stage_a) + 1 == 32
    @test length(run.scratch.cache) == GN.TRANSFER_SEARCH_MAX_EVALS
    @test length(run.requested) == length(run.stage_a) + 2 * GN.TRANSFER_REFINE_MAX_ITER
end

@testset "local transfer search: broad remote hit and explicit missed band" begin
    # Remote exploration runs even with no finite local-neighbour samples:
    # the coarse ladder probes the broad band around 0.25.
    remote = theta -> abs(theta - 0.25) < 0.1 ? 1.0 - ((theta - 0.25) / 0.1)^2 : -Inf
    hit = local_synthetic(0.0, theta -> local_record(remote(theta); gw=remote(theta), gm=remote(theta)))
    @test isfinite(hit.best)
    @test abs(hit.best - 0.25) <= 0.02
    @test hit.scratch.cache[hit.best].payoff > remote(0.256)

    # This remote band is wider than the old 1e-3 discovery spacing but
    # entirely between production exploration probes, and with no bound
    # guidance signal nothing steers the refinement at it. Production
    # must not silently fall back to discovery or assert global
    # infeasibility.
    band = theta -> abs(theta - 0.02) < 0.003 ?
        1.0 - ((theta - 0.02) / 0.003)^2 : -Inf
    miss = local_synthetic(0.0, theta -> local_record(band(theta); gw=band(theta), gm=band(theta)))
    @test isnan(miss.best)
    @test isequal(miss.requested, miss.stage_a)
    cache = Dict(0.0 => local_record(-Inf))
    found = GN._transfer_search!(
        cache, t -> local_record(band(t)), 0.0, GN.TRANSFER_REFINE_TOL,
    )
    @test isfinite(found) && cache[found].payoff > 0.99
end

@testset "local transfer search: plateau and non-finite neighbour values" begin
    # A constant guidance plateau collapses to the representative nearest
    # the status quo and refines exactly one peak.
    plateau = local_synthetic(0.0, theta -> local_record(1.0; gw=1.0, gm=1.0))
    probes = plateau.requested[(length(plateau.stage_a) + 1):end]
    @test !isempty(probes)
    @test all(t -> -1.0e-4 < t < 1.0e-4, probes)
    @test length(plateau.scratch.maxima) == 1
    @test isequal(plateau.best, 0.0)

    # A non-finite neighbouring value is worst, not a barrier to
    # refinement: the band holds the 0.001 ladder point but its right
    # sampled neighbour is `NaN`.
    star = 0.001475
    peak = theta -> isequal(theta, 0.0) ? -Inf :
        (abs(theta - star) < 5.0e-4 ? 1.0 - 1000.0 * (theta - star)^2 : NaN)
    run = local_synthetic(0.0, theta -> local_record(peak(theta); gw=peak(theta), gm=peak(theta)))
    @test isfinite(run.best)
    @test abs(run.best - star) <= 1.0e-4
    @test !(run.best in run.stage_a)
    @test run.scratch.cache[run.best].payoff > maximum(
        peak(t) for t in run.stage_a if isfinite(peak(t))
    )

    # Non-improving candidates remain cached but cannot beat the status quo.
    lower = local_synthetic(0.0, theta -> isequal(theta, 0.0) ?
        local_record(2.0; gw=2.0, gm=2.0) : local_record(1.0; gw=1.0, gm=1.0))
    @test isequal(lower.best, 0.0)
end

@testset "local transfer search: ladder resolution and boundary brackets" begin
    # Bands containing a ladder point are found directly and refined.
    for star in (0.0001, -0.0001, 0.001, 0.003, 0.03, -0.3)
        peak = t -> abs(t - star) < 5.0e-5 ? 1.0 - 1.0e8 * (t - star)^2 : -Inf
        run = local_synthetic(0.0, theta -> local_record(peak(theta); gw=peak(theta), gm=peak(theta)))
        @test isfinite(run.best) && abs(run.best - star) <= GN.TRANSFER_REFINE_TOL
    end
    # Domain-boundary brackets stay one-sided and inside the domain.
    for edge in (-1.0, 1.0)
        star = edge - sign(edge) * 0.05
        peak = t -> abs(t - edge) < 0.2 ? 1.0 - (t - star)^2 : -Inf
        run = local_synthetic(0.0, theta -> local_record(peak(theta); gw=peak(theta), gm=peak(theta)))
        @test isfinite(run.best)
        @test abs(run.best - star) <= 0.02
        @test all(t -> -1.0 <= t <= 1.0, run.requested)
    end
end

"""
    local_fixture_case(h)

Decode one frozen near-zero household without changing its recorded state.
"""
function local_fixture_case(h)
    f(key) = parse(Float64, h[key])
    fields = ("wage_self", "wage_spouse", "alpha", "conformism", "N_h", "N_theta", "N_h_spouse")
    pw = GN.AgentPayoffParams((f("pw_" * key) for key in fields)..., true)
    pm = GN.AgentPayoffParams((f("pm_" * key) for key in fields)..., false)
    return (f("hw_init"), f("hm_init"), f("theta_init"), pw, pm,
        GN.UtilityConfig(func=GN.CES(beta=f("beta"))))
end

@testset "local transfer search: fixture gains, cached hours, and scratch reuse" begin
    fixture = TOML.parsefile(joinpath(@__DIR__, "fixtures", "transfer_feasibility_households.toml"))
    scratch = GN.TransferSearchScratch()
    @test length(fixture["household"]) == 3
    for h in fixture["household"]
        args = local_fixture_case(h)
        result = GN.bargain_transfer(scratch, args...)
        @test isequal(result, GN.bargain_transfer(args...; search=:local))
        @test result[1] != 0.0
        @test length(scratch.cache) <= GN.TRANSFER_SEARCH_MAX_EVALS
        entry = scratch.cache[result[1]]
        @test isequal((result[2], result[3]), (entry.hw, entry.hm))
        @test entry.payoff >= parse(Float64, h["demo_payoff"])
        @test entry.gain_w >= 0.0 && entry.gain_m >= 0.0
        # Alternating modes on the same scratch cannot leak candidates,
        # slabs, or the validation search's much larger sampled sequence.
        GN.bargain_transfer(scratch, args...; search=:discovery)
        @test isequal(result, GN.bargain_transfer(scratch, args...))
    end
    # The non-finite-outside fast path also drops all previous scratch state.
    pw = GN.AgentPayoffParams(wage_self=1.0, wage_spouse=0.0, is_woman=true)
    pm = GN.AgentPayoffParams(wage_self=0.0, wage_spouse=1.0, is_woman=false)
    for search in (:local, :discovery)
        scratch.cache[0.0] = GN.TransferObjectiveValue(1.0, 1.0, 1.0, 0.5, 0.5)
        push!(scratch.samples, (0.0, 1.0))
        push!(scratch.maxima, 1)
        push!(scratch.slabs, (-1.0, 1.0))
        result = GN.bargain_transfer(scratch, 0.5, 0.5, -0.0, pw, pm, GN.UtilityConfig(); search=search)
        @test isequal(result[1], -0.0)
        @test isempty(scratch.cache) && isempty(scratch.samples)
        @test isempty(scratch.maxima) && isempty(scratch.slabs)
    end
end

@testset "local transfer search: household 100 hidden band has no Stage A hit" begin
    # Production-realizable hidden-band path of household 100
    # (`benchmark/guided_search_validation.md` section 1): its measured
    # feasible band [6.65e-4, 8.05e-4] contains no Stage A ladder point,
    # so no Stage A probe can hit it directly, and the production
    # driver rescues it through Stage B guidance refinement (tiny
    # negative guidance at the flanking solved probes, one gain
    # slightly negative). The band check uses the test-owned
    # `LOCAL_*` literals, never the driver's constants.
    fixture = TOML.parsefile(joinpath(@__DIR__, "fixtures", "transfer_feasibility_households.toml"))
    h = only(filter(h -> h["id"] == 100, fixture["household"]))
    @test isequal(parse(Float64, h["theta_init"]), 0.0)
    band_lo, band_hi = 6.65e-4, 8.05e-4
    candidates = Float64[-1.0, 0.0, 1.0]
    for offset in LOCAL_EXPLORE_OFFSETS
        push!(candidates, offset, -offset)
    end
    push!(candidates, LOCAL_ADAPTIVE_OFFSET, -LOCAL_ADAPTIVE_OFFSET)
    @test all(t -> !(band_lo <= t <= band_hi), candidates)
    args = local_fixture_case(h)
    scratch = GN.TransferSearchScratch()
    result = GN.bargain_transfer(scratch, args...)
    entry = scratch.cache[result[1]]
    @test entry.payoff >= parse(Float64, h["demo_payoff"])
    @test entry.payoff > 0.0
    # The commit is a refinement probe, not a Stage A sample.
    @test all(t -> !isequal(t, result[1]), candidates)
    # No Stage A candidate strictly beats the status quo, while the
    # refinement commit does: the band is rescued by Stage B/C, not by
    # a direct Stage A hit.
    status_payoff = scratch.cache[0.0].payoff
    for t in candidates
        haskey(scratch.cache, t) || continue
        @test !(scratch.cache[t].payoff > status_payoff)
    end
    @test entry.payoff > status_payoff
end

@testset "local transfer search: explicit mode and tolerance validation" begin
    pw = GN.AgentPayoffParams(is_woman=true)
    pm = GN.AgentPayoffParams(is_woman=false)
    config = GN.UtilityConfig()
    args = (0.5, 0.5, 0.0, pw, pm, config)
    @test_throws ArgumentError GN.bargain_transfer(args...; search=:unknown)
    @test_throws ArgumentError GN.bargain_transfer(GN.TransferSearchScratch(), args...; search=:unknown)
    for search in (:local, :discovery), tol in (0.0, -1.0e-5, NaN, Inf)
        @test_throws ArgumentError GN.bargain_transfer(args...; search=search, tol=tol)
    end
    # Mode errors precede world queries, including an empty world.
    @test_throws ArgumentError GN.set_theta!(Ark.World(), config; search=:unknown)
end
