# Tests for the in-repo Brent maximizer `maximize_1d` (unseeded and seeded
# variants over the `_brent_maximize` core) and the seeded `best_response_1d`
# in `src/resources/utility_functions.jl` (see `MDR-0002` and `MDR-0005`).
# The suite pins analytic maximizers, the non-finite-sample guards (including
# the parabolic-fit regression guard), the `max_iter` cap, the seeded
# early-return and window-fallback paths, and the zero-allocation contract.

using GenderNorms
using Test

const GN = GenderNorms

@testset "maximize_1d finds analytic maximizers" begin
    quad(x) = 1.0 - 2.0 * (x - 0.7)^2
    quartic(x) = 1.0 - (x - 0.3)^4
    tol = 1.0e-4

    @test abs(GN.maximize_1d(quad, 0.0, 1.0, tol) - 0.7) <= tol
    @test abs(GN.maximize_1d(quartic, 0.0, 1.0, tol) - 0.3) <= tol
end

@testset "maximize_1d finds a feasible band" begin
    band(x) = (0.2 <= x <= 0.8) ? x : -Inf

    x = GN.maximize_1d(band, 0.0, 1.0, 1.0e-4)

    @test 0.2 <= x <= 0.8
    @test isfinite(band(x))
    @test x ≈ 0.8 atol = 1.0e-3
end

@testset "maximize_1d returns NaN cheaply when nothing is finite" begin
    # Regression guard for the parabolic-fit guard: with no finite sample the
    # unguarded interpolation produces NaN steps and crawls for `max_iter`
    # iterations instead of shrinking the bracket.
    n = Ref(0)
    nothing_finite(x) = (n[] += 1; -Inf)

    @test isnan(GN.maximize_1d(nothing_finite, 0.0, 1.0, 1.0e-4))
    @test n[] <= 30
    @test isnan(GN.maximize_1d(x -> NaN, 0.0, 1.0, 1.0e-4))
end

@testset "maximize_1d respects the max_iter cap" begin
    n = Ref(0)
    hard(x) = (n[] += 1; sin(50.0 * x))

    x = GN.maximize_1d(hard, 0.0, 1.0, 1.0e-4; max_iter = 10)

    # One initial plus at most `max_iter` Brent samples plus the two
    # bracket endpoints, which are evaluated as candidates.
    @test n[] <= 13
    @test isfinite(x)
    @test 0.0 <= x <= 1.0
end

@testset "seeded maximize_1d returns the seed at the optimum" begin
    quad(x) = 1.0 - 2.0 * (x - 0.7)^2
    n = Ref(0)
    counted(x) = (n[] += 1; quad(x))

    x = GN.maximize_1d(counted, 0.0, 1.0, 0.7, 0.05, 1.0e-4)

    @test x == 0.7
    @test n[] <= 6
end

@testset "seeded maximize_1d finds an optimum inside the window" begin
    quad(x) = 1.0 - 2.0 * (x - 0.7)^2

    x = GN.maximize_1d(quad, 0.0, 1.0, 0.68, 0.05, 1.0e-4)

    @test abs(x - 0.7) <= 1.0e-4
end

@testset "seeded maximize_1d falls back outside the window" begin
    quad(x) = 1.0 - 2.0 * (x - 0.7)^2
    tol = 1.0e-4

    unseeded = GN.maximize_1d(quad, 0.0, 1.0, tol)

    @test abs(GN.maximize_1d(quad, 0.0, 1.0, 0.1, 0.05, tol) - unseeded) <= tol
    @test abs(GN.maximize_1d(quad, 0.0, 1.0, 0.0, 0.05, tol) - 0.7) <= tol
    @test abs(GN.maximize_1d(quad, 0.0, 1.0, 1.0, 0.05, tol) - 0.7) <= tol
end

@testset "seeded maximize_1d returns NaN when nothing is finite" begin
    @test isnan(GN.maximize_1d(x -> -Inf, 0.0, 1.0, 0.5, 0.05, 1.0e-4))
end

@testset "maximize_1d allocates nothing" begin
    quad(x) = 1.0 - 2.0 * (x - 0.7)^2
    GN.maximize_1d(quad, 0.0, 1.0, 1.0e-4)
    GN.maximize_1d(quad, 0.0, 1.0, 0.5, 0.05, 1.0e-4)

    @test @allocated(GN.maximize_1d(quad, 0.0, 1.0, 1.0e-4)) == 0
    @test @allocated(GN.maximize_1d(quad, 0.0, 1.0, 0.5, 0.05, 1.0e-4)) == 0
end

# Derivative best-response solver of `MDR-0017` (see `ADR-0022`): the
# specialized `best_response_1d(::BestResponseObjective, ::Float64)`
# with its two accuracy tiers -- the tier-1 seed certificate at
# `BEST_RESPONSE_TOL` (`_derivative_seed_certificate`, two sign probes,
# a certified seed keeps its hours) and the tier-2 full derivative
# solve certified at `DERIVATIVE_RESPONSE_TOL` -- plus the closed-form
# optima, derivative formulas, applicability regime (including the
# `CES_DERIVATIVE_MIN_BETA` floor), fallback identity against the
# seeded `MDR-0002` expression, the width-exit sign-bracket
# certificate, the measured two-sided value envelope against the
# legacy solve, and the allocation and inference contracts. The
# generic Brent tests above are unchanged; every legacy comparison
# below uses the explicit fallback expression `maximize_1d(obj, 0.0,
# 1.0, h_start, BEST_RESPONSE_WINDOW, BEST_RESPONSE_TOL)`.

"""
    solver_obj(spec, theta, h_spouse; kwargs...)

One prepared `BestResponseObjective` of a woman (recipient for
`theta > 0`, payer for `theta < 0`) for the solver testsets.
"""
function solver_obj(
        spec, theta::Float64, h_spouse::Float64;
        alpha::Float64 = 0.5, conformism::Float64 = 0.0,
        wage_self::Float64 = 1.0, wage_spouse::Float64 = 1.0,
        N_h::Float64 = 0.5, N_theta::Float64 = 0.0, N_h_spouse::Float64 = 0.5,
        w_self::Float64 = 1.0,
    )
    p = GN.AgentPayoffParams(
        wage_self = wage_self, wage_spouse = wage_spouse, alpha = alpha, conformism = conformism,
        N_h = N_h, N_theta = N_theta, N_h_spouse = N_h_spouse, is_woman = true,
    )
    config = GN.UtilityConfig(func = spec, w_self = w_self)
    return GN.BestResponseObjective(theta, h_spouse, p, config)
end

"""
    legacy_response(obj, h_start)

The seeded `MDR-0002` fallback expression that ineligible and failed
cases must reproduce bitwise.
"""
legacy_response(obj, h_start::Float64)::Float64 =
    GN.maximize_1d(obj, 0.0, 1.0, h_start, GN.BEST_RESPONSE_WINDOW, GN.BEST_RESPONSE_TOL)

"""
    tier1_pattern(obj, h_start)::Bool

Test-side recomputation of the tier-1 seed certificate of `MDR-0017`
(kept separate from `GN._derivative_seed_certificate` so a solver
regression cannot hide in the helper): `true` iff `h_start` is a
feasible point of `[0, 1]` and the two sign probes at `h_start +/-
BEST_RESPONSE_TOL` certify it within that resolution of the optimum of
`obj` (both probes enclosing `g(h - tol) >= 0 >= g(h + tol)`, or the
one-sided rule at a domain end with its `h_start <= BEST_RESPONSE_TOL`
/ `h_start >= 1 - BEST_RESPONSE_TOL` domain condition).
"""
function tier1_pattern(obj, h_start::Float64)::Bool
    (0.0 <= h_start <= 1.0) || return false
    isfinite(obj(h_start)) || return false
    tol = GN.BEST_RESPONSE_TOL
    gl = GN._best_response_gradient_sign(obj, h_start - tol)
    gr = GN._best_response_gradient_sign(obj, h_start + tol)
    gl_ok = isfinite(gl)
    gr_ok = isfinite(gr)
    if gl_ok && gr_ok
        return gl >= 0.0 && gr <= 0.0
    elseif gr_ok
        return h_start <= tol && gr <= 0.0
    elseif gl_ok
        return h_start >= 1.0 - tol && gl >= 0.0
    end
    return false
end

# Measured two-sided computed-value envelope `|U(new) - U(legacy)|` of
# the two-tier solver against the legacy seeded search, relative at the
# comparison scale (see `MDR-0017` and
# `benchmark/derivative_solver_validation.md`): 31,855 measured cases
# (the 200 fixture cases at their frozen reference state, the asserted
# regime grid below, and 32,728 random-draw cases over all specs,
# roles, and parameter edges, half of them production-like seeds
# within 3e-4 of the optimum) measure a worst case of 1.85e-4
# relative. The envelope is the objective's value variation across the
# shared `BEST_RESPONSE_TOL` quality window at sharp peaks (both
# returns sit within that window of the optimum and can differ inside
# it): 99% of cases sit at or below 1.73e-4, no case exceeds 2e-4, and
# the LOSS side (legacy better) measures 9.35e-5 at its single worst
# draw with 99.9% of cases at or below 9.4e-7. The tolerance below is
# that envelope with headroom; the outlier draws are reported with
# their parameters in `MDR-0017` and the validation report instead of
# being hidden by a looser tolerance. The `CES` computed-jaggedness
# allowance `CES_DERIVATIVE_LOSS_TOL` (below) stays in force inside
# this envelope for every computed-value comparison.
const BEST_RESPONSE_VALUE_RTOL = 5.0e-4

# An unenveloped `UtilitySpec` subtype: the objective is evaluable, but
# the derivative solve must decline it and fall back bitwise (top level,
# like all test helpers).
struct _WeirdSolverSpec <: GN.UtilitySpec end

GN.material(::_WeirdSolverSpec, x::Float64, Q::Float64, alpha::Float64) = sqrt(x) * sqrt(Q)

@testset "derivative best response finds closed-form optima" begin
    # Zero conformism, recipient (`A = wage_self`, `B = |theta| *
    # wage_spouse * h_spouse`, `Q0 = 2 - h_spouse`): the first-order
    # conditions of `MDR-0017` have closed-form roots; the chosen
    # parameters keep every root strictly inside `(0, 1)`.
    theta = 0.1
    h_spouse = 1.0
    A = 1.0
    B = 0.1 * 1.0 * h_spouse
    Q0 = 2.0 - h_spouse
    # Multiplicative: `A * (Q0 - h) == A * h + B`.
    obj = solver_obj(GN.Multiplicative(), theta, h_spouse)
    h_star = (A * Q0 - B) / (2A)
    @test 0.0 < h_star < 1.0
    for h_start in (0.0, 0.3, 1.0)
        h = GN.best_response_1d(obj, h_start)
        @test abs(h - h_star) <= 2.0e-7
    end
    # MultiplicativeWeighted recipient: `alpha * A / x == (1 - alpha) / Q`.
    for alpha in (0.3, 0.7)
        obj = solver_obj(GN.MultiplicativeWeighted(), theta, h_spouse; alpha = alpha)
        h_star = (alpha * A * Q0 - (1 - alpha) * B) / A
        @test 0.0 < h_star < 1.0
        for h_start in (0.0, 0.3, 1.0)
            h = GN.best_response_1d(obj, h_start)
            @test abs(h - h_star) <= 2.0e-7
        end
    end
    # Additive: `alpha^2 * A^2 * Q == (1 - alpha)^2 * x`.
    for alpha in (0.3, 0.7)
        obj = solver_obj(GN.Additive(), theta, h_spouse; alpha = alpha)
        num = alpha^2 * A^2 * Q0 - (1 - alpha)^2 * B
        den = (1 - alpha)^2 * A + alpha^2 * A^2
        h_star = num / den
        @test 0.0 < h_star < 1.0
        for h_start in (0.0, 0.3, 1.0)
            h = GN.best_response_1d(obj, h_start)
            @test abs(h - h_star) <= 2.0e-7
        end
    end
    # Conformism shifts the root off the closed form; the shifted
    # optimum satisfies the first-order condition directly, or the
    # tier-1 seed certificate keeps the seed when the shifted root lies
    # within `BEST_RESPONSE_TOL` of it (the two-tier contract of
    # `MDR-0017`).
    obj = solver_obj(GN.Multiplicative(), theta, h_spouse; conformism = 10.0, N_h = 0.2)
    h = GN.best_response_1d(obj, 0.3)
    if GN._derivative_applicable(obj, 0.3) && GN._derivative_seed_certificate(obj, 0.3)
        @test h == 0.3
        @test tier1_pattern(obj, 0.3)
    else
        g, _, _ = GN._best_response_derivatives(obj, h)
        @test abs(g) <= 1.0e-5
    end
end

@testset "derivative formulas match finite differences" begin
    d = 1.0e-5
    for spec in (
                GN.Multiplicative(), GN.MultiplicativeWeighted(), GN.Additive(),
                GN.CES(beta = 0.1), GN.CES(beta = 0.5), GN.CES(beta = 0.9), GN.CES(beta = 1.0),
            ), theta in (0.3, -0.3), alpha in (0.3, 0.7), conformism in (0.0, 10.0)
        obj = solver_obj(spec, theta, 0.5; alpha = alpha, conformism = conformism, N_h = 0.4)
        for h in (0.2, 0.5, 0.8)
            g, gp, value = GN._best_response_derivatives(obj, h)
            # The same-pass value is bitwise `obj(h)`.
            @test isequal(value, obj(h))
            # The sign probe is the `MDR-0017` multiplied-through sign
            # residual of `g` (`_gradient_sign_residual`): its sign is
            # the sign of `g`, but it is a different rounding of `g`, so
            # the old exact-value pin `isequal(probe, g)` is not a valid
            # assertion anymore (it held only while the probe evaluated
            # the `g` expression itself). Sign equality is asserted
            # instead, with the near-zero noise class of the sign form
            # exempted.
            probe = GN._best_response_gradient_sign(obj, h)
            @test isfinite(probe)
            @test sign(probe) == sign(g) || abs(g) <= 1.0e-12
            log_p = log(obj(h + d))
            log_m = log(obj(h - d))
            fd = (log_p - log_m) / (2.0 * d)
            @test isapprox(g, fd; rtol = 1.0e-6)
            g_p = GN._best_response_derivatives(obj, h + d)[1]
            g_m = GN._best_response_derivatives(obj, h - d)[1]
            fd2 = (g_p - g_m) / (2.0 * d)
            @test isapprox(gp, fd2; rtol = 1.0e-5, atol = 1.0e-9)
        end
    end
end

@testset "derivative best response boundary optima" begin
    # `CES` `beta == 1` has `g = D / S` with `D = alpha * A -
    # (1-alpha)`: the sign of `D` selects `h = 0` or `h = 1` exactly.
    obj = solver_obj(GN.CES(beta = 1.0), 0.3, 0.5; alpha = 0.3)
    @test GN.best_response_1d(obj, 0.3) == 0.0
    obj = solver_obj(GN.CES(beta = 1.0), 0.3, 0.5; alpha = 0.7)
    @test GN.best_response_1d(obj, 0.3) == 1.0
    # Weighted recipient at `alpha == 1` (material `x`, `g = A/x > 0`
    # everywhere) selects `h = 1` exactly; at `alpha == 0` (material
    # `Q`, `g = -1/Q < 0` everywhere) it selects `h = 0` exactly.
    obj = solver_obj(GN.MultiplicativeWeighted(), 0.3, 0.5; alpha = 1.0)
    @test GN.best_response_1d(obj, 0.3) == 1.0
    obj = solver_obj(GN.MultiplicativeWeighted(), 0.3, 0.5; alpha = 0.0)
    @test GN.best_response_1d(obj, 0.3) == 0.0
    # A Multiplicative root below the domain: the lower boundary is the
    # optimum and is returned exactly.
    obj = solver_obj(GN.Multiplicative(), 0.9, 1.0; wage_self = 0.01, wage_spouse = 1.0)
    @test GN.best_response_1d(obj, 0.3) == 0.0
end

@testset "derivative best response tier-1 seed certificate" begin
    # Tier-1 of `MDR-0017` (`_derivative_seed_certificate`): a seed
    # certified within `BEST_RESPONSE_TOL` (the NetLogo `current-delta`
    # resolution) of the optimum by two cheap sign probes keeps its
    # hours and returns at probe cost. Every assertion recomputes the
    # certificate independently (`tier1_pattern`).
    tol = GN.BEST_RESPONSE_TOL
    # Interior enclosure seeds: solve once at a far seed, then seed
    # within `BEST_RESPONSE_TOL` of the solved root; the certificate
    # fires, the seed is kept bitwise, and a re-solve at it re-certifies
    # (tier-1 idempotence).
    for spec in (
                GN.Multiplicative(), GN.MultiplicativeWeighted(), GN.Additive(),
                GN.CES(beta = 0.5), GN.CES(beta = 0.9), GN.CES(beta = 1.0),
            ), theta in (0.3, -0.3)
        obj = solver_obj(spec, theta, 0.5; conformism = 5.0, N_h = 0.4)
        h_star = GN.best_response_1d(obj, 0.95)
        (isfinite(h_star) && 0.0 < h_star < 1.0) || continue
        for delta in (-8.0e-5, -3.0e-5, 3.0e-5, 8.0e-5)
            h_seed = h_star + delta
            (0.0 < h_seed < 1.0) || continue
            @test GN._derivative_seed_certificate(obj, h_seed)
            @test tier1_pattern(obj, h_seed)
            @test isequal(GN.best_response_1d(obj, h_seed), h_seed)
            @test abs(h_seed - h_star) <= tol
        end
    end
    # One-sided boundary seeds certify at ONE probe cost: the probe
    # outside the domain is skipped (`NaN` from the point guards)
    # and the feasible interval extends at most `tol` past the seed.
    # `alpha == 0` weighted recipient: material `Q`, `g < 0` everywhere,
    # boundary optimum at `h = 0`.
    obj = solver_obj(GN.MultiplicativeWeighted(), 0.3, 0.5; alpha = 0.0)
    @test isnan(GN._best_response_gradient_sign(obj, -tol))
    @test GN._best_response_gradient_sign(obj, tol) < 0.0
    @test GN._derivative_seed_certificate(obj, 0.0)
    @test tier1_pattern(obj, 0.0)
    @test isequal(GN.best_response_1d(obj, 0.0), 0.0)
    # Seeds within `tol` of the lower end keep their hours through the
    # one-sided rule (within `tol` of the boundary optimum); a seed
    # beyond `tol` certifies nothing and the tier-2 boundary rule
    # returns the boundary optimum exactly.
    @test GN._derivative_seed_certificate(obj, 5.0e-5)
    @test isequal(GN.best_response_1d(obj, 5.0e-5), 5.0e-5)
    @test !GN._derivative_seed_certificate(obj, 3.0e-4)
    @test GN.best_response_1d(obj, 3.0e-4) == 0.0
    # Symmetric at the upper end: `alpha == 1` weighted recipient,
    # material `x`, `g > 0` everywhere, boundary optimum at `h = 1`.
    obj = solver_obj(GN.MultiplicativeWeighted(), 0.3, 0.5; alpha = 1.0)
    @test isnan(GN._best_response_gradient_sign(obj, 1.0 + tol))
    @test GN._best_response_gradient_sign(obj, 1.0 - tol) > 0.0
    @test GN._derivative_seed_certificate(obj, 1.0)
    @test tier1_pattern(obj, 1.0)
    @test isequal(GN.best_response_1d(obj, 1.0), 1.0)
    @test GN._derivative_seed_certificate(obj, 1.0 - 5.0e-5)
    @test isequal(GN.best_response_1d(obj, 1.0 - 5.0e-5), 1.0 - 5.0e-5)
    @test !GN._derivative_seed_certificate(obj, 1.0 - 3.0e-4)
    @test GN.best_response_1d(obj, 1.0 - 3.0e-4) == 1.0
    # A guard-open boundary seed is infeasible and must NOT certify
    # (there the optimum is the unattainable supremum): the `alpha == 0`
    # payer corner at `h_start == 0` runs the full solve and falls back
    # bitwise. A near-boundary seed keeps its hours through the
    # one-sided rule, which is bitwise the legacy anchor return there.
    p = GN.AgentPayoffParams(
        wage_self = 1.0, wage_spouse = 1.0, alpha = 0.0, is_woman = false
    )
    obj = GN.BestResponseObjective(
        0.3, 0.5, p, GN.UtilityConfig(func = GN.MultiplicativeWeighted())
    )
    @test !GN._derivative_seed_certificate(obj, 0.0)
    @test isequal(GN.best_response_1d(obj, 0.0), legacy_response(obj, 0.0))
    @test GN._derivative_seed_certificate(obj, 5.0e-5)
    @test isequal(GN.best_response_1d(obj, 5.0e-5), 5.0e-5)
    @test isequal(GN.best_response_1d(obj, 5.0e-5), legacy_response(obj, 5.0e-5))
    # Flat objective (`g == 0` at both probes): tier-1 keeps the seed,
    # matching the legacy tie/seed return bitwise.
    p = GN.AgentPayoffParams(
        wage_self = 1.0, wage_spouse = 1.0, alpha = 1.0, is_woman = false
    )
    obj = GN.BestResponseObjective(
        0.3, 0.5, p, GN.UtilityConfig(func = GN.MultiplicativeWeighted())
    )
    @test GN._derivative_seed_certificate(obj, 0.37)
    @test tier1_pattern(obj, 0.37)
    @test isequal(GN.best_response_1d(obj, 0.37), 0.37)
    @test isequal(GN.best_response_1d(obj, 0.37), legacy_response(obj, 0.37))
    # Cost structure of a certified return: only the two sign probes
    # run (never the objective value or the curvature), and at a
    # boundary seed the out-of-domain probe is skipped at once, so the
    # return costs ONE probe plus the applicability gate. The probes
    # never call the objective, so no counting wrapper can observe the
    # specialized dispatch; the cost claim is pinned structurally (the
    # skipped probe is `NaN` by its point guards, the result is the
    # seed bitwise) with the zero-allocation contract pinned in the
    # allocation testset below.
    obj = solver_obj(GN.MultiplicativeWeighted(), 0.3, 0.5; alpha = 0.0)
    @test isequal(GN._derivative_best_response(obj, 0.0), (0.0, true))
end

@testset "derivative best response keeps the legacy solver for inapplicable cases" begin
    # Unsupported specs and out-of-regime parameters fall back bitwise
    # to the seeded `MDR-0002` expression (including `NaN`).
    inapplicable = (
        ("ces beta 0", solver_obj(GN.CES(beta = 0.0), 0.2, 0.5)),
        ("ces beta -1", solver_obj(GN.CES(beta = -1.0), 0.2, 0.5)),
        ("ces beta 1.5", solver_obj(GN.CES(beta = 1.5), 0.2, 0.5)),
        ("ces beta NaN", solver_obj(GN.CES(beta = NaN), 0.2, 0.5)),
        ("alpha -0.5", solver_obj(GN.Multiplicative(), 0.2, 0.5; alpha = -0.5)),
        ("alpha 1.5", solver_obj(GN.Multiplicative(), 0.2, 0.5; alpha = 1.5)),
        ("negative conformism", solver_obj(GN.Multiplicative(), 0.2, 0.5; conformism = -1.0)),
        ("negative norm weight", solver_obj(GN.Multiplicative(), 0.2, 0.5; w_self = -1.0)),
        ("non-finite N_h", solver_obj(GN.Multiplicative(), 0.2, 0.5; N_h = NaN)),
        ("spouse out of range", solver_obj(GN.Multiplicative(), 0.2, 1.5)),
        ("weird spec", solver_obj(_WeirdSolverSpec(), 0.2, 0.5)),
    )
    for (label, obj) in inapplicable, h_start in (0.0, 0.3, 1.0)
        @test isequal(GN.best_response_1d(obj, h_start), legacy_response(obj, h_start))
    end
    # The all-infeasible payer (`A == B == 0`) is inapplicable and keeps
    # the legacy `NaN` contract.
    p = GN.AgentPayoffParams(wage_self = 0.0, wage_spouse = 1.0, is_woman = false)
    obj = GN.BestResponseObjective(0.2, 0.5, p, GN.UtilityConfig())
    @test GN._derivative_applicable(obj, 0.3) == false
    @test isequal(GN.best_response_1d(obj, 0.3), legacy_response(obj, 0.3))
    @test isnan(GN.best_response_1d(obj, 0.3))
    # The guard-infeasible-supremum corner of `MDR-0017` step 2: the
    # `MultiplicativeWeighted` payer with `alpha == 0` (material `Q`)
    # has the finite one-sided limit `-1 / Q(0) < 0` at the infeasible
    # `h -> 0+` when `x(0) == 0`: `U` rises toward the infeasible
    # endpoint, so the derivative solve refuses the unattainable
    # supremum and falls back bitwise.
    p = GN.AgentPayoffParams(wage_self = 1.0, wage_spouse = 1.0, alpha = 0.0, is_woman = false)
    obj = GN.BestResponseObjective(
        0.3, 0.5, p, GN.UtilityConfig(func = GN.MultiplicativeWeighted())
    )
    @test GN._derivative_applicable(obj, 0.3)
    @test GN._one_sided_gradient(obj, true) < 0.0
    for h_start in (0.0, 0.3, 1.0)
        @test isequal(GN.best_response_1d(obj, h_start), legacy_response(obj, h_start))
    end
end

@testset "derivative best response keeps the legacy solver below the CES beta floor" begin
    # Reviewer repro of `MDR-0017`: `CES` `beta = 1.0e-12` amplifies the
    # inner-sum rounding of `S^(1/beta)` by `1 / beta` (see
    # `CES_DERIVATIVE_MIN_BETA`), jags the computed utility at the
    # 1e-4 relative level, and used to let a certified analytic root
    # return materially worse computed utility than the legacy Brent
    # sample (0.9899478346405225 at 0.9599999999999227 versus
    # 0.9900577470296925 at 0.9576275641403225). Below the floor the
    # case is inapplicable and bitwise the seeded `MDR-0002` expression.
    obj = solver_obj(
        GN.CES(beta = 1.0e-12), 0.3, 0.05;
        alpha = 0.5, wage_self = 1.0, wage_spouse = 2.0
    )
    @test GN._derivative_applicable(obj, 0.1) == false
    @test isequal(
        GN.best_response_1d(obj, 0.1),
        GN.maximize_1d(obj, 0.0, 1.0, 0.1, GN.BEST_RESPONSE_WINDOW, GN.BEST_RESPONSE_TOL),
    )
    # The whole measured sub-floor band (see the `CES_DERIVATIVE_MIN_BETA`
    # sweep) stays bitwise legacy at every seed, and the floor itself is
    # the first applicable `CES` regime.
    for beta in (1.0e-12, 1.0e-6, 1.0e-5, 2.0e-5, 9.9e-4), h_start in (0.0, 0.3, 1.0)
        obj = solver_obj(GN.CES(beta = beta), 0.3, 0.5)
        @test GN._derivative_applicable(obj, h_start) == false
        @test isequal(GN.best_response_1d(obj, h_start), legacy_response(obj, h_start))
    end
    obj = solver_obj(GN.CES(beta = GN.CES_DERIVATIVE_MIN_BETA), 0.3, 0.5)
    @test GN._derivative_applicable(obj, 0.3)
end

@testset "derivative best response width exit certifies a sign bracket" begin
    # Reviewer repro of `MDR-0017` step 5: the `MultiplicativeWeighted`
    # payer with `alpha = 1e-12`, zero conformism, transfer `-0.3`,
    # spouse hours `0.5`, seed `0.3` exits at a maintained sign bracket
    # of width `<= DERIVATIVE_RESPONSE_TOL` whose left enclosure probe
    # is skipped (it leaves the feasible interval, `x(0) == 0` opens the
    # lower end). The sign bracket certifies the candidate, which must
    # sit within `DERIVATIVE_RESPONSE_TOL` of an independently computed
    # root of `g` (the sharp interior root near `h -> 0+`).
    p = GN.AgentPayoffParams(
        alpha = 1.0e-12, wage_self = 1.0, wage_spouse = 1.0, conformism = 0.0,
        N_h = 0.5, N_theta = 0.0, N_h_spouse = 0.5, is_woman = true,
    )
    obj = GN.BestResponseObjective(
        -0.3, 0.5, p, GN.UtilityConfig(func = GN.MultiplicativeWeighted())
    )
    candidate, solved = GN._derivative_best_response(obj, 0.3)
    @test solved
    @test isequal(GN.best_response_1d(obj, 0.3), candidate)
    @test isnan(
        GN._best_response_gradient_sign(
            obj, candidate - GN.DERIVATIVE_RESPONSE_TOL
        )
    )
    # Independent root of `g`: high-precision bisection on the sign
    # probe between the `g > 0` point at `h -> 0+` and the `g < 0` side.
    lo = 1.0e-15
    hi = 1.0e-6
    @test GN._best_response_gradient_sign(obj, lo) > 0.0
    @test GN._best_response_gradient_sign(obj, hi) < 0.0
    for _ in 1:100
        mid = 0.5 * (lo + hi)
        (mid > lo && mid < hi) || break
        if GN._best_response_gradient_sign(obj, mid) > 0.0
            lo = mid
        else
            hi = mid
        end
    end
    root = 0.5 * (lo + hi)
    @test abs(candidate - root) <= GN.DERIVATIVE_RESPONSE_TOL
    # The noise-guard half of the certificate (both probes evaluable but
    # not enclosing, possible only under numerical non-monotonicity of
    # the computed `g`) is not constructible in the eligible regime: the
    # probes are the `MDR-0017` multiplied-through sign residuals of `g`
    # (`_gradient_sign_residual`), whose terms are exactly the `g` terms
    # times the positive denominator, so the probe signals at `+/-
    # DERIVATIVE_RESPONSE_TOL` (magnitude `|g'| * tol * den`) still sit
    # `tol / eps` (1e8) above the rounding noise of the residual form,
    # and a 3.8M-draw scan over every eligible spec and adversarial
    # corner (BigFloat analytic-sign reference) found no probe sign flip
    # at all, no tier-1 enclosure violation, and no tier-2 exit
    # certificate violation. The guard is pinned structurally by the
    # enclosure invariant of the regime grid instead.
end

# Documented computed-utility non-degradation envelope of the derivative
# solver for `CES` over the eligible beta range (see
# `CES_DERIVATIVE_MIN_BETA` and `MDR-0017`): the computed utility
# evaluates `S^(1/beta)`, whose condition number `1 / beta` amplifies
# the inner-sum rounding of two compared evaluations to the relative gap
# `(1 / beta) * n_ops * eps` (about 1.1e-12 at the floor `beta =
# CES_DERIVATIVE_MIN_BETA` with `n_ops = 10`, `eps = 2^-53`). The
# measured sweep behind the floor (log grid of `beta` in [1.0e-6, 1.0],
# 4000 random parameter draws per beta) bounds the worst relative loss
# of the derivative result versus the legacy result by 1.5e-13 at the
# floor and 2.1e-15 above `beta = 0.1`; the 1.0e-11 envelope covers the
# analytic amplification bound and the measured losses an order of
# magnitude up. The O(1)-conditioned specs keep the 32-ulp bar.
const CES_DERIVATIVE_LOSS_TOL = 1.0e-11

"""
    quality_slack(spec, scale::Float64)::Float64

Computed-utility non-degradation tolerance of the derivative quality
checks at comparison scale `scale`: `CES_DERIVATIVE_LOSS_TOL * scale`
for `CES` (the documented envelope above), 32 ulps for every other
spec. Governs every computed-value comparison of both tiers (the
tier-2 local probe checks and the two-sided legacy comparison below).
"""
quality_slack(spec, scale::Float64)::Float64 =
    spec isa GN.CES ? CES_DERIVATIVE_LOSS_TOL * scale : 32.0 * eps(scale)

"""
    value_slack(spec, scale::Float64)::Float64

Two-sided computed-value tolerance of the new-versus-legacy comparison
at comparison scale `scale`: the measured `BEST_RESPONSE_VALUE_RTOL`
window-variation envelope plus the `quality_slack` computed-jaggedness
allowance of the spec.
"""
value_slack(spec, scale::Float64)::Float64 =
    BEST_RESPONSE_VALUE_RTOL * scale + quality_slack(spec, scale)

@testset "derivative best response: regime grid and quality invariant" begin
    # The applicable grid of `TASK-0023`, tier-aware per the two-tier
    # contract of `MDR-0017`: a tier-1 return (the seed certificate
    # fires) must be the seed and satisfy the independently recomputed
    # enclosure pattern; a tier-2 return must satisfy the own-response
    # first-order condition (`|g|` small or a certified boundary with
    # its endpoint sign) and the local probe quality; and every result
    # must stay inside the measured two-sided value envelope
    # `BEST_RESPONSE_VALUE_RTOL` against the legacy solve (both returns
    # sit within the `BEST_RESPONSE_TOL` quality window of the optimum
    # and can differ inside it). The `CES` column covers the whole
    # eligible beta range from `CES_DERIVATIVE_MIN_BETA` up, where the
    # computed-value checks use the measured jaggedness envelope above.
    specs = (
        GN.Multiplicative(), GN.MultiplicativeWeighted(), GN.Additive(),
        GN.CES(beta = GN.CES_DERIVATIVE_MIN_BETA), GN.CES(beta = 1.0e-2),
        GN.CES(beta = 0.1), GN.CES(beta = 0.5), GN.CES(beta = 0.9), GN.CES(beta = 1.0),
    )
    checked = 0
    tier1_checked = 0
    tier2_checked = 0
    for spec in specs, alpha in (0.0, 0.3, 0.7, 1.0), conf in (0.0, 10.0),
            theta in (-1.0, 0.0, 0.5, 1.0), h_spouse in (0.0, 0.5, 1.0),
            wage_self in (1.2, 0.0), h_start in (0.0, 0.3, 1.0)
        obj = solver_obj(
            spec, theta, h_spouse;
            alpha = alpha, conformism = conf, wage_self = wage_self, wage_spouse = 0.8
        )
        legacy = legacy_response(obj, h_start)
        result = GN.best_response_1d(obj, h_start)
        candidate, solved = GN._derivative_best_response(obj, h_start)
        checked += 1
        if !GN._derivative_applicable(obj, h_start)
            @test isequal(result, legacy)
            continue
        end
        @test isequal(result, solved ? candidate : legacy)
        v_new = NaN
        if isfinite(result)
            @test 0.0 <= result <= 1.0
            v_new = obj(result)
            @test isfinite(v_new) && v_new > 0.0
            if GN._derivative_seed_certificate(obj, h_start)
                # Tier 1: the certified seed keeps its hours and
                # satisfies the independent enclosure recomputation.
                tier1_checked += 1
                @test solved
                @test isequal(result, h_start)
                @test tier1_pattern(obj, h_start)
            elseif solved
                # Tier 2: the first-order condition at `DERIVATIVE_RESPONSE_TOL`
                # (the width-exit certificate bounds the argument
                # error there, so the FOC residual is bounded by
                # `|g'| * DERIVATIVE_RESPONSE_TOL`), a certified
                # boundary sign where the result is an endpoint, and
                # the probe sign-enclosure invariant of `MDR-0017`
                # step 5.
                tier2_checked += 1
                if result != 0.0 && result != 1.0
                    g, _, _ = GN._best_response_derivatives(obj, result)
                    @test abs(g) <= 1.0e-4
                else
                    g_end = GN._best_response_gradient_sign(obj, result)
                    if isfinite(g_end)
                        @test result == 0.0 ? g_end < 0.0 : g_end > 0.0
                    end
                end
                g_left = GN._best_response_gradient_sign(
                    obj, result - GN.DERIVATIVE_RESPONSE_TOL
                )
                g_right = GN._best_response_gradient_sign(
                    obj, result + GN.DERIVATIVE_RESPONSE_TOL
                )
                if isfinite(g_left) && isfinite(g_right)
                    @test g_left >= 0.0 && g_right <= 0.0
                end
                for probe in (result - 1.0e-6, result + 1.0e-6)
                    (0.0 <= probe <= 1.0) || continue
                    v_probe = obj(probe)
                    isfinite(v_probe) || continue
                    scale = max(abs(v_new), abs(v_probe))
                    @test v_new >= v_probe - quality_slack(spec, scale)
                end
            end
        end
        # Measured two-sided value equivalence against the legacy solve
        # (the `MDR-0017` non-degradation contract: the tier accuracy
        # certificates above plus the `BEST_RESPONSE_VALUE_RTOL`
        # envelope, with the `CES` computed-jaggedness allowance kept
        # inside it).
        v_legacy = (isfinite(legacy) && 0.0 <= legacy <= 1.0) ? obj(legacy) : NaN
        if isfinite(v_legacy)
            @test isfinite(v_new)
            scale = max(abs(v_new), abs(v_legacy))
            @test abs(v_new - v_legacy) <= value_slack(spec, scale)
        end
    end
    @test checked > 1000
    @test tier1_checked > 100
    @test tier2_checked > 100
end

# Allocation probes of the solver contract: measured through top-level
# helpers so the testset scope cannot box the objective argument.
solver_allocs(obj, h_start::Float64)::Int = @allocated GN.best_response_1d(obj, h_start)

derivative_allocs(obj, h_start::Float64)::Int = @allocated GN._derivative_best_response(obj, h_start)

cert_allocs(obj, h_start::Float64)::Int = @allocated GN._derivative_seed_certificate(obj, h_start)

@testset "derivative best response allocates nothing and infers" begin
    for spec in (
            GN.Multiplicative(), GN.MultiplicativeWeighted(), GN.Additive(),
            GN.CES(beta = 0.1), GN.CES(beta = 0.5), GN.CES(beta = 0.9), GN.CES(beta = 1.0),
        )
        obj = solver_obj(spec, 0.2, 0.5; conformism = 5.0, N_h = 0.4)
        GN.best_response_1d(obj, 0.3)
        @test solver_allocs(obj, 0.3) == 0
        @test derivative_allocs(obj, 0.3) == 0
        @test (@inferred GN.best_response_1d(obj, 0.3)) isa Float64
        @test (@inferred GN._derivative_best_response(obj, 0.3)) isa Tuple{Float64, Bool}
        @test (@inferred GN._derivative_seed_certificate(obj, 0.3)) isa Bool
    end
    # The tier-1 route (a certified seed return) allocates nothing.
    for spec in (GN.Multiplicative(), GN.Additive(), GN.CES(beta = 0.5))
        obj = solver_obj(spec, 0.2, 0.5; conformism = 5.0, N_h = 0.4)
        h = GN.best_response_1d(obj, 0.3)
        @test GN._derivative_seed_certificate(obj, h)
        GN.best_response_1d(obj, h)
        @test solver_allocs(obj, h) == 0
        @test derivative_allocs(obj, h) == 0
        @test cert_allocs(obj, h) == 0
    end
    # The fallback route allocates nothing as well.
    obj = solver_obj(GN.CES(beta = 1.5), 0.2, 0.5)
    GN.best_response_1d(obj, 0.3)
    @test solver_allocs(obj, 0.3) == 0
end

@testset "derivative best response settles a solved point" begin
    # A certified solution is a fixed point of the solver: re-solving at
    # the returned hours re-certifies (tier 1 at the same probes, or the
    # tier-2 probe enclosure) and returns them bitwise (the property
    # `mutual_best_response` relies on for its bitwise fixed points).
    # The claim covers interior, boundary, and tier-1 seed returns
    # alike: a boundary optimum re-certifies through the one-sided
    # rule at its domain end.
    for spec in (
                GN.Multiplicative(), GN.MultiplicativeWeighted(), GN.Additive(),
                GN.CES(beta = 0.5), GN.CES(beta = 0.9), GN.CES(beta = 1.0),
            ), theta in (0.3, -0.3), conformism in (0.0, 10.0)
        obj = solver_obj(spec, theta, 0.5; conformism = conformism, N_h = 0.4)
        candidate, solved = GN._derivative_best_response(obj, 0.3)
        solved || continue
        @test isfinite(candidate) && 0.0 <= candidate <= 1.0
        @test isequal(GN.best_response_1d(obj, candidate), candidate)
    end
end
