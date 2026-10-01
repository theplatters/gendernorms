# Contract tests for the household bargaining solver against the frozen
# pre-optimization fixtures of `test/fixtures/bargaining_baseline.toml`
# and the frozen reference copy `test/reference_bargaining.jl` (included
# here exactly once). The fixture records every Float64 as a quoted Julia
# `repr` string; exact comparisons use `isequal`, so NaN matches NaN and
# -0.0 does not match 0.0.
#
# What is asserted (see `MDR-0012`, which supersedes `MDR-0005`,
# `MDR-0013`, which supersedes the objective-chain exactness of
# `MDR-0012`, and `MDR-0017`, which supersedes the labour solver of
# `MDR-0002`):
# - Objective-level equivalence of the solver chain: `mutual_best_response`,
#   `outside_options`, `nash_product`, `equilibrium_payoff`, and
#   `maximize_1d`. Three comparison classes apply. (1) Exact (`isequal`)
#   where neither the `MDR-0013` arithmetic nor the `MDR-0017` solver
#   path can have changed anything: every ineligible case keeps the
#   bitwise seeded Brent fallback. (2) The `MDR-0013` validated-
#   equivalence ulp envelope (`veq`) for `CES` `beta == 0.5` arithmetic
#   alone. (3) The `MDR-0017` validated-equivalence tolerances where the
#   specialized derivative best-response solver may have run: hours
#   within `VE_HOURS_ATOL` per partner (two `eps = 1.0e-3` sweep
#   budgets; measured worst case over the 200 fixture cases 9.6e-5),
#   outside-option utilities and gains within `VE_UTIL_ATOL` (absolute)
#   or `VE_UTIL_RTOL` (relative; measured utilities 2.4e-4, gains
#   1.8e-4), the status Nash
#   payoff within `VE_PAYOFF_ATOL` (measured
#   1.8e-5), the measured two-sided own-utility envelope at the solved
#   hours (`VE_OBJ_RTOL`; see the solver battery for the tier accuracy
#   certificates behind it), and
#   identical feasible/non-finite classifications and branch labels
#   (measured 0 flips). The frozen reference stays bitwise against the
#   fixtures (it IS the old arithmetic and the old solver).
# - `bargain_transfer` follows the bounded local contract of
#   `MDR-0016` / `ADR-0021`: result-validity invariants (bounds,
#   strict-improvement commit, exact status fallback), bit-identical
#   repeated calls, and an integration replay of the search over the
#   same inputs (live versus live, unaffected by `MDR-0013`/`MDR-0017`).
#   The replay drives the production driver itself, so it verifies
#   integration and ranking, not the search schedule; the schedule is
#   pinned independently in `test/test_transfer_local_search.jl`.
# - The `maximize_1d` diagnostics (the unseeded-Brent `best_theta` and
#   `best_payoff` over the live chain) are re-derived exactly through the
#   unchanged `maximize_1d`; against the fixture they stay exact where
#   the objective they see is unchanged and are compared by finiteness
#   plus the jaggedness tolerance `VE_MAXIMIZER_PAYOFF_ATOL` where the
#   `MDR-0017` solver moved the objective (the unseeded-Brent maximizer
#   is jagged and may move to a neighbouring noise spike; measured
#   payoff delta 7.3e-5, theta delta 7.2e-3).
# - Baseline comparison statistics against the frozen
#   `bargain_transfer_reference` are collected per case; the old search
#   can in principle find narrow peaks the sampled grid misses (the
#   objective is jagged at the 1e-4 scale through the discrete labour
#   solver), so universal dominance is NOT asserted. The counts are
#   reported in the test log; the old-versus-new outcome assessment
#   belongs to the follow-up validation package (`TASK-0014`).
#
# What is deferred: the recorded `bt_*`/`best_*` fixture fields describe
# the pre-`MDR-0012` unseeded Brent search and stay as baseline data;
# they are re-derived exactly through the frozen reference and only
# approximately through the live chain (the unseeded-Brent maximizer is
# jagged and moved in 8 of 200 cases under `MDR-0013` and further under
# `MDR-0017`). The recorded trajectories describe pre-`MDR-0012` model
# results and are kept as baseline data only (run-level invariants
# below; trajectory deltas belong to the follow-up validation package,
# `TASK-0014`).

using Ark
using GenderNorms
using Test
using TOML

const GN = GenderNorms

include("reference_bargaining.jl")

const BASELINE_PATH = joinpath(@__DIR__, "fixtures", "bargaining_baseline.toml")
const BASELINE = TOML.parsefile(BASELINE_PATH)
const BASELINE_SOLVER = BASELINE["solver"]
const BASELINE_TRAJECTORY = BASELINE["trajectory"]
const SOLVER_CASES = BASELINE_SOLVER["case"]
const TRAJECTORY_RUNS = BASELINE_TRAJECTORY["run"]

"""
    f64(text::AbstractString)::Float64

Read one fixture float: the fixture encodes every `Float64` as a quoted
Julia `repr` string, and `parse` round-trips it exactly.
"""
f64(text::AbstractString)::Float64 = parse(Float64, text)

"""
    f64s(values)::Vector{Float64}

Read one fixture float array elementwise with `f64`.
"""
f64s(values)::Vector{Float64} = [f64(v) for v in values]

"""
    isequal_all(a, b)::Bool

Elementwise `isequal` over two equally long sequences of `Float64`:
NaN matches NaN and -0.0 does not match 0.0, mirroring the fixture
comparison contract.
"""
isequal_all(a, b)::Bool =
    length(a) == length(b) && all(isequal(x, y) for (x, y) in zip(a, b))

# Validated-equivalence comparison of `MDR-0013`: the CES `beta == 0.5`
# sqrt/square `material` specialization moves computed values by a few
# ulps (measured envelope over the fixture and workload samples,
# `benchmark/solver_equivalence_validation.md`: utility deltas <=
# 1.2e-15 absolute, solver-hour deltas <= 1.0e-12, payoff deltas <=
# 3e-15). The tolerances below are that envelope with a 100x margin;
# every other spec and beta is compared bitwise (`arith_changed` is
# false there and `veq` degenerates to `isequal`).
const VE_ATOL = 1.0e-10
const VE_RTOL = 1.0e-9

# Validated-equivalence tolerances of `MDR-0017` where the specialized
# derivative best-response solver may have run (see the file header).
# Measured worst-case deltas over the 200 fixture cases (the timing
# side is in `benchmark/derivative_solver_validation.md`):
# solver hours 9.6e-5 per partner, outside-option utilities 2.4e-4,
# gains 1.8e-4, the status Nash payoff 1.8e-5, and the unseeded-Brent
# maximizer payoff 7.3e-5; each tolerance below is that envelope with
# headroom, and the hours budget of two `eps = 1.0e-3` sweeps is the
# `mutual_best_response` contract.
const VE_HOURS_ATOL = 2.0e-3
const VE_UTIL_ATOL = 1.0e-3
const VE_UTIL_RTOL = 1.0e-3
const VE_PAYOFF_ATOL = 1.0e-4
const VE_PAYOFF_RTOL = 1.0e-3
const VE_MAXIMIZER_PAYOFF_ATOL = 5.0e-4

# Measured two-sided own-value envelope `|U(new) - U(legacy)|` of the
# two-tier solver against the legacy seeded search at the solved hours,
# relative at the comparison scale (the `MDR-0017` non-degradation
# contract: tier accuracy certificates plus this envelope instead of
# pointwise value dominance, since both returns sit within the shared
# `BEST_RESPONSE_TOL` quality window of the optimum and can differ
# inside it). Measured worst case over the 200 fixture cases at their
# frozen reference state 6.8e-7 and over the 31,855-case envelope grid
# of `MDR-0017` 1.85e-4 (the window's value variation at sharp peaks);
# the tolerance is that envelope with headroom, and the outlier draws
# are reported with their parameters in `MDR-0017` and
# `benchmark/derivative_solver_validation.md`.
const VE_OBJ_RTOL = 5.0e-4

"""
    arith_changed(config)::Bool

`true` exactly for the utility specs whose computed arithmetic changed
under `MDR-0013` (`CES` with `beta == 0.5`, the sqrt/square `material`
specialization); every other spec is bitwise identical to the frozen
reference.
"""
arith_changed(config)::Bool =
    config.func isa GN.CES && config.func.beta == 0.5

"""
    veq(a::Float64, b::Float64)::Bool

Validated-equivalence float comparison of `MDR-0013`: `isequal` (NaN
matches NaN, signed zeros distinct) when both values are non-finite,
otherwise `isapprox` with the `VE_ATOL`/`VE_RTOL` envelope. Exact
(`isequal`) for specs where the arithmetic is unchanged.
"""
veq(a::Float64, b::Float64)::Bool =
    (isfinite(a) && isfinite(b)) ? isapprox(a, b; atol=VE_ATOL, rtol=VE_RTOL) : isequal(a, b)

"""
    solver_relaxed(config, theta0::Float64, pw, pm)::Bool

Conservative static predicate that the `MDR-0017` specialized derivative
solver may have contributed to one fixture case: at least one partner's
prepared objective passes `_derivative_applicable` for some transfer and
spouse-hours combination the case's solves can use. Only when this is
`false` for both partners do the live outputs stay bitwise against the
frozen reference and fixture (the bitwise `MDR-0002` fallback); the
probe points over `theta` and `h_spouse` are a superset of the solves'
inputs, so the predicate never under-reports a changed chain.
"""
function solver_relaxed(config, theta0::Float64, pw, pm)::Bool
    for p in (pw, pm), theta in (theta0, 0.0, 1.0, -1.0), h_spouse in (0.0, 0.5, 1.0)
        obj = GN.BestResponseObjective(theta, h_spouse, p, config)
        GN._derivative_applicable(obj, 0.3) && return true
    end
    return false
end

"""
    equiv(a::Float64, b::Float64, atol::Float64, config, relaxed::Bool; rtol = 0.0)::Bool

Three-class validated-equivalence comparison of one recorded `Float64`
(see the file header and `MDR-0017`): exact (`isequal`) when neither the
`MDR-0013` arithmetic nor the `MDR-0017` solver path can have changed
the value, `veq` (the `MDR-0013` ulp envelope) when only the `CES`
`beta == 0.5` arithmetic applies, and the explicit `MDR-0017` envelope
`abs(a - b) <= atol + rtol * max(abs(a), abs(b))` (with `isequal` on
non-finite pairs) when the derivative solver may have run. The
per-quantity `atol`/`rtol` values are the explicit `MDR-0017`
tolerances above, not one blanket envelope.
"""
function equiv(
    a::Float64, b::Float64, atol::Float64, config, relaxed::Bool; rtol::Float64=0.0
)::Bool
    if relaxed
        return (isfinite(a) && isfinite(b)) ?
            abs(a - b) <= atol + rtol * max(abs(a), abs(b)) : isequal(a, b)
    end
    arith_changed(config) && return veq(a, b)
    return isequal(a, b)
end

"""
    payoff_equiv(a::Float64, b::Float64, config, relaxed::Bool)::Bool

Payoff comparison of `MDR-0017` on boundary draws: the scale-aware
`VE_PAYOFF_ATOL` plus `VE_PAYOFF_RTOL` envelope (the Nash product is
quadratic in gains that scale with the drawn wages, so the absolute
delta grows with the payoff scale while the relative delta stays at the
hours-equivalence level), extended by the documented zero-gain knife
edge - a gain at the rounding scale of its utility difference can flip
sign between the two chains, mapping a payoff of `0.0` or a tiny
positive value onto the exact `-Inf` of a negative gain (and back). Such
a pair is accepted when the finite side is within `VE_PAYOFF_ATOL` of
zero; every other pair must satisfy the envelope. On bitwise
(ineligible) draws the comparison is exact.
"""
function payoff_equiv(a::Float64, b::Float64, config, relaxed::Bool)::Bool
    relaxed || return (arith_changed(config) ? veq(a, b) : isequal(a, b))
    if isfinite(a) && isfinite(b)
        return abs(a - b) <= VE_PAYOFF_ATOL + VE_PAYOFF_RTOL * max(abs(a), abs(b))
    end
    isequal(a, b) && return true
    (isfinite(a) && abs(a) <= VE_PAYOFF_ATOL && b == -Inf) && return true
    return isfinite(b) && abs(b) <= VE_PAYOFF_ATOL && a == -Inf
end

"""
    fixture_config(utility::AbstractString, beta::Float64)::GN.UtilityConfig

Utility configuration of one solver case from its recorded spec strings,
with the package-default weights (the fixture records only the spec).
"""
function fixture_config(utility::AbstractString, beta::Float64)::GN.UtilityConfig
    utility == "additive" && return GN.UtilityConfig(func=GN.Additive())
    utility == "ces" && return GN.UtilityConfig(func=GN.CES(beta=beta))
    utility == "multiplicative" && return GN.UtilityConfig(func=GN.Multiplicative())
    utility == "multiplicative_weighted" &&
        return GN.UtilityConfig(func=GN.MultiplicativeWeighted())
    error("unknown utility spec $(repr(utility))")
end

"""
    replay_search(hw_init, hm_init, theta_init, pw, pm, config)

Integration replay of the bounded local search of `bargain_transfer`
(`MDR-0016`, `ADR-0021`): rebuilds the status-quo evaluation and the
cached evaluation function exactly as `bargain_transfer` does and
drives the production `GN._transfer_local_search!` with a fresh cache,
so the test can inspect the full candidate set. This is an integration
replay of the evaluation chain driving the production driver, not an
independent oracle for schedule correctness: a driver regression would
move both sides identically, so these assertions verify
integration and ranking (result-validity invariants, commit and tie
rules, cache consistency). The search schedule (Stage A/Stage B/Stage C
probe order, brackets, and budgets) is pinned independently in
`test/test_transfer_local_search.jl`, whose `local_stage_a` /
`local_bracket` enumeration is built from its own literal constants
without calling the driver's enumeration helpers. Mirrors the
evaluation of `bargain_transfer`, including the `MDR-0016` guidance
semantics: a certified probe keeps the exact `-Inf` payoff and stores
the partner bounds minus the outside options as its guidance gains,
and the search runs at the production normalization scales
`max(abs(outside option), 1.0)`. When the two diverge, the contract
tests fail. Returns
`(cache, theta0, status_payoff, hw_status, hm_status)`.
"""
function replay_search(
    hw_init::Float64, hm_init::Float64, theta_init::Float64,
    pw::GN.AgentPayoffParams, pm::GN.AgentPayoffParams, config::GN.UtilityConfig,
)
    theta0 = clamp(theta_init, -1.0, 1.0)
    hw_out, hm_out = GN.mutual_best_response(hw_init, hm_init, 0.0, pw, pm, config)
    uw_out = GN.individual_utility(hw_out, hm_out, 0.0, pw, config)
    um_out = GN.individual_utility(hm_out, hw_out, 0.0, pm, config)
    hw_status, hm_status = theta0 === 0.0 ? (hw_out, hm_out) :
        GN.mutual_best_response(hw_init, hm_init, theta0, pw, pm, config)
    status_payoff =
        GN.nash_product(theta0, hw_status, hm_status, uw_out, um_out, pw, pm, config)
    function evaluate(theta::Float64)
        bound_w = GN._payoff_upper_bound(theta, pw, config)
        bound_m = GN._payoff_upper_bound(theta, pm, config)
        if (isfinite(bound_w) && bound_w * (1.0 + GN.OBJECTIVE_CERT_MARGIN) < uw_out) ||
            (isfinite(bound_m) && bound_m * (1.0 + GN.OBJECTIVE_CERT_MARGIN) < um_out)
            return GN.TransferObjectiveValue(
                NaN, NaN, -Inf, NaN, NaN, bound_w - uw_out, bound_m - um_out
            )
        end
        hw, hm = GN.mutual_best_response(hw_status, hm_status, theta, pw, pm, config)
        gain_w, gain_m = GN._transfer_gains(theta, hw, hm, uw_out, um_out, pw, pm, config)
        return GN.TransferObjectiveValue(gain_w, gain_m, GN._nash_from_gains(gain_w, gain_m), hw, hm)
    end
    cache = Dict{Float64,GN.TransferObjectiveValue}()
    gain_w0, gain_m0 =
        GN._transfer_gains(theta0, hw_status, hm_status, uw_out, um_out, pw, pm, config)
    cache[theta0] = GN.TransferObjectiveValue(gain_w0, gain_m0, status_payoff, hw_status, hm_status)
    GN._transfer_local_search!(
        GN.TransferSearchScratch(cache), evaluate, theta0, GN.TRANSFER_REFINE_TOL;
        scale_w=max(abs(uw_out), 1.0), scale_m=max(abs(um_out), 1.0),
    )
    return cache, theta0, status_payoff, hw_status, hm_status
end

"""
    replay_search_best(cache, theta0)

Best cached candidate of a `replay_search` cache under the `MDR-0012`
tie rule, computed independently of `GN._transfer_search!`: the largest
finite payoff, exact ties broken by the smallest `abs(theta - theta0)`,
then the smallest `theta`. Returns `NaN` when no payoff is finite.
"""
function replay_search_best(
    cache::Dict{Float64,GN.TransferObjectiveValue}, theta0::Float64
)::Float64
    best_theta = NaN
    best_payoff = -Inf
    for theta in keys(cache)
        entry = cache[theta]
        isfinite(entry.payoff) || continue
        if entry.payoff != best_payoff
            if entry.payoff > best_payoff
                best_theta, best_payoff = theta, entry.payoff
            end
            continue
        end
        distance = abs(theta - theta0)
        best_distance = abs(best_theta - theta0)
        if distance < best_distance || (distance == best_distance && theta < best_theta)
            best_theta, best_payoff = theta, entry.payoff
        end
    end
    return best_theta
end

@testset "bargaining equivalence: solver fixture replay" begin
    old_commits = 0
    new_matches_old = 0
    new_below_old = 0
    new_commits = 0
    new_only_commits = 0
    @testset "solver case $(case["id"]): $(case["label"])" for case in SOLVER_CASES
        config = fixture_config(case["utility"], f64(get(case, "beta", "0.5")))
        pw = GN.AgentPayoffParams(
            wage_self=f64(case["pw_wage_self"]),
            wage_spouse=f64(case["pw_wage_spouse"]),
            alpha=f64(case["pw_alpha"]),
            conformism=f64(case["pw_conformism"]),
            N_h=f64(case["pw_N_h"]),
            N_theta=f64(case["pw_N_theta"]),
            N_h_spouse=f64(case["pw_N_h_spouse"]),
            is_woman=true,
        )
        pm = GN.AgentPayoffParams(
            wage_self=f64(case["pm_wage_self"]),
            wage_spouse=f64(case["pm_wage_spouse"]),
            alpha=f64(case["pm_alpha"]),
            conformism=f64(case["pm_conformism"]),
            N_h=f64(case["pm_N_h"]),
            N_theta=f64(case["pm_N_theta"]),
            N_h_spouse=f64(case["pm_N_h_spouse"]),
            is_woman=false,
        )
        theta_init = f64(case["theta_init"])
        hw_init = f64(case["hw_init"])
        hm_init = f64(case["hm_init"])
        theta0 = clamp(theta_init, -1.0, 1.0)

        # Live objective-level chain and the recorded diagnostics
        # re-derived from it exactly as the fixture generator recorded
        # them. `TRANSFER_TOL` is the frozen reference's local copy of
        # the old search tolerance (the package folded it into
        # `TRANSFER_COARSE_STEP` under `MDR-0012`); `maximize_1d` is
        # unchanged, so the recorded maximizer is still bitwise.
        mbr_hw, mbr_hm =
            GN.mutual_best_response(hw_init, hm_init, theta0, pw, pm, config)
        uw_out, um_out = GN.outside_options(hw_init, hm_init, pw, pm, config)
        status_payoff =
            GN.nash_product(theta0, mbr_hw, mbr_hm, uw_out, um_out, pw, pm, config)
        objective(theta) =
            first(GN.equilibrium_payoff(theta, mbr_hw, mbr_hm, uw_out, um_out, pw, pm, config))
        best_theta = GN.maximize_1d(objective, -1.0, 1.0, TRANSFER_TOL)
        if isfinite(best_theta)
            best_payoff, best_hw, best_hm =
                GN.equilibrium_payoff(best_theta, mbr_hw, mbr_hm, uw_out, um_out, pw, pm, config)
        else
            best_payoff, best_hw, best_hm = NaN, NaN, NaN
        end

        # Frozen reference chain.
        ref_bt_theta, ref_bt_hw, ref_bt_hm =
            bargain_transfer_reference(hw_init, hm_init, theta_init, pw, pm, config)
        ref_mbr_hw, ref_mbr_hm =
            mutual_best_response_reference(hw_init, hm_init, theta0, pw, pm, config)
        ref_uw_out, ref_um_out =
            outside_options_reference(hw_init, hm_init, pw, pm, config)
        ref_status_payoff = nash_product_reference(
            theta0, ref_mbr_hw, ref_mbr_hm, ref_uw_out, ref_um_out, pw, pm, config
        )

        # Live objective-level outputs against the fixture, in the
        # three comparison classes of the file header (see `MDR-0017`):
        # exact where nothing changed, `veq` for `MDR-0013` arithmetic,
        # and the explicit `MDR-0017` tolerances where the derivative
        # solver may have run.
        relaxed = solver_relaxed(config, theta0, pw, pm)
        eq_hours(a, b) = equiv(a, b, VE_HOURS_ATOL, config, relaxed)
        eq_util(a, b) = equiv(a, b, VE_UTIL_ATOL, config, relaxed; rtol=VE_UTIL_RTOL)
        eq_pay(a, b) = equiv(a, b, VE_PAYOFF_ATOL, config, relaxed)
        eq(a, b) = arith_changed(config) ? veq(a, b) : isequal(a, b)
        @test eq_hours(mbr_hw, f64(case["mbr_hw"]))
        @test eq_hours(mbr_hm, f64(case["mbr_hm"]))
        @test eq_util(uw_out, f64(case["uw_out"]))
        @test eq_util(um_out, f64(case["um_out"]))
        @test eq_pay(status_payoff, f64(case["status_payoff"]))
        if arith_changed(config) || relaxed
            # The unseeded-Brent maximizer is jagged and may move to a
            # neighbouring noise spike (8 of 200 cases under `MDR-0013`,
            # payoff deltas <= 2e-15; up to 7.2e-3 in theta and 7.3e-5 in
            # payoff where `MDR-0017` moved the objective), so only its
            # finiteness is a stable claim; the payoff value stays within
            # the jaggedness tolerance.
            @test isfinite(best_theta) == isfinite(f64(case["best_theta"]))
            if relaxed
                @test isequal(best_payoff, f64(case["best_payoff"])) ||
                    (isfinite(best_payoff) && isfinite(f64(case["best_payoff"])) &&
                        abs(best_payoff - f64(case["best_payoff"])) <= VE_MAXIMIZER_PAYOFF_ATOL)
            else
                @test eq(best_payoff, f64(case["best_payoff"]))
            end
        else
            @test isequal(best_theta, f64(case["best_theta"]))
            @test isequal(best_payoff, f64(case["best_payoff"]))
        end

        # Reference outputs against the fixture (bitwise), including the
        # recorded pre-`MDR-0012` `bt_*` results of the frozen chain.
        @test isequal(ref_bt_theta, f64(case["bt_theta"]))
        @test isequal(ref_bt_hw, f64(case["bt_hw"]))
        @test isequal(ref_bt_hm, f64(case["bt_hm"]))
        @test isequal(ref_mbr_hw, f64(case["mbr_hw"]))
        @test isequal(ref_mbr_hm, f64(case["mbr_hm"]))
        @test isequal(ref_uw_out, f64(case["uw_out"]))
        @test isequal(ref_um_out, f64(case["um_out"]))
        @test isequal(ref_status_payoff, f64(case["status_payoff"]))

        # Live objective-level outputs against the frozen reference, in
        # the same three comparison classes as against the fixture.
        @test eq_hours(mbr_hw, ref_mbr_hw)
        @test eq_hours(mbr_hm, ref_mbr_hm)
        @test eq_util(uw_out, ref_uw_out)
        @test eq_util(um_out, ref_um_out)
        @test eq_pay(status_payoff, ref_status_payoff)
        # Own-response value equivalence at the reference's state: the
        # specialized two-tier solve on the reference's own-hours
        # objective and the seeded `MDR-0002` solve both return points
        # within the shared `BEST_RESPONSE_TOL` quality window of the
        # optimum and can differ inside it, so the check is the
        # measured two-sided envelope `VE_OBJ_RTOL` (the tier accuracy
        # certificates are pinned on the full regime grid in
        # `test/test_utility_solver.jl`).
        if relaxed && isfinite(ref_mbr_hw) && isfinite(ref_mbr_hm)
            obj_w = GN.BestResponseObjective(theta0, ref_mbr_hm, pw, config)
            h_new = GN.best_response_1d(obj_w, ref_mbr_hw)
            h_old = GN.maximize_1d(
                obj_w, 0.0, 1.0, ref_mbr_hw, GN.BEST_RESPONSE_WINDOW, GN.BEST_RESPONSE_TOL
            )
            v_new = obj_w(h_new)
            v_old = obj_w(h_old)
            if isfinite(v_new) && isfinite(v_old)
                scale = max(abs(v_new), abs(v_old))
                @test abs(v_new - v_old) <= VE_OBJ_RTOL * scale
            end
        end

        # Recorded branch labels re-derived from the objective-level
        # chain: these describe the frozen pre-`MDR-0012` maximizer and
        # stay valid because `maximize_1d` is unchanged. Finiteness and
        # the improving/fallback label are exact (0 flips measured under
        # `MDR-0013`); the maximizer-value relations hold bitwise only
        # where the arithmetic is unchanged.
        @test case["status_finite"] == isfinite(status_payoff)
        @test case["maximizer_finite"] == isfinite(best_theta)
        improving = isfinite(best_theta) && isfinite(best_payoff) && best_payoff > status_payoff
        @test (improving ? "improving" : "fallback") == case["branch"]
        if arith_changed(config) || relaxed
            # The unseeded-Brent maximizer is jagged and may move to a
            # neighbouring noise spike (under `MDR-0013` ulp jitter and
            # wherever `MDR-0017` moved the objective), so the
            # maximizer-value relations are asserted bitwise against the
            # frozen reference only (above); the fallback relation is
            # exact even here.
            if !improving
                @test isequal(f64(case["bt_theta"]), theta0)
            end
        else
            @test isequal(f64(case["bt_theta"]), improving ? best_theta : theta0)
            @test isequal(f64(case["bt_hw"]), improving ? best_hw : mbr_hw)
            @test isequal(f64(case["bt_hm"]), improving ? best_hm : mbr_hm)
        end

        # `bargain_transfer` under the `MDR-0016` contract: validity
        # invariants and bit-identical repeated calls.
        bt_theta, bt_hw, bt_hm =
            GN.bargain_transfer(hw_init, hm_init, theta_init, pw, pm, config)
        @test isfinite(bt_theta) && -1.0 <= bt_theta <= 1.0
        @test isfinite(bt_hw) && 0.0 <= bt_hw <= 1.0
        @test isfinite(bt_hm) && 0.0 <= bt_hm <= 1.0
        repeat = GN.bargain_transfer(hw_init, hm_init, theta_init, pw, pm, config)
        @test isequal_all((bt_theta, bt_hw, bt_hm), repeat)

        if !isfinite(uw_out) || !isfinite(um_out)
            # Non-finite-outside fast path: the status fallback is
            # returned without a search (see `ADR-0015`).
            @test isequal(bt_theta, theta0)
            @test isequal(bt_hw, mbr_hw)
            @test isequal(bt_hm, mbr_hm)
        else
            # Integration replay of the search (not an independent
            # schedule oracle): the replayed evaluation chain drives the
            # production driver, so the assertions verify integration and
            # ranking. The returned result is the replayed one, a commit
            # is strictly better than the status quo with the cached
            # solved hours, and a fallback means no cached candidate beat
            # the status quo. Schedule correctness itself is pinned
            # independently in `test/test_transfer_local_search.jl`.
            cache, replay_theta0, replay_status, replay_hw, replay_hm =
                replay_search(hw_init, hm_init, theta_init, pw, pm, config)
            @test length(cache) <= GN.TRANSFER_SEARCH_MAX_EVALS
            @test isequal(replay_theta0, theta0)
            @test isequal(replay_status, status_payoff)
            @test isequal(replay_hw, mbr_hw) && isequal(replay_hm, mbr_hm)
            fallback = isequal(bt_theta, theta0) &&
                isequal(bt_hw, mbr_hw) && isequal(bt_hm, mbr_hm)
            finite_payoffs = [entry.payoff for entry in values(cache) if isfinite(entry.payoff)]
            if fallback
                @test all(payoff -> !(payoff > status_payoff), finite_payoffs)
            else
                entry = cache[bt_theta]
                @test isfinite(entry.payoff) && entry.payoff > status_payoff
                @test isequal(bt_theta, replay_search_best(cache, theta0))
                @test isequal(bt_hw, entry.hw) && isequal(bt_hm, entry.hm)
            end
        end

        # Baseline comparison against the frozen pre-`MDR-0012` search
        # (see the file header): the old result is committed exactly
        # when its recorded `bt_theta` differs from the status quo.
        # Dominance is NOT asserted (the old Brent can find narrow peaks
        # the sampled grid misses and vice versa; the objective is
        # jagged at the 1e-4 scale through the discrete labour solver).
        # Counts are reported in the test log and assessed by the
        # follow-up validation package (`TASK-0014`).
        old_payoff = nash_product_reference(
            ref_bt_theta, ref_bt_hw, ref_bt_hm, ref_uw_out, ref_um_out, pw, pm, config
        )
        new_payoff = nash_product_reference(
            bt_theta, bt_hw, bt_hm, ref_uw_out, ref_um_out, pw, pm, config
        )
        if !isequal(ref_bt_theta, theta0)
            old_commits += 1
            if new_payoff >= old_payoff
                new_matches_old += 1
            else
                new_below_old += 1
            end
        end
        if !isequal(bt_theta, theta0)
            new_commits += 1
            isequal(ref_bt_theta, theta0) && (new_only_commits += 1)
        end
    end
    @info "MDR-0016 baseline comparison over the 200 fixture cases" old_commits new_matches_old new_below_old new_commits new_only_commits
end

@testset "bargaining equivalence: fixture branch coverage" begin
    @test BASELINE_SOLVER["case_count"] == length(SOLVER_CASES) == 200
    @test count(case -> case["branch"] == "improving", SOLVER_CASES) ==
        BASELINE_SOLVER["improving_count"]
    @test count(case -> case["branch"] == "fallback", SOLVER_CASES) ==
        BASELINE_SOLVER["fallback_count"]
    @test count(case -> case["branch"] == "fallback" && case["status_finite"], SOLVER_CASES) ==
        BASELINE_SOLVER["feasible_fallback_count"]
    @test count(case -> !case["status_finite"], SOLVER_CASES) ==
        BASELINE_SOLVER["infeasible_status_count"]
    @test count(case -> !case["maximizer_finite"], SOLVER_CASES) ==
        BASELINE_SOLVER["nonfinite_maximizer_count"]

    # Branch and boundary coverage required of the fixture grid.
    @test any(case -> case["branch"] == "improving", SOLVER_CASES)
    @test any(case -> case["branch"] == "fallback" && case["status_finite"], SOLVER_CASES)
    @test any(case -> !case["maximizer_finite"], SOLVER_CASES)
    @test any(case -> !case["status_finite"], SOLVER_CASES)
    @test any(case -> isequal(f64(case["theta_init"]), -1.0), SOLVER_CASES)
    @test any(case -> isequal(f64(case["theta_init"]), 1.0), SOLVER_CASES)
    @test any(case -> isequal(f64(case["hw_init"]), 0.0), SOLVER_CASES)
    @test any(case -> isequal(f64(case["hw_init"]), 1.0), SOLVER_CASES)
    @test any(case -> isequal(f64(case["hm_init"]), 0.0), SOLVER_CASES)
    @test any(case -> isequal(f64(case["hm_init"]), 1.0), SOLVER_CASES)
    @test any(
        case -> isequal(f64(case["pw_wage_self"]), 0.05) &&
            isequal(f64(case["pw_wage_spouse"]), 2.0),
        SOLVER_CASES,
    )
    @test any(
        case -> isequal(f64(case["pw_wage_self"]), 2.0) &&
            isequal(f64(case["pw_wage_spouse"]), 0.05),
        SOLVER_CASES,
    )
    for spec in ("additive", "multiplicative", "multiplicative_weighted")
        @test any(case -> case["utility"] == spec, SOLVER_CASES)
    end
    @test any(case -> case["utility"] == "ces" && isequal(f64(case["beta"]), 0.2), SOLVER_CASES)
    @test any(case -> case["utility"] == "ces" && isequal(f64(case["beta"]), 0.5), SOLVER_CASES)
end

@testset "bargaining equivalence: trajectory run invariants" begin
    # The recorded trajectories describe pre-`MDR-0012` model results
    # and stay in the fixture as baseline data only; their old-versus-new
    # deltas belong to the follow-up validation package (`TASK-0014`).
    # Asserted here: the fixture structure, finite metric runs of the
    # recorded length, committed transfers in [-1, 1] and hours in
    # [0, 1] at both phases of every tick, and bit-identical metric
    # series across two independently built and driven worlds (the
    # authoritative `GN.run` pipeline versus a manual `step_model!`
    # drive). Cross-thread-count determinism of full runs is asserted by
    # `test/test_threading.jl` (new versus new).
    @test BASELINE_TRAJECTORY["run_count"] == length(TRAJECTORY_RUNS) == 4
    @testset "trajectory $(run["id"])" for run in TRAJECTORY_RUNS
        network = Dict{String,Any}("type" => run["network_type"])
        if run["network_type"] == "watts_strogatz"
            network["neighbors_per_side"] = run["neighbors_per_side"]
            network["rewiring"] = f64(run["rewiring"])
        end
        raw = Dict{String,Any}(
            "run" => Dict{String,Any}("name" => "bargaining-baseline", "seed" => run["seed"]),
            "model" => Dict{String,Any}(
                "name" => "gender_norms",
                "agents_per_gender" => run["agents_per_gender"],
                "utility" =>
                    Dict{String,Any}("type" => run["utility_type"], "beta" => f64(run["beta"])),
                "network" => network,
            ),
            "runtime" => Dict{String,Any}("ticks" => run["ticks"]),
        )
        spec = GN.parse_spec(raw)

        # Authoritative metric series: the full `create_world` + `GN.run`
        # pipeline.
        result = GN.run(GN.create_world(spec))
        GN.is_success(result) ||
            error("trajectory run $(run["id"]) failed: $(result.error)")
        @test result.ticks == run["metric_ticks"]
        for name in ("working_time_men", "working_time_women", "working_time_gap")
            @test length(result.metrics[name]) == run["ticks"]
            @test all(isfinite, result.metrics[name])
        end

        # Manual drive of an identical world in the `step_model!` order,
        # checking run-level state invariants and comparing its metric
        # series bitwise against the authoritative run.
        config = spec.model_config
        world = GN.create_world(spec)
        women = GN.entities_with(world, GN.Female)
        agents = vcat(women, GN.entities_with(world, GN.Male))
        @test length(agents) == run["agent_count"]
        spouse_of = Dict{Ark.Entity,Int}(entity => i for (i, entity) in enumerate(agents))
        for record in run["agent"]
            entity = agents[record["index"]]
            @test (entity in women ? "woman" : "man") == record["gender"]
            spouse = Ark.get_components(world, entity, (GN.Spouse,))[1].entity
            @test spouse_of[spouse] == record["spouse_index"]
        end

        for tick in 0:(run["ticks"] - 1)
            GN.update_shocks!(world, tick)
            GN.calculate_norm_perception!(world, config.utility)
            GN.set_theta!(world, config.utility)
            for entity in agents
                time, transfer = Ark.get_components(
                    world, entity, (GN.WorkingTime, GN.TransferToWoman)
                )
                @test isfinite(time.current) && 0.0 <= time.current <= 1.0
                @test isfinite(transfer.current) && -1.0 <= transfer.current <= 1.0
            end
            GN.update_old_working_time_and_transfer!(world)
            GN.update_global_working_times!(world)
            GN.update_preferences(world)
            stats = Ark.get_resource(world, GN.WorkingTimeStats)
            @test isequal(stats.men, result.metrics["working_time_men"][tick + 1])
            @test isequal(stats.women, result.metrics["working_time_women"][tick + 1])
            @test isequal(stats.gap, result.metrics["working_time_gap"][tick + 1])
        end
    end
end

@testset "bargaining equivalence: clamped and signed-zero status quo" begin
    # Beyond the fixture grid: `bargain_transfer` must satisfy the
    # `MDR-0012` contract for status-quo transfers that `clamp` folds
    # back into `[-1, 1]`, for the signed zero -0.0 (not `=== 0.0`, so
    # it keeps its own status-quo solve; the guard of `ADR-0015` is
    # bitwise), and for an off-grid status quo. Objective-level values
    # stay bitwise against the frozen reference where the solver is
    # ineligible and within the `MDR-0017` envelopes where the
    # derivative solve may have run; the transfer result is checked by
    # validity invariants and bit-identical repeats.
    config = GN.UtilityConfig(func=GN.CES(beta=0.5))
    pw = GN.AgentPayoffParams(
        wage_self=0.6, wage_spouse=1.2, alpha=0.5, conformism=10.0,
        N_h=0.5, N_theta=0.0, N_h_spouse=0.5, is_woman=true,
    )
    pm = GN.AgentPayoffParams(
        wage_self=1.2, wage_spouse=0.6, alpha=0.5, conformism=10.0,
        N_h=0.5, N_theta=0.0, N_h_spouse=0.5, is_woman=false,
    )
    for theta_init in (-0.0, 0.0, 1.5, -1.5, 0.37)
        theta0 = clamp(theta_init, -1.0, 1.0)
        live = GN.bargain_transfer(0.5, 0.5, theta_init, pw, pm, config)
        repeat = GN.bargain_transfer(0.5, 0.5, theta_init, pw, pm, config)
        @test isequal_all(live, repeat)
        @test isfinite(live[1]) && -1.0 <= live[1] <= 1.0
        @test isfinite(live[2]) && 0.0 <= live[2] <= 1.0
        @test isfinite(live[3]) && 0.0 <= live[3] <= 1.0
        live_mbr = GN.mutual_best_response(0.5, 0.5, theta0, pw, pm, config)
        ref_mbr = mutual_best_response_reference(0.5, 0.5, theta0, pw, pm, config)
        # `CES` `beta == 0.5` config: the `MDR-0017` hours envelope on
        # top of the `MDR-0013` validated equivalence (this config is
        # derivative-solver eligible).
        @test solver_relaxed(config, theta0, pw, pm)
        @test abs(live_mbr[1] - ref_mbr[1]) <= VE_HOURS_ATOL
        @test abs(live_mbr[2] - ref_mbr[2]) <= VE_HOURS_ATOL
        uw_out, um_out = GN.outside_options(0.5, 0.5, pw, pm, config)
        status_payoff = GN.nash_product(theta0, live_mbr..., uw_out, um_out, pw, pm, config)
        if isequal(live[1], theta0)
            @test isequal(live[2], live_mbr[1]) && isequal(live[3], live_mbr[2])
        else
            committed = GN.nash_product(live..., uw_out, um_out, pw, pm, config)
            @test isfinite(committed) && committed > status_payoff
        end
    end
    @test !isequal(clamp(-0.0, -1.0, 1.0), 0.0)  # the guard must see -0.0
end
