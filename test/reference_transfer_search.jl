# Frozen pre-`ADR-0017` staged transfer search of `bargain_transfer`
# (`MDR-0012` as implemented by `ADR-0016`): the per-call
# `Dict{Float64,TransferObjectiveValue}` evaluation cache, the Stage A
# enumeration, and the Stage B refinement and candidate selection
# exactly as they stood before the interval prefilter and the
# task-owned `TransferSearchScratch` storage were added. This file is
# the bitwise-identity oracle of `test/test_transfer_search_identity.jl`:
# the full evaluation sequence (ordered keys, cached payoffs including
# every `-Inf` sentinel, Stage B weak maxima, plateaus, brackets, and
# probes) and the commit-or-fallback decision of the live search must
# be `isequal` to this copy on every case. It must never be
# "optimized", refactored, or otherwise edited; retire it only under a
# recorded decision that also retires the oracle.
#
# Frozen (copied verbatim from the pre-`ADR-0017`
# `src/systems/household_bargaining.jl`, modulo `_reference` renames,
# `GN.` qualification, this header, and docstrings):
# `_transfer_eval!` (`transfer_eval_reference`), `_transfer_better`
# (`transfer_better_reference`), `_transfer_search!`
# (`transfer_search_reference!`), and `bargain_transfer`
# (`bargain_transfer_search_reference`). Shared with the package and
# NOT frozen here (unchanged by `ADR-0017` and pinned by the bitwise
# objective fixtures of `test/test_bargaining_equivalence.jl`):
# `TransferObjectiveValue`, `mutual_best_response`, `outside_options`,
# `nash_product`, `equilibrium_payoff`, `individual_utility`,
# `maximize_1d`, `_objective_prunable`, and the `TRANSFER_*` solver
# parameters (local value copies below pin those too). Helper file like
# `test/reference_bargaining.jl`: not included in `test/runtests.jl`; a
# test file `include`s it exactly once. See `MDR-0012`, `ADR-0016`, and
# `ADR-0017`.

using GenderNorms: AgentPayoffParams, TransferObjectiveValue, UtilityConfig

# Local value copies of the `MDR-0012` solver parameters of
# `src/systems/household_bargaining.jl`; the identity tests compare
# against these, so any drift of the live constants shows up as a
# divergence.
const TRANSFER_COARSE_STEP_REFERENCE = 1.0e-3
const TRANSFER_LOCAL_STEP_REFERENCE = 1.0e-4
const TRANSFER_LOCAL_STEPS_REFERENCE = 200
const TRANSFER_REFINE_TOL_REFERENCE = 1.0e-5

"""
    transfer_eval_reference(cache::Dict{Float64,TransferObjectiveValue}, evaluate!::F, theta::Float64) where {F}

Frozen copy of `_transfer_eval!` (pre-`ADR-0017`); see the file
header: cached evaluation of the staged transfer search at the exact
transfer `theta`.
"""
function transfer_eval_reference(
        cache::Dict{Float64, TransferObjectiveValue}, evaluate!::F, theta::Float64
    )::TransferObjectiveValue where {F}
    haskey(cache, theta) && return cache[theta]
    entry = evaluate!(theta)
    cache[theta] = entry
    return entry
end

"""
    transfer_better_reference(theta::Float64, payoff::Float64, best_theta::Float64, best_payoff::Float64, theta0::Float64) -> Bool

Frozen copy of `_transfer_better` (pre-`ADR-0017`); see the file
header: the candidate tie rule of `MDR-0012` (largest payoff, then
smallest `abs(theta - theta0)`, then smallest `theta`).
"""
function transfer_better_reference(
        theta::Float64, payoff::Float64, best_theta::Float64, best_payoff::Float64, theta0::Float64
    )::Bool
    payoff != best_payoff && return payoff > best_payoff
    distance = abs(theta - theta0)
    best_distance = abs(best_theta - theta0)
    distance != best_distance && return distance < best_distance
    return theta < best_theta
end

"""
    transfer_search_reference!(cache::Dict{Float64,TransferObjectiveValue}, evaluate!::F, theta0::Float64, tol::Float64) -> Float64 where {F}

Frozen copy of `_transfer_search!` (pre-`ADR-0017`); see the file
header: the staged search of `MDR-0012` over the caller-owned cache,
without any interval prefilter.
"""
function transfer_search_reference!(
        cache::Dict{Float64, TransferObjectiveValue}, evaluate!::F,
        theta0::Float64, tol::Float64
    )::Float64 where {F}
    # Stage A: the explicit evaluation set of `MDR-0012`, anchors
    # first, then the anchor neighbourhoods, then the coarse grid; the
    # cache deduplicates overlaps (theta0 often coincides with an anchor
    # or a grid point).
    transfer_eval_reference(cache, evaluate!, -1.0)
    transfer_eval_reference(cache, evaluate!, 0.0)
    transfer_eval_reference(cache, evaluate!, theta0)
    transfer_eval_reference(cache, evaluate!, 1.0)
    for anchor in (0.0, theta0)
        for k in 1:TRANSFER_LOCAL_STEPS_REFERENCE
            transfer_eval_reference(
                cache, evaluate!,
                clamp(anchor + k * TRANSFER_LOCAL_STEP_REFERENCE, -1.0, 1.0)
            )
            transfer_eval_reference(
                cache, evaluate!,
                clamp(anchor - k * TRANSFER_LOCAL_STEP_REFERENCE, -1.0, 1.0)
            )
        end
    end
    for theta in -1.0:TRANSFER_COARSE_STEP_REFERENCE:1.0
        transfer_eval_reference(cache, evaluate!, theta)
    end
    # Stage B: weak local maxima of the sampled payoffs, one bounded
    # refinement per equal-payoff plateau (see `MDR-0012`).
    thetas = sort!(collect(keys(cache)))
    n = length(thetas)
    maxima = Int[]
    for i in 1:n
        payoff = cache[thetas[i]].payoff
        isfinite(payoff) || continue
        i == 1 || payoff >= cache[thetas[i - 1]].payoff || continue
        i == n || payoff >= cache[thetas[i + 1]].payoff || continue
        push!(maxima, i)
    end
    objective(theta) = transfer_eval_reference(cache, evaluate!, theta).payoff
    plateau_start = 1
    while plateau_start <= length(maxima)
        plateau_end = plateau_start
        while plateau_end < length(maxima) &&
                maxima[plateau_end + 1] == maxima[plateau_end] + 1 &&
                cache[thetas[maxima[plateau_end + 1]]].payoff ==
                cache[thetas[maxima[plateau_start]]].payoff
            plateau_end += 1
        end
        # The plateau member closest to the status quo refines; equal
        # payoffs make the tie rule apply the distance-then-theta rule
        # of `MDR-0012`.
        refined = maxima[plateau_start]
        for mi in (plateau_start + 1):plateau_end
            m = maxima[mi]
            if transfer_better_reference(
                    thetas[m], cache[thetas[m]].payoff,
                    thetas[refined], cache[thetas[refined]].payoff, theta0,
                )
                refined = m
            end
        end
        lo = clamp(refined == 1 ? thetas[refined] : thetas[refined - 1], -1.0, 1.0)
        hi = clamp(refined == n ? thetas[refined] : thetas[refined + 1], -1.0, 1.0)
        GenderNorms.maximize_1d(objective, lo, hi, tol)
        plateau_start = plateau_end + 1
    end
    # Candidate selection over every cached finite payoff with the tie
    # rule of `MDR-0012` (the empty best `(NaN, -Inf)` loses to the
    # first finite candidate).
    best_theta = NaN
    best_payoff = -Inf
    for theta in keys(cache)
        entry = cache[theta]
        isfinite(entry.payoff) || continue
        if transfer_better_reference(theta, entry.payoff, best_theta, best_payoff, theta0)
            best_theta = theta
            best_payoff = entry.payoff
        end
    end
    return best_theta
end

"""
    bargain_transfer_search_reference(hw_init::Float64, hm_init::Float64, theta_init::Float64, pw::AgentPayoffParams, pm::AgentPayoffParams, config::UtilityConfig; tol::Float64 = TRANSFER_REFINE_TOL_REFERENCE)

Frozen copy of `bargain_transfer` (pre-`ADR-0017`); see the file
header: the full staged search of `MDR-0012` with the per-call cache
and the pointwise certificate only. Returns `(theta, hw, hm)`.
"""
function bargain_transfer_search_reference(
        hw_init::Float64, hm_init::Float64, theta_init::Float64,
        pw::AgentPayoffParams, pm::AgentPayoffParams, config::UtilityConfig;
        tol::Float64 = TRANSFER_REFINE_TOL_REFERENCE
    )
    theta0 = clamp(theta_init, -1.0, 1.0)
    hw_out, hm_out = GenderNorms.mutual_best_response(hw_init, hm_init, 0.0, pw, pm, config)
    uw_out = GenderNorms.individual_utility(hw_out, hm_out, 0.0, pw, config)
    um_out = GenderNorms.individual_utility(hm_out, hw_out, 0.0, pm, config)
    hw_status, hm_status = theta0 === 0.0 ? (hw_out, hm_out) :
        GenderNorms.mutual_best_response(hw_init, hm_init, theta0, pw, pm, config)
    status_payoff = GenderNorms.nash_product(
        theta0, hw_status, hm_status, uw_out, um_out, pw, pm, config
    )
    if !isfinite(uw_out) || !isfinite(um_out)
        return theta0, hw_status, hm_status
    end
    function evaluate_transfer(theta::Float64)::TransferObjectiveValue
        if GenderNorms._objective_prunable(theta, uw_out, um_out, pw, pm, config)
            return TransferObjectiveValue(NaN, NaN, -Inf, NaN, NaN)
        end
        payoff, hw, hm = GenderNorms.equilibrium_payoff(
            theta, hw_status, hm_status, uw_out, um_out, pw, pm, config
        )
        gain_w = GenderNorms.individual_utility(hw, hm, theta, pw, config) - uw_out
        gain_m = GenderNorms.individual_utility(hm, hw, theta, pm, config) - um_out
        return TransferObjectiveValue(gain_w, gain_m, payoff, hw, hm)
    end
    cache = Dict{Float64, TransferObjectiveValue}()
    gain_w0 = GenderNorms.individual_utility(hw_status, hm_status, theta0, pw, config) - uw_out
    gain_m0 = GenderNorms.individual_utility(hm_status, hw_status, theta0, pm, config) - um_out
    cache[theta0] = TransferObjectiveValue(gain_w0, gain_m0, status_payoff, hw_status, hm_status)
    best_theta = transfer_search_reference!(cache, evaluate_transfer, theta0, tol)
    if isfinite(best_theta)
        best = cache[best_theta]
        if best.payoff > status_payoff
            return best_theta, best.hw, best.hm
        end
    end
    return theta0, hw_status, hm_status
end
