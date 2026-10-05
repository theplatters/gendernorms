# Search-contract tests for the retained offline discovery driver of
# `bargain_transfer` (`MDR-0014`, `ADR-0019`, `ADR-0020`): Stage A tiered
# evaluation-set coverage and order, Stage B refinement brackets and
# equal-payoff plateaus, the exact bounded-Brent refinement-run counts
# (one run per plateau, one-sided brackets at the domain boundaries)
# and an off-grid peak that only the Stage B refinement can reach, so
# the refinement checks cannot pass vacuously, the candidate tie rule,
# the strict-improvement commit rule, the documented band-discovery
# guarantee of `MDR-0014` (windowed synthetic bands at the recorded
# widths and offsets: found exactly when the band contains a sampled
# transfer, missable otherwise), and the regression fixtures of the
# three benchmark households whose near-zero feasible band the
# pre-`MDR-0012` unseeded Brent search missed
# (`benchmark/transfer_search_diagnosis.md`). The driver
# `GN._transfer_search!` is probed through its cache with manufactured
# evaluations, so the search contract is checked exactly and cheaply;
# the constructed `bargain_transfer` cases use probe `UtilitySpec`s that
# make payoffs controllable; the regression fixtures drive the real
# solver chain. Objective-level bitwise checks and the boundary-household
# objective equality live in `test/test_bargaining_equivalence.jl` and
# `test/test_bargain_certificate.jl`; the non-finite-outside fast path is
# tested in `test/test_bargain_certificate.jl`; the sample-set subset
# and cache-discipline contract of `ADR-0019` lives in
# `test/test_transfer_search_reduction.jl`.

using GenderNorms
using Test
using TOML

const GN = GenderNorms

"""
    t64(text::AbstractString)::Float64

Read one fixture float of `test/fixtures/transfer_feasibility_households.toml`
(the fixture encodes every `Float64` as a quoted Julia `repr` string).
"""
t64(text::AbstractString)::Float64 = parse(Float64, text)

# `MDR-0013` validated-equivalence helper (defined in
# `test/test_bargaining_equivalence.jl` for the full suite); the guard
# keeps this file runnable on its own. The fixture households use
# `CES` `beta == 0.5`, whose arithmetic changed under `MDR-0013`.
if !isdefined(@__MODULE__, :veq)
    """
        veq(a::Float64, b::Float64)::Bool

    Validated-equivalence float comparison of `MDR-0013`: `isapprox`
    with the recorded tolerance envelope where the arithmetic changed,
    `isequal` otherwise (and for non-finite values).
    """
    veq(a::Float64, b::Float64)::Bool =
        (isfinite(a) && isfinite(b)) ? isapprox(a, b; atol = 1.0e-10, rtol = 1.0e-9) : isequal(a, b)
end

"""
    stage_a_sequence(theta0::Float64)

The Stage A evaluation sequence of `GN._transfer_search!` for a status
quo `theta0`, recomputed independently in the test: the anchors, the
fine anchor windows, and the coarse grid in their recorded order,
minus every transfer the cache already holds (the cache is seeded at
`theta0`). Returns the sequence the evaluator must be asked about,
exactly and in order.
"""
function stage_a_sequence(theta0::Float64)::Vector{Float64}
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
    recording_evaluator(requested::Vector{Float64}, payoff_of)

Manufactured evaluation function for `GN._transfer_search!`: records
every requested transfer in `requested` (in request order) and returns
a `TransferObjectiveValue` with the manufactured payoff
`payoff_of(theta)` and `NaN` gains and hours.
"""
function recording_evaluator(requested::Vector{Float64}, payoff_of)
    return function (theta::Float64)
        push!(requested, theta)
        return GN.TransferObjectiveValue(NaN, NaN, payoff_of(theta), NaN, NaN)
    end
end

"""
    run_synthetic(theta0::Float64, payoff_of)

Run `GN._transfer_search!` with a fresh cache seeded at `theta0` and the
manufactured `payoff_of` objective. Returns
`(best_theta, cache, requested, stage_a)`.
"""
function run_synthetic(theta0::Float64, payoff_of)
    requested = Float64[]
    cache = Dict{Float64, GN.TransferObjectiveValue}()
    cache[theta0] = GN.TransferObjectiveValue(NaN, NaN, payoff_of(theta0), NaN, NaN)
    best_theta = GN._transfer_search!(
        cache, recording_evaluator(requested, payoff_of), theta0, GN.TRANSFER_REFINE_TOL
    )
    return best_theta, cache, requested, stage_a_sequence(theta0)
end

# Curvature of the manufactured off-grid peaks of `windowed_peak`:
# `1.0 - PEAK_CURVATURE * dist^2` puts the refined candidate's payoff
# within `PEAK_CURVATURE * tol^2` of the true peak while the nearby
# Stage A samples stay strictly below it.
const PEAK_CURVATURE = 1000.0

"""
    windowed_peak(theta_star::Float64, window::Float64)

Manufactured transfer objective of the Stage B pins with its maximum at
the off-grid `theta_star`: `1.0 - PEAK_CURVATURE * dist^2` for `|theta -
theta_star| < window` and `-Inf` otherwise, faithful to the objective
value contract (a `Float64` payoff, `-Inf` infeasible). The window is
chosen per scenario so that exactly the intended Stage A transfers stay
finite, which pins the sampled weak local maxima (and with them the
refinement runs) exactly: a wholly finite smooth objective would gain
weak local maxima wherever a coarse/local grid-twin pair rounds to
equal payoffs.
"""
function windowed_peak(theta_star::Float64, window::Float64)
    return function (theta::Float64)
        dist = abs(theta - theta_star)
        return dist < window ? 1.0 - PEAK_CURVATURE * dist^2 : -Inf
    end
end

"""
    sample_bracket(sampled::Vector{Float64}, representative::Float64)

The bounded-Brent refinement bracket of `MDR-0012` for the refined
`representative`, recomputed independently in the test from the sorted
sampled set: its previous and next distinct sampled transfers, or the
representative itself at a domain boundary (a one-sided bracket there).
"""
function sample_bracket(sampled::Vector{Float64}, representative::Float64)
    j = findfirst(isequal(representative), sampled)
    lo = j > 1 ? sampled[j - 1] : sampled[j]
    hi = j < length(sampled) ? sampled[j + 1] : sampled[j]
    return (lo, hi)
end

"""
    refinement_runs(requested::Vector{Float64}, sampled::Vector{Float64}, brackets::Vector{Tuple{Float64,Float64}}) -> Vector{Int}

The bounded-Brent refinement runs of one `GN._transfer_search!` call,
counted exactly from the evaluator call record `requested`: every Stage
A transfer is sampled and every refinement bracket endpoint is cached,
so an evaluator call at a non-sampled transfer is a Stage B probe
strictly inside exactly one refinement bracket (the brackets of
distinct representatives share at most an endpoint). Consecutive probes
inside one bracket come from one `maximize_1d` run and the runs execute
sequentially, one per plateau of `MDR-0012`; only the representative is
cached inside its bracket, so every run leaves at least one probe in
the record. Returns the bracket index of every refinement run in
execution order, or `0` for a probe outside every expected bracket (a
search-contract violation).
"""
function refinement_runs(
        requested::Vector{Float64}, sampled::Vector{Float64},
        brackets::Vector{Tuple{Float64, Float64}},
    )::Vector{Int}
    runs = Int[]
    for theta in requested
        any(isequal(theta), sampled) && continue
        bracket = findfirst(b -> b[1] < theta < b[2], brackets)
        index = bracket === nothing ? 0 : bracket
        (isempty(runs) || runs[end] != index) && push!(runs, index)
    end
    return runs
end

@testset "transfer search: Stage A evaluation set and order" begin
    # Every anchor, every fine-grid point of both fine anchor windows,
    # and every coarse-grid point is evaluated exactly once, in the
    # recorded deterministic order, with overlaps deduplicated through
    # the cache (the status quo `theta0` is seeded, so it is never
    # requested). A wholly infeasible manufactured objective keeps
    # Stage B quiet and leaves only Stage A requests.
    for theta0 in (0.0, -0.0, 0.3, -1.0, 1.0, 0.123456789)
        best_theta, cache, requested, stage_a = run_synthetic(theta0, theta -> -Inf)
        @test all(isequal(a, b) for (a, b) in zip(requested, stage_a))
        @test length(requested) == length(stage_a)
        @test isnan(best_theta)
        # Anchors and their fine windows are covered explicitly.
        for anchor in (-1.0, 0.0, theta0, 1.0)
            @test anchor in keys(cache)
        end
        for anchor in (0.0, theta0)
            for k in 1:GN.TRANSFER_FINE_STEPS
                @test clamp(anchor + k * GN.TRANSFER_FINE_STEP, -1.0, 1.0) in keys(cache)
                @test clamp(anchor - k * GN.TRANSFER_FINE_STEP, -1.0, 1.0) in keys(cache)
            end
        end
        for theta in -1.0:GN.TRANSFER_COARSE_STEP:1.0
            @test theta in keys(cache)
        end
    end
end

@testset "transfer search: tie rule and refinement brackets" begin
    # Two isolated candidates with exactly equal payoffs at exactly
    # equal distances from the status quo: the tie rule of `MDR-0012`
    # picks the smaller theta. With the status quo moved, the closer
    # candidate wins. The refinement runs stay inside the brackets of
    # the previous and next sampled transfers of their representative.
    theta0 = 0.0
    # Exact-magnitude mirror pair of the fine window: the manufactured
    # payoffs must hit sampled transfers exactly, and the fine-grid
    # points `+/- k * TRANSFER_FINE_STEP` are exact mirrors (a
    # coarse-grid pair would not be, the lattice is computed
    # asymmetrically).
    pos = 0.0 + 15 * GN.TRANSFER_FINE_STEP
    neg = 0.0 - 15 * GN.TRANSFER_FINE_STEP
    payoff_of = theta -> (isequal(theta, pos) || isequal(theta, neg)) ? 1.0 : -Inf
    best_theta, cache, requested, stage_a = run_synthetic(theta0, payoff_of)
    @test isequal(abs(pos - theta0), abs(neg - theta0))  # exact-distance tie
    @test isequal(best_theta, neg)
    finite = [theta for theta in keys(cache) if isfinite(cache[theta].payoff)]
    @test length(finite) == 2
    # Refinement samples lie between the sampled neighbours of a
    # refined candidate (the bracket of `MDR-0012`); the neighbours are
    # taken from the sampled set, not from the refinement results.
    sampled = sort(collect(Set(vcat(stage_a, [theta0]))))
    for theta in requested
        any(isequal(theta), sampled) && continue
        refined_ok = any(sampled) do candidate
            isfinite(cache[candidate].payoff) || return false
            j = findfirst(isequal(candidate), sampled)
            lo = j > 1 ? sampled[j - 1] : sampled[j]
            hi = j < length(sampled) ? sampled[j + 1] : sampled[j]
            return lo <= theta <= hi
        end
        @test refined_ok
    end
    # Non-vacuity: the bracket checks above are meaningful only when
    # refinement actually ran. Two isolated candidates are two plateaus
    # of `MDR-0012`, so at least two bounded-Brent refinements must be
    # visible in the evaluator call record.
    brackets = [sample_bracket(sampled, neg), sample_bracket(sampled, pos)]
    @test length(refinement_runs(requested, sampled, brackets)) >= 2

    # Distance rule: the candidate closest to the status quo wins an
    # exact payoff tie.
    theta0 = pos
    best_theta, cache, requested, stage_a = run_synthetic(theta0, payoff_of)
    @test isequal(best_theta, pos)
    # Non-vacuity again: moving the status quo changes the winner, not
    # the two refinement runs of the two isolated candidates.
    sampled = sort(collect(Set(vcat(stage_a, [theta0]))))
    brackets = [sample_bracket(sampled, neg), sample_bracket(sampled, pos)]
    @test length(refinement_runs(requested, sampled, brackets)) >= 2
end

@testset "transfer search: equal-payoff plateau refines once" begin
    # A plateau of equal-payoff adjacent weak local maxima refines only
    # the member closest to the status quo (then the smallest theta);
    # every plateau member stays a candidate. The manufactured plateau
    # boundary 0.01075 lies strictly between the sampled points
    # 0.010 and 0.011 of the coarse grid (outside the fine windows).
    theta0 = 0.0
    payoff_of = theta -> abs(theta) <= 0.01075 ? 1.0 : -Inf
    best_theta, cache, requested, stage_a = run_synthetic(theta0, payoff_of)
    sampled = sort(collect(Set(vcat(stage_a, [theta0]))))
    sampled_plateau = [theta for theta in sampled if cache[theta].payoff == 1.0]
    @test length(sampled_plateau) >= 50
    @test all(theta -> -0.01075 <= theta <= 0.01075, sampled_plateau)
    # The single refinement is bracketed by the sampled neighbours of
    # the representative `theta0`, the anchor 0.0 on the fine grid.
    @test isequal(best_theta, theta0)
    j = findfirst(isequal(theta0), sampled)
    lo, hi = sampled[j - 1], sampled[j + 1]
    @test lo == -GN.TRANSFER_FINE_STEP && hi == GN.TRANSFER_FINE_STEP
    for theta in requested
        any(isequal(theta), sampled) && continue
        @test lo <= theta <= hi
    end
    # Non-vacuity: at least one bounded-Brent refinement must be
    # visible inside the bracket for the checks above to mean anything.
    @test length(refinement_runs(requested, sampled, [(lo, hi)])) >= 1

    # Off the plateau the representative is the sampled plateau member
    # closest to the status quo; the refinement stays inside its sampled
    # bracket and the winner is a plateau-region candidate at least as
    # close to the status quo as the representative.
    theta0 = 0.014
    best_theta, cache, requested, stage_a = run_synthetic(theta0, payoff_of)
    sampled = sort(collect(Set(vcat(stage_a, [theta0]))))
    sampled_plateau = sort([theta for theta in sampled if cache[theta].payoff == 1.0])
    representative = sampled_plateau[1]
    for theta in sampled_plateau[2:end]
        if abs(theta - theta0) < abs(representative - theta0) ||
                (abs(theta - theta0) == abs(representative - theta0) && theta < representative)
            representative = theta
        end
    end
    @test isequal(representative, maximum(sampled_plateau))
    j = findfirst(isequal(representative), sampled)
    lo, hi = sampled[j - 1], sampled[j + 1]
    for theta in requested
        any(isequal(theta), sampled) && continue
        @test lo <= theta <= hi
    end
    @test length(refinement_runs(requested, sampled, [(lo, hi)])) >= 1
    @test cache[best_theta].payoff == 1.0
    @test best_theta <= 0.01075
    @test abs(best_theta - theta0) <= abs(representative - theta0)
end

@testset "transfer search: Stage B refinement reaches an off-grid peak" begin
    # Pins that Stage B refinement actually runs and matters: the
    # manufactured objective peaks at `theta_star`, strictly between the
    # adjacent sampled transfers `s_lo` and `s_hi` (off the Stage A
    # grid) and strictly above every Stage A sample value, so the only
    # winning candidate is a bounded-Brent refinement probe. If
    # `_transfer_search!` stopped refining, the winner would be the
    # Stage A point `s_hi` and these assertions fail. The window keeps
    # exactly `s_lo` and `s_hi` finite (`-Inf` elsewhere), which pins
    # the sampled weak local maxima to `s_hi` alone: exactly one
    # plateau of `MDR-0012` and exactly one refinement.
    theta0 = 0.0
    sampled = sort(collect(Set(vcat(stage_a_sequence(theta0), [theta0]))))
    j = findlast(<(0.00145), sampled)  # the fine-grid pair around 0.00145
    s_lo, s_hi = sampled[j], sampled[j + 1]
    @test 0.5 * GN.TRANSFER_FINE_STEP < s_hi - s_lo < 2.0 * GN.TRANSFER_FINE_STEP
    theta_star = s_lo + 0.75 * (s_hi - s_lo)
    @test s_lo < theta_star < s_hi
    @test !any(isequal(theta_star), sampled)
    payoff_of = windowed_peak(theta_star, 1.0e-4)
    @test payoff_of(s_lo) > -Inf && payoff_of(s_hi) > -Inf
    @test payoff_of(sampled[j - 1]) == -Inf && payoff_of(sampled[j + 2]) == -Inf
    peak = payoff_of(theta_star)
    @test all(theta -> peak > payoff_of(theta), sampled)  # strictly better than every Stage A sample
    best_theta, cache, requested, stage_a = run_synthetic(theta0, payoff_of)
    # The winner is the refined off-grid point (a refinement probe of
    # the evaluator record), never a Stage A point, and its payoff
    # reaches the injected true peak within the refinement tolerance.
    @test isfinite(best_theta)
    @test !any(isequal(best_theta), sampled)
    @test any(isequal(best_theta), requested)
    @test cache[best_theta].payoff >= peak - GN.TRANSFER_REFINE_TOL
    @test cache[best_theta].payoff > maximum(theta -> cache[theta].payoff, sampled)
    # Exact refinement count for a single interior peak: `s_hi` is the
    # only weak local maximum, so exactly one bounded-Brent run, on the
    # bracket of its previous and next distinct sampled transfers.
    bracket = sample_bracket(sampled, s_hi)
    @test bracket == (s_lo, sampled[j + 2])
    @test refinement_runs(requested, sampled, [bracket]) == [1]
end

@testset "transfer search: exact refinement run counts" begin
    # Exact bounded-Brent refinement counts of the plateau rule of
    # `MDR-0012` (one run per plateau of adjacent equal-payoff weak
    # local maxima), counted from the evaluator call record with
    # `refinement_runs`. Equal-payoff plateau first: exactly ONE
    # refinement, on the bracket of the plateau member closest to the
    # status quo, although every plateau member stays a candidate.
    theta0 = 0.0
    payoff_of = theta -> abs(theta) <= 0.01075 ? 1.0 : -Inf
    best_theta, cache, requested, stage_a = run_synthetic(theta0, payoff_of)
    sampled = sort(collect(Set(vcat(stage_a, [theta0]))))
    bracket = sample_bracket(sampled, theta0)
    @test bracket == (-GN.TRANSFER_FINE_STEP, GN.TRANSFER_FINE_STEP)
    @test refinement_runs(requested, sampled, [bracket]) == [1]

    # One-sided domain-boundary case (left): the objective peaks
    # off-grid strictly inside the one-sided refinement bracket of the
    # boundary sample `-1.0`, which compares only its right neighbour.
    # Exactly one refinement, and it reaches the off-grid peak, so the
    # one-sided bracket is actually searched.
    sampled = sort(collect(Set(vcat(stage_a_sequence(theta0), [theta0]))))
    s_edge, s_next = sampled[1], sampled[2]
    @test s_edge == -1.0
    @test 0.5 * GN.TRANSFER_COARSE_STEP < s_next - s_edge < 2.0 * GN.TRANSFER_COARSE_STEP
    theta_star = s_edge + 0.25 * (s_next - s_edge)
    @test s_edge < theta_star < s_next
    payoff_of = windowed_peak(theta_star, 1.0e-3)
    @test payoff_of(s_edge) > -Inf && payoff_of(s_next) > -Inf
    @test payoff_of(sampled[3]) == -Inf
    best_theta, cache, requested, stage_a = run_synthetic(theta0, payoff_of)
    bracket = sample_bracket(sampled, s_edge)
    @test bracket == (s_edge, s_next)  # one-sided at the domain boundary
    @test refinement_runs(requested, sampled, [bracket]) == [1]
    @test !any(isequal(best_theta), sampled)
    @test cache[best_theta].payoff >= payoff_of(theta_star) - GN.TRANSFER_REFINE_TOL
    @test cache[best_theta].payoff > cache[s_edge].payoff

    # One-sided domain-boundary case (right), the mirror of the left:
    # the boundary sample `+1.0` refines exactly once, on the one-sided
    # bracket of its previous distinct sampled transfer.
    sampled = sort(collect(Set(vcat(stage_a_sequence(theta0), [theta0]))))
    s_edge, s_next = sampled[end], sampled[end - 1]
    @test s_edge == 1.0
    @test 0.5 * GN.TRANSFER_COARSE_STEP < s_edge - s_next < 2.0 * GN.TRANSFER_COARSE_STEP
    theta_star = s_edge + 0.25 * (s_next - s_edge)
    @test s_next < theta_star < s_edge
    payoff_of = windowed_peak(theta_star, 1.0e-3)
    @test payoff_of(s_edge) > -Inf && payoff_of(s_next) > -Inf
    @test payoff_of(sampled[end - 2]) == -Inf
    best_theta, cache, requested, stage_a = run_synthetic(theta0, payoff_of)
    bracket = sample_bracket(sampled, s_edge)
    @test bracket == (s_next, s_edge)  # one-sided at the domain boundary
    @test refinement_runs(requested, sampled, [bracket]) == [1]
    @test !any(isequal(best_theta), sampled)
    @test cache[best_theta].payoff >= payoff_of(theta_star) - GN.TRANSFER_REFINE_TOL
    @test cache[best_theta].payoff > cache[s_edge].payoff
end

@testset "transfer search: documented band-discovery guarantee" begin
    # The discovery guarantee of `MDR-0014`, encoded exactly on
    # windowed synthetic bands (`windowed_peak`): a band containing at
    # least one sampled transfer of the tiered Stage A set is
    # discovered (the sampled transfer is a weak local maximum whose
    # bounded refinement reaches the injected peak to within the
    # refinement tolerance), while a band containing no sampled
    # transfer can be missed - on a windowed band the miss is exact
    # (no sample, no finite cached value, no refinement), so those
    # cases assert the miss itself and document the class of bands the
    # reduced resolution does not guarantee. Band widths 3e-5 to 3e-3
    # (the measured model-band range of `MDR-0014`) at offsets 1e-4 to
    # 2e-2 from the anchors `0.0` and `theta0`; width at least the
    # local spacing within the fine window and at least the coarse
    # spacing elsewhere is the recorded guarantee.
    theta0 = 0.00037  # off both grids: the two fine windows are distinct
    sampled = sort(collect(Set(vcat(stage_a_sequence(theta0), [theta0]))))
    widths = (3.0e-5, 1.0e-4, 3.0e-4, 1.0e-3, 3.0e-3)
    offsets = (0.0001, 0.0005, 0.0011, 0.002, 0.005, 0.01, 0.02)
    n_found = 0
    n_missed = 0
    for anchor in (0.0, theta0), width in widths, offset in offsets, sign in (-1.0, 1.0)
        theta_star = anchor + sign * offset
        (-1.0 <= theta_star <= 1.0) || continue
        window = width / 2.0
        hit = any(s -> abs(s - theta_star) < window, sampled)
        payoff_of = windowed_peak(theta_star, window)
        best_theta, cache, requested, stage_a = run_synthetic(theta0, payoff_of)
        if hit
            # Documented guarantee: the band holds a sampled transfer,
            # so a finite candidate is found and reaches the peak to
            # within the refinement tolerance (narrow windows hold
            # their sample within the tolerance distance outright).
            @test isfinite(best_theta)
            @test cache[best_theta].payoff >= payoff_of(theta_star) - GN.TRANSFER_REFINE_TOL
            n_found += 1
        else
            # Documented miss class: no sample inside the band, no
            # finite cached value anywhere, so the search falls back
            # and the band is not discovered.
            @test isnan(best_theta)
            n_missed += 1
        end
    end
    # Non-vacuity: both sides of the documented rule are exercised
    # (misses arise for sub-spacing bands between coarse samples away
    # from the fine windows).
    @test n_found >= 50
    @test n_missed >= 5
end

# Probe utility specs for the constructed `bargain_transfer` cases: a
# constant material value makes payoffs controllable through the
# conformism norm term alone (see `test/test_bargain_certificate.jl` for
# the counting probes).

struct ConstantMaterial <: GN.UtilitySpec end

GN.material(::ConstantMaterial, x::Float64, Q::Float64, alpha::Float64) = 1.0

@testset "transfer search: commit only on strict improvement" begin
    # Constructed case with every candidate payoff exactly equal to the
    # status-quo payoff: the constant material utility makes every gain
    # exactly zero, so the search must stay at the status quo.
    config = GN.UtilityConfig(func = ConstantMaterial())
    pw = GN.AgentPayoffParams{GN.Female}(
        wage_self = 1.0, wage_spouse = 1.0, alpha = 0.5, conformism = 10.0,
        N_h = 0.5, N_theta = 0.25, N_h_spouse = 0.5,
    )
    pm = GN.AgentPayoffParams{GN.Male}(
        wage_self = 1.0, wage_spouse = 1.0, alpha = 0.5, conformism = 10.0,
        N_h = 0.5, N_theta = 0.25, N_h_spouse = 0.5,
    )
    theta, hw, hm = GN.bargain_transfer(0.5, 0.5, 0.25, pw, pm, config)
    status_w, status_m = GN.mutual_best_response(0.5, 0.5, 0.25, pw, pm, config)
    @test isequal(theta, 0.25)
    @test isequal(hw, status_w) && isequal(hm, status_m)
    uw_out, um_out = GN.outside_options(0.5, 0.5, pw, pm, config)
    @test isequal(
        GN.nash_product(0.25, hw, hm, uw_out, um_out, pw, pm, config),
        GN.nash_product(0.25, status_w, status_m, uw_out, um_out, pw, pm, config),
    )

    # Constructed case with a strictly better candidate: the norm term
    # alone peaks at the transfer norm 0.25, the search commits near it,
    # and the commit carries the cached solved hours.
    theta, hw, hm = GN.bargain_transfer(0.5, 0.5, 0.0, pw, pm, config)
    status_w, status_m = GN.mutual_best_response(0.5, 0.5, 0.0, pw, pm, config)
    committed = GN.nash_product(theta, hw, hm, uw_out, um_out, pw, pm, config)
    status_payoff = GN.nash_product(0.0, status_w, status_m, uw_out, um_out, pw, pm, config)
    @test isfinite(committed) && committed > status_payoff
    @test abs(theta - 0.25) <= 2.0 * GN.TRANSFER_REFINE_TOL
    @test isequal(hw, 0.5) && isequal(hm, 0.5)
end

# `MDR-0002` chain helpers for the frozen demonstration fixtures: the
# recorded state of `transfer_feasibility_households.toml` was produced
# by the seeded Brent best-response chain and stays reproducible there,
# while the live chain now runs the `MDR-0017` derivative solver. The
# `MDR-0017` envelopes below (defined in
# `test/test_bargaining_equivalence.jl` for the full suite; the guard
# keeps this file runnable on its own) are the validated-equivalence
# tolerances of that record.
if !isdefined(@__MODULE__, :VE_HOURS_ATOL)
    const VE_HOURS_ATOL = 2.0e-3
    const VE_UTIL_ATOL = 1.0e-3
end

"""
    legacy_best_response(obj, h_start)

The seeded `MDR-0002` best-response expression (the bitwise fallback of
`MDR-0017`).
"""
legacy_best_response(obj, h_start::Float64)::Float64 =
    GN.maximize_1d(obj, 0.0, 1.0, h_start, GN.BEST_RESPONSE_WINDOW, GN.BEST_RESPONSE_TOL)

"""
    legacy_mutual_best_response(hw_init, hm_init, theta, pw, pm, config)

The `MDR-0002` alternation of `mutual_best_response` with the seeded
best responses: the chain that recorded the demonstration fixtures.
"""
function legacy_mutual_best_response(
        hw_init::Float64, hm_init::Float64, theta::Float64,
        pw::GN.AgentPayoffParams, pm::GN.AgentPayoffParams, config::GN.UtilityConfig;
        eps = 1.0e-3, max_sweeps = 100,
    )
    hw = clamp(hw_init, 0.0, 1.0)
    hm = clamp(hm_init, 0.0, 1.0)
    for _ in 1:max_sweeps
        hw_new = legacy_best_response(GN.BestResponseObjective(theta, hm, pw, config), hw)
        isfinite(hw_new) || (hw_new = hw)
        hm_new = legacy_best_response(GN.BestResponseObjective(theta, hw_new, pm, config), hm)
        isfinite(hm_new) || (hm_new = hm)
        change = abs(hw_new - hw) + abs(hm_new - hm)
        hw = clamp(hw_new, 0, 1)
        hm = clamp(hm_new, 0, 1)
        change <= eps && break
    end
    return (hw, hm)
end

@testset "transfer search: demonstrated benchmark households" begin
    # Frozen regression fixtures of the three seed-1 benchmark
    # households whose strictly positive near-zero payoffs the
    # pre-`MDR-0012` search missed (`benchmark/transfer_search_diagnosis.md`,
    # `test/fixtures/transfer_feasibility_households.toml`).
    #
    # Under `MDR-0017` the specialized derivative labour solver moves
    # the objective of these households by the validated-equivalence
    # envelope (measured here: hours <= 4.8e-5, outside options <=
    # 4.4e-5), which is ABOVE the demonstrated near-zero gains (payoffs
    # 1.2e-10 to 1.5e-8): their feasible bands are features of the
    # seeded solver's discrete fixed points and their tiny gain signs
    # can flip under the continuous solve (the recorded divergence of
    # `MDR-0017`). The fixture is therefore pinned against the
    # `MDR-0002` chain that recorded it (first block, `veq` = the
    # `MDR-0013` ulp envelope) and against the live chain within the
    # explicit `MDR-0017` envelopes plus the `MDR-0016` search
    # contract; the search-quality machinery itself is pinned on
    # synthetic bands in this file and in `test/test_transfer_local_search.jl`.
    fixture = TOML.parsefile(
        joinpath(@__DIR__, "fixtures", "transfer_feasibility_households.toml")
    )
    @test length(fixture["household"]) == 3
    @testset "household $(h["id"])" for h in fixture["household"]
        config = GN.UtilityConfig(func = GN.CES(beta = t64(h["beta"])))
        pw = GN.AgentPayoffParams{GN.Female}(
            wage_self = t64(h["pw_wage_self"]),
            wage_spouse = t64(h["pw_wage_spouse"]),
            alpha = t64(h["pw_alpha"]),
            conformism = t64(h["pw_conformism"]),
            N_h = t64(h["pw_N_h"]),
            N_theta = t64(h["pw_N_theta"]),
            N_h_spouse = t64(h["pw_N_h_spouse"]),

        )
        pm = GN.AgentPayoffParams{GN.Male}(
            wage_self = t64(h["pm_wage_self"]),
            wage_spouse = t64(h["pm_wage_spouse"]),
            alpha = t64(h["pm_alpha"]),
            conformism = t64(h["pm_conformism"]),
            N_h = t64(h["pm_N_h"]),
            N_theta = t64(h["pm_N_theta"]),
            N_h_spouse = t64(h["pm_N_h_spouse"]),

        )
        hw_init, hm_init, theta_init = t64(h["hw_init"]), t64(h["hm_init"]), t64(h["theta_init"])
        demo_theta, demo_payoff = t64(h["demo_theta"]), t64(h["demo_payoff"])
        theta0 = clamp(theta_init, -1.0, 1.0)

        # The recorded state on the `MDR-0002` chain: outside options,
        # status hours, and the demonstrated payoff re-derived exactly
        # as the fixture recorded them.
        leg_hw0, leg_hm0 = legacy_mutual_best_response(hw_init, hm_init, 0.0, pw, pm, config)
        leg_uw = GN.individual_utility(leg_hw0, leg_hm0, 0.0, pw, config)
        leg_um = GN.individual_utility(leg_hm0, leg_hw0, 0.0, pm, config)
        @test veq(leg_uw, t64(h["uw_out"]))
        @test veq(leg_um, t64(h["um_out"]))
        leg_hws, leg_hms =
            legacy_mutual_best_response(hw_init, hm_init, theta0, pw, pm, config)
        @test veq(leg_hws, t64(h["hw_status"]))
        @test veq(leg_hms, t64(h["hm_status"]))
        leg_demo = legacy_mutual_best_response(leg_hws, leg_hms, demo_theta, pw, pm, config)
        leg_payoff = GN.nash_product(
            demo_theta, leg_demo[1], leg_demo[2], leg_uw, leg_um, pw, pm, config
        )
        @test veq(leg_payoff, demo_payoff)
        @test leg_payoff > 0.0
        if haskey(h, "demo2_theta")
            demo2_theta = t64(h["demo2_theta"])
            leg_demo2 = legacy_mutual_best_response(leg_hws, leg_hms, demo2_theta, pw, pm, config)
            leg_payoff2 = GN.nash_product(
                demo2_theta, leg_demo2[1], leg_demo2[2], leg_uw, leg_um, pw, pm, config
            )
            @test veq(leg_payoff2, t64(h["demo2_payoff"]))
            @test leg_payoff2 > 0.0
        end

        # The live chain within the `MDR-0017` validated-equivalence
        # envelopes.
        uw_out, um_out = GN.outside_options(hw_init, hm_init, pw, pm, config)
        @test abs(uw_out - t64(h["uw_out"])) <= VE_UTIL_ATOL
        @test abs(um_out - t64(h["um_out"])) <= VE_UTIL_ATOL
        hw_status, hm_status = GN.mutual_best_response(hw_init, hm_init, theta0, pw, pm, config)
        @test abs(hw_status - t64(h["hw_status"])) <= VE_HOURS_ATOL
        @test abs(hm_status - t64(h["hm_status"])) <= VE_HOURS_ATOL

        # The `MDR-0016` result contract on the live chain: a nonzero
        # commit is finite and at least the status quo, a fallback keeps
        # the status-quo transfer and its cached hours.
        theta, hw, hm = GN.bargain_transfer(hw_init, hm_init, theta_init, pw, pm, config)
        @test isfinite(theta) && -1.0 <= theta <= 1.0
        committed = GN.nash_product(theta, hw, hm, uw_out, um_out, pw, pm, config)
        status_payoff = GN.nash_product(theta0, hw_status, hm_status, uw_out, um_out, pw, pm, config)
        if isequal(theta, theta0)
            @test isequal(hw, hw_status) && isequal(hm, hm_status)
        else
            @test isfinite(committed) && committed > status_payoff
        end
    end
end
