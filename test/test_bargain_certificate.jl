# Tests for the certified `-Inf` transfer-objective certificate of
# `ADR-0015`: `_objective_prunable`, `_payoff_upper_bound`, and the
# per-spec `_material_envelope` helpers of
# `src/resources/utility_functions.jl`. The contract under test is
# soundness, not coverage: whenever the certificate prunes a sampled
# transfer, the reference solver chain
# (`test/reference_bargaining.jl`) must compute the payoff `-Inf` for
# that transfer, so pruning cannot change any committed output. Every
# uncertain input must fail open (run the full solve). The certificate
# is an optimization of `ADR-0015`, not a ported NetLogo behavior, so
# it carries no NetLogo or ODD citation; the solver semantics it must
# preserve are pinned by `MDR-0002` and `MDR-0012` (superseding
# `MDR-0005`).

using GenderNorms
using Random
using Test

const GN = GenderNorms

# `test/reference_bargaining.jl` is included exactly once per test run
# (`test/test_bargaining_equivalence.jl` owns the include for the full
# suite); the guard keeps this file runnable on its own.
if !isdefined(@__MODULE__, :bargain_transfer_reference)
    include("reference_bargaining.jl")
end

# `MDR-0013` validated-equivalence helpers (defined in
# `test/test_bargaining_equivalence.jl` for the full suite); the guard
# keeps this file runnable on its own.
if !isdefined(@__MODULE__, :veq)
    """
        arith_changed(config)::Bool

    `true` exactly for the utility specs whose computed arithmetic
    changed under `MDR-0013` (`CES` with `beta == 0.5`).
    """
    arith_changed(config)::Bool =
        config.func isa GN.CES && config.func.beta == 0.5

    """
        veq(a::Float64, b::Float64)::Bool

    Validated-equivalence float comparison of `MDR-0013`: `isapprox`
    with the recorded tolerance envelope where the arithmetic changed,
    `isequal` otherwise (and for non-finite values).
    """
    veq(a::Float64, b::Float64)::Bool =
        (isfinite(a) && isfinite(b)) ? isapprox(a, b; atol = 1.0e-10, rtol = 1.0e-9) : isequal(a, b)
end

# `MDR-0017` validated-equivalence helpers (defined in
# `test/test_bargaining_equivalence.jl` for the full suite); the guard
# keeps this file runnable on its own.
if !isdefined(@__MODULE__, :solver_relaxed)
    const VE_HOURS_ATOL = 2.0e-3
    const VE_UTIL_ATOL = 1.0e-3
    const VE_UTIL_RTOL = 1.0e-3
    const VE_PAYOFF_ATOL = 1.0e-4
    const VE_PAYOFF_RTOL = 1.0e-3

    """
        solver_relaxed(config, theta0::Float64, pw, pm)::Bool

    Conservative static predicate that the `MDR-0017` specialized
    derivative solver may have contributed to one case (see
    `test/test_bargaining_equivalence.jl`).
    """
    function solver_relaxed(config, theta0::Float64, pw, pm)::Bool
        for partner in (pw, pm), theta in (theta0, 0.0, 1.0, -1.0), h_spouse in (0.0, 0.5, 1.0)
            obj = GN.BestResponseObjective(theta, h_spouse, partner, config)
            GN._derivative_applicable(obj, 0.3) && return true
        end
        return false
    end

    """
        equiv(a::Float64, b::Float64, atol::Float64, config, relaxed::Bool)::Bool

    Three-class validated-equivalence comparison of `MDR-0017`: exact,
    `MDR-0013` `veq`, or the explicit `MDR-0017` tolerance (see
    `test/test_bargaining_equivalence.jl`).
    """
    function equiv(
            a::Float64, b::Float64, atol::Float64, config, relaxed::Bool; rtol::Float64 = 0.0
        )::Bool
        relaxed && return (isfinite(a) && isfinite(b)) ?
            abs(a - b) <= atol + rtol * max(abs(a), abs(b)) : isequal(a, b)
        arith_changed(config) && return veq(a, b)
        return isequal(a, b)
    end

    """
        payoff_equiv(a::Float64, b::Float64, config, relaxed::Bool)::Bool

    Payoff comparison of `MDR-0017` on boundary draws: the scale-aware
    `VE_PAYOFF_ATOL` plus `VE_PAYOFF_RTOL` envelope (the Nash product is
    quadratic in gains that scale with the drawn wages, so the absolute
    delta grows with the payoff scale while the relative delta stays at
    the hours-equivalence level), extended by the documented zero-gain
    knife edge - a gain at the rounding scale of its utility difference
    can flip sign between the two chains, mapping a payoff of `0.0` or a
    tiny positive value onto the exact `-Inf` of a negative gain (and
    back). Such a pair is accepted when the finite side is within
    `VE_PAYOFF_ATOL` of zero; every other pair must satisfy the
    envelope. On bitwise (ineligible) draws the comparison is exact.
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
end

"""
    cert_config(utility::String, beta::Float64, weights)

`UtilityConfig` of one certificate case from its spec string, with the
given `(w_self, w_partner, w_transfer)` weights.
"""
function cert_config(utility::String, beta::Float64, weights)
    w_self, w_partner, w_transfer = weights
    if utility == "additive"
        func = GN.Additive()
    elseif utility == "ces"
        func = GN.CES(beta = beta)
    elseif utility == "multiplicative"
        func = GN.Multiplicative()
    elseif utility == "multiplicative_weighted"
        func = GN.MultiplicativeWeighted()
    else
        error("unknown utility spec $(repr(utility))")
    end
    return GN.UtilityConfig(
        func = func, w_self = w_self, w_partner = w_partner, w_transfer = w_transfer
    )
end

@testset "bargain certificate: envelope dominates brute force" begin
    rng = MersenneTwister(0x000EA7E1)
    specs = (
        GN.Additive(),
        GN.CES(beta = 0.2),
        GN.CES(beta = 0.5),
        GN.CES(beta = 1.5),
        GN.Multiplicative(),
        GN.MultiplicativeWeighted(),
    )
    alphas = (0.0, 0.1, 0.5, 0.9, 1.0)
    checked = 0
    for _ in 1:1500
        spec = rand(rng, specs)
        alpha = rand(rng, alphas) + (rand(rng) < 0.5 ? 0.0 : 1.0e-3 * rand(rng))
        alpha = clamp(alpha, 0.0, 1.0)
        q = rand(rng, (0.05, 0.5, 1.0, 2.0, 40.0)) * (rand(rng) < 0.5 ? 1.0 : rand(rng))
        # Both effective working-time lengths, drawn independently of
        # the partner role: the envelope is role-independent since the
        # unified `MultiplicativeWeighted` material of `MDR-0023`.
        d = rand(rng, (1.0, 2.0))
        bound = GN._material_envelope(spec, q, d, alpha)
        isnan(bound) && continue
        grid_max = 0.0
        for v in range(0.0, d; length = 4001)
            x = q * v
            Q = 2.0 - v
            value = GN.material(spec, x, Q, alpha)
            value > grid_max && (grid_max = value)
        end
        # The envelope must dominate the grid maximum; only ulp-level
        # slack is allowed (the FP soundness argument itself is the
        # `OBJECTIVE_CERT_MARGIN` plus fail open, see `ADR-0015`).
        @test bound >= grid_max * (1.0 - 8.0 * eps(Float64))
        checked += 1
    end
    @test checked >= 1000

    # Out-of-range and degenerate inputs fail open instead of certifying.
    @test isnan(GN._material_envelope(GN.Additive(), 0.0, 1.0, 0.5))
    @test isnan(GN._material_envelope(GN.Additive(), -1.0, 1.0, 0.5))
    @test isnan(GN._material_envelope(GN.Additive(), 1.0, 0.0, 0.5))
    @test isnan(GN._material_envelope(GN.Additive(), 1.0, 1.0, -0.1))
    @test isnan(GN._material_envelope(GN.Additive(), 1.0, 1.0, 1.1))
    @test isnan(GN._material_envelope(GN.CES(beta = 0.0), 1.0, 1.0, 0.5))
    @test isnan(GN._material_envelope(GN.CES(beta = -0.5), 1.0, 1.0, 0.5))
    @test isnan(GN._material_envelope(GN.CES(beta = NaN), 1.0, 1.0, 0.5))
    @test isnan(GN._material_envelope(GN.Multiplicative(), Inf, 1.0, 0.5))
end

@testset "bargain certificate: specialized CES beta == 0.5 envelope" begin
    # The specialized sqrt/square envelope of `ADR-0019` must dominate
    # the computed `material(::CES, beta=0.5, ...)` for every input (a
    # bound that does not dominate the computed utility is a stop),
    # evaluate the identical expression `material` evaluates at
    # the envelope candidates, and keep the analytic maximizer of the
    # closed form. Checked on dense brute-force grids with tiny, huge,
    # and asymmetric wages and alpha at and near its endpoints.
    spec = GN.CES(beta = 0.5)
    qs = (1.0e-8, 0.05, 0.125, 0.5, 1.0, 2.0, 40.0)
    alphas = (0.0, 1.0e-8, 0.1, 0.5, 0.9, 1.0 - 1.0e-8, 1.0)
    checked = 0
    for q in qs, alpha in alphas, d in (1.0, 2.0)
        bound = GN._material_envelope(spec, q, d, alpha)
        isnan(bound) && continue
        # Brute-force domination over a dense v grid (the computed
        # material uses the same sqrt/square grouping as the envelope
        # candidate, so the only slack is the rounding of the computed
        # consumption and leisure against `q * v` and `2 - v`).
        grid_max = 0.0
        for v in range(0.0, d; length = 20001)
            value = GN.material(spec, q * v, 2.0 - v, alpha)
            value > grid_max && (grid_max = value)
        end
        @test bound >= grid_max * (1.0 - 8.0 * eps(Float64))
        # Candidate identity: the envelope equals the largest of the
        # three `material` values at `v == 0`, `v == v_star` (the
        # closed form of `ADR-0019`, re-derived independently), and
        # `v == d` - the candidate evaluates the identical expression
        # `material` evaluates, so this is bitwise.
        if alpha <= 0.0
            v_star = 0.0
        elseif alpha >= 1.0
            v_star = d
        else
            v_star = clamp(2.0 * alpha * alpha * q / (alpha * alpha * q + (1.0 - alpha)^2), 0.0, d)
        end
        candidates = map(v -> GN.material(spec, q * v, 2.0 - v, alpha), (0.0, v_star, d))
        @test isequal(bound, maximum(candidates))
        # The analytic maximizer dominates the endpoints whenever it
        # is interior (the envelope does not depend on `v_star` being
        # located exactly, but the closed form must be the maximizer).
        if 0.0 < v_star < d
            @test candidates[2] >= max(candidates[1], candidates[3]) - 8.0 * eps(Float64) *
                max(1.0, candidates[2])
        end
        checked += 1
    end
    @test checked >= 80

    # Bound-versus-computed-utility for the specialized path: the
    # `_payoff_upper_bound` of both partner roles dominates the
    # computed `individual_utility` over a dense hours grid.
    margin = GN.OBJECTIVE_CERT_MARGIN
    for (wage_self, wage_spouse) in ((1.0e-8, 1.0), (1.0, 40.0), (40.0, 1.0), (0.125, 0.25)),
            G in (GN.Female, GN.Male),
            theta in (-1.0, -0.3, 0.0, 0.3, 1.0)
        config = cert_config("ces", 0.5, (1.0, 1.0, 1.0))
        p = GN.AgentPayoffParams{G}(
            wage_self = wage_self, wage_spouse = wage_spouse,
            alpha = 0.4, conformism = 10.0,
            N_h = 0.5, N_theta = 0.1, N_h_spouse = 0.5,
        )
        bound = GN._payoff_upper_bound(theta, p, config)
        isnan(bound) && continue
        worst = -Inf
        for h_self in range(0.0, 1.0; length = 201), h_spouse in range(0.0, 1.0; length = 201)
            u = GN.individual_utility(h_self, h_spouse, theta, p, config)
            u > worst && (worst = u)
        end
        @test worst <= bound * (1.0 + margin)
    end
end

@testset "bargain certificate: bound dominates computed utility" begin
    # Direct soundness tests of the bound itself: over randomized
    # guarded draws (fixed seed) across all four specs and both partner
    # roles, the computed `individual_utility` at every point of a
    # dense `(h_self, h_spouse)` grid in `[0, 1]^2` (101x101, including
    # the feasible corners) must stay below the per-partner bound
    # inflated by `OBJECTIVE_CERT_MARGIN` whenever the guards pass.
    # The grid resolves the 1e-4-level gaps of an unsound CES
    # amplification (see `CES_CERT_MIN_BETA`) and the maximizer
    # mislocation the endpoint-max envelope guards against.
    rng = MersenneTwister(0xB0D1F1ED)
    specs = (
        ("additive", 0.5),
        ("ces", 1.0e-12), ("ces", 1.0e-6), ("ces", 1.0e-4),
        ("ces", 1.0e-3), ("ces", 0.2), ("ces", 0.5), ("ces", 1.0),
        ("ces", 1.5), ("ces", 3.0),
        ("multiplicative", 0.5),
        ("multiplicative_weighted", 0.5),
    )
    alphas = (0.0, 0.1, 0.5, 0.9, 1.0)
    wage_pairs = (
        (0.0, 0.0), (0.0, 1.0), (1.0, 0.0), (1.0e-8, 1.0), (1.0, 1.0e-8),
        (40.0, 1.0), (1.0, 40.0), (0.125, 0.25), (0.05, 2.0),
    )
    conformisms = (0.0, 50.0, 1.0e4)
    thetas = (-1.0, -0.3, 0.0, 0.3, 1.0)
    weights = ((1.0, 1.0, 1.0), (0.0, 0.0, 0.0), (0.5, 2.0, 1.5))
    margin = GN.OBJECTIVE_CERT_MARGIN
    hours = range(0.0, 1.0; length = 101)
    draws = 0
    bounded = 0
    for (utility, beta) in specs, G in (GN.Female, GN.Male), _ in 1:25
        config = cert_config(utility, beta, rand(rng, weights))
        wage_self, wage_spouse = rand(rng, wage_pairs)
        p = GN.AgentPayoffParams{G}(
            wage_self = wage_self, wage_spouse = wage_spouse,
            alpha = rand(rng, alphas),
            conformism = rand(rng, conformisms),
            N_h = rand(rng) * 1.5 - 0.25,
            N_theta = rand(rng) * 2.0 - 1.0,
            N_h_spouse = rand(rng) * 1.5 - 0.25,
        )
        theta = rand(rng, thetas)
        draws += 1
        bound = GN._payoff_upper_bound(theta, p, config)
        if utility == "ces" && beta < GN.CES_CERT_MIN_BETA
            # Below the certified band the certificate fails open
            # unconditionally (`CES_CERT_MIN_BETA`, `ADR-0015`).
            @test isnan(bound)
            continue
        end
        isnan(bound) && continue
        bounded += 1
        worst = -Inf
        for h_self in hours, h_spouse in hours
            u = GN.individual_utility(h_self, h_spouse, theta, p, config)
            u > worst && (worst = u)
        end
        @test worst <= bound * (1.0 + margin)
    end
    @test draws == 600
    @test bounded >= 200
end

@testset "bargain certificate: CES small-beta counterexample fails open" begin
    # Reviewer regression case: CES with `beta = 1e-12`, man as payer
    # at `theta = 0.2`, `wage_self = 0.125`, `alpha = 0.3`, zero
    # conformism and zero norm weights. The pre-fix envelope bound
    # 0.5440988918819328 was below the computed utility
    # 0.5442197195194871 at the feasible hours (598/1001, 0), so a
    # man's outside option between the two values made
    # `_objective_prunable` certify while `nash_product` stayed finite.
    config = cert_config("ces", 1.0e-12, (0.0, 0.0, 0.0))
    pm = GN.AgentPayoffParams{GN.Male}(
        wage_self = 0.125, wage_spouse = 0.25, alpha = 0.3, conformism = 0.0,
        N_h = 0.0, N_theta = 0.0, N_h_spouse = 0.0,
    )
    pw = GN.AgentPayoffParams{GN.Female}(
        wage_self = 0.25, wage_spouse = 0.125, alpha = 0.3, conformism = 0.0,
        N_h = 0.0, N_theta = 0.0, N_h_spouse = 0.0,
    )
    theta = 0.2
    u = GN.individual_utility(598 / 1001, 0.0, theta, pm, config)
    @test isfinite(u)
    # With the `CES_CERT_MIN_BETA` floor guard the certificate fails
    # open here instead of certifying on the unsound bound.
    @test isnan(GN._payoff_upper_bound(theta, pm, config))
    um_out = 0.54415   # between the pre-fix bound and the computed utility
    uw_out = 0.0
    @test !GN._objective_prunable(theta, uw_out, um_out, pw, pm, config)
    # The Nash product at the feasible pair (hw, hm) = (0, 598/1001) is
    # finite there: the man gains at (598/1001, 0), the woman gains as
    # the recipient, so a false prune would have destroyed a finite
    # objective value.
    np = GN.nash_product(theta, 0.0, 598 / 1001, uw_out, um_out, pw, pm, config)
    @test isfinite(np)
    @test np > 0.0
    # Positive control: the same configuration just above the floor
    # certifies soundly again, with the bound dominating the computed
    # utility over a dense grid.
    config_floor = cert_config("ces", 1.0e-3, (0.0, 0.0, 0.0))
    bound = GN._payoff_upper_bound(theta, pm, config_floor)
    @test isfinite(bound)
    worst = -Inf
    for h_self in range(0.0, 1.0; length = 101), h_spouse in range(0.0, 1.0; length = 101)
        v = GN.individual_utility(h_self, h_spouse, theta, pm, config_floor)
        v > worst && (worst = v)
    end
    @test worst <= bound * (1.0 + GN.OBJECTIVE_CERT_MARGIN)
end

@testset "bargain certificate: soundness fuzz" begin
    rng = MersenneTwister(0x0005A17D)
    specs = (
        ("additive", 0.5),
        ("ces", 0.2),
        ("ces", 0.5),
        ("ces", 1.5),
        ("ces", -0.5),
        ("ces", 0.0),
        ("multiplicative", 0.5),
        ("multiplicative_weighted", 0.5),
    )
    alphas = (0.0, 0.1, 0.5, 0.9, 1.0)
    conformisms = (0.0, 10.0, 50.0, 1.0e4)
    weights = (
        (1.0, 1.0, 1.0), (0.0, 1.0, 1.0), (1.0, 0.0, 1.0), (1.0, 1.0, 0.0),
        (0.5, 2.0, 1.5), (0.0, 0.0, 0.0),
    )
    decisions = 0
    pruned = 0
    for _ in 1:1400
        utility, beta = rand(rng, specs)
        config = cert_config(utility, beta, rand(rng, weights))
        wage_pair = rand(
            rng, (
                (0.0, 0.0), (0.0, 1.0), (1.0, 0.0), (1.0, 40.0), (40.0, 1.0),
                (0.05, 2.0), (2.0, 0.05),
            )
        )
        if rand(rng) < 0.5
            wage_pair = (wage_pair[1] * rand(rng), wage_pair[2] * rand(rng))
        end
        pw = GN.AgentPayoffParams{GN.Female}(
            wage_self = wage_pair[1],
            wage_spouse = wage_pair[2],
            alpha = rand(rng, alphas),
            conformism = rand(rng, conformisms) * (rand(rng) < 0.5 ? 1.0 : rand(rng)),
            N_h = rand(rng) * 1.5 - 0.25,
            N_theta = rand(rng) * 2.0 - 1.0,
            N_h_spouse = rand(rng) * 1.5 - 0.25,

        )
        pm = GN.AgentPayoffParams{GN.Male}(
            wage_self = wage_pair[2],
            wage_spouse = wage_pair[1],
            alpha = rand(rng, alphas),
            conformism = rand(rng, conformisms) * (rand(rng) < 0.5 ? 1.0 : rand(rng)),
            N_h = rand(rng) * 1.5 - 0.25,
            N_theta = rand(rng) * 2.0 - 1.0,
            N_h_spouse = rand(rng) * 1.5 - 0.25,

        )
        hw_init = rand(rng, (0.0, 1.0, 0.5)) + (rand(rng) < 0.5 ? 0.0 : 0.4 * rand(rng))
        hm_init = rand(rng, (0.0, 1.0, 0.5)) + (rand(rng) < 0.5 ? 0.0 : 0.4 * rand(rng))
        theta_init = rand(rng) * 2.4 - 1.2

        # The certificate's claim is independent of the warm start; the
        # fuzz uses the status-quo equilibrium exactly as
        # `bargain_transfer` does.
        theta0 = clamp(theta_init, -1.0, 1.0)
        uw_out, um_out = outside_options_reference(hw_init, hm_init, pw, pm, config)
        hw_status, hm_status =
            mutual_best_response_reference(hw_init, hm_init, theta0, pw, pm, config)
        thetas = (0.0, -0.0, 1.0, -1.0, theta0)
        for _ in 1:5
            thetas = (thetas..., rand(rng) * 2.0 - 1.0)
        end
        for theta in thetas
            decisions += 1
            prunable = GN._objective_prunable(theta, uw_out, um_out, pw, pm, config)
            payoff = first(
                equilibrium_payoff_reference(
                    theta, hw_status, hm_status, uw_out, um_out, pw, pm, config
                )
            )
            # Objective-level equality: the live solver chain equals the
            # frozen reference bitwise where the arithmetic is unchanged
            # and within the `MDR-0013` validated-equivalence envelope
            # for `CES` `beta == 0.5`.
            live_payoff = first(
                GN.equilibrium_payoff(
                    theta, hw_status, hm_status, uw_out, um_out, pw, pm, config
                )
            )
            relaxed = solver_relaxed(config, theta0, pw, pm)
            @test payoff_equiv(live_payoff, payoff, config, relaxed)
            if prunable
                pruned += 1
                # Soundness: a certified prune must be the exact `-Inf`
                # that `nash_product` would have returned, in the frozen
                # and in the live chain alike (the certificate bounds
                # the computed utility of both within
                # `OBJECTIVE_CERT_MARGIN`).
                @test isequal(payoff, -Inf)
                @test isequal(live_payoff, -Inf)
            end
        end
        # A zero gain at the status-quo transfer is feasible and yields
        # the finite payoff 0.0, so `theta == 0.0` must never certify
        # against the true outside options.
        @test !GN._objective_prunable(0.0, uw_out, um_out, pw, pm, config)
    end
    @test decisions >= 10000
    @test pruned >= 1000
end

@testset "bargain certificate: objective matches reference near the bound" begin
    # Adversarial boundary cases: bisect to transfers where the
    # certified bound equals the outside option to within a few ulps,
    # so the `OBJECTIVE_CERT_MARGIN` is load-bearing, and require the
    # pruned objective value to equal the reference payoff there and at
    # the neighbouring representable transfers.
    cases = (
        (cert_config("ces", 0.5, (1.0, 1.0, 1.0)), 0.6, 1.2, 10.0, 0.5, 0.0),
        (cert_config("additive", 0.5, (1.0, 1.0, 1.0)), 1.0, 1.0, 50.0, 0.9, 0.3),
        (cert_config("multiplicative_weighted", 0.5, (1.0, 1.0, 1.0)), 0.05, 2.0, 20.0, 0.1, -0.2),
        (cert_config("multiplicative", 0.5, (1.0, 1.0, 1.0)), 2.0, 0.05, 5.0, 1.0, 0.1),
    )
    for (config, wage_self, wage_spouse, conformism, alpha, n_theta) in cases
        pw = GN.AgentPayoffParams{GN.Female}(
            wage_self = wage_self, wage_spouse = wage_spouse, alpha = alpha,
            conformism = conformism, N_h = 0.5, N_theta = n_theta, N_h_spouse = 0.5,

        )
        pm = GN.AgentPayoffParams{GN.Male}(
            wage_self = wage_spouse, wage_spouse = wage_self, alpha = alpha,
            conformism = conformism, N_h = 0.5, N_theta = n_theta, N_h_spouse = 0.5,

        )
        hw_init, hm_init = 0.5, 0.5
        uw_out, um_out = outside_options_reference(hw_init, hm_init, pw, pm, config)
        isfinite(uw_out) && isfinite(um_out) || continue
        hw_status, hm_status = mutual_best_response_reference(hw_init, hm_init, 0.0, pw, pm, config)
        margin = GN.OBJECTIVE_CERT_MARGIN
        # Certified decision as a function of theta, on the woman bound.
        certified(theta) = begin
            bound = GN._payoff_upper_bound(theta, pw, config)
            isfinite(bound) && bound * (1.0 + margin) < uw_out
        end
        bracket = nothing
        prev_theta = -1.0
        prev_decision = certified(prev_theta)
        for theta in range(-1.0, 1.0; length = 2001)
            decision = certified(theta)
            if decision != prev_decision
                # Keep two consecutive grid points with opposite
                # decisions: bisecting a pair that agrees on both ends
                # (e.g. `prevfloat` of the first certified point, which
                # can itself be certified) proves nothing about the
                # decision boundary.
                bracket = (prev_theta, theta)
                break
            end
            prev_theta = theta
            prev_decision = decision
        end
        @test bracket !== nothing
        bracket === nothing && continue
        lo, hi = bracket
        lo_decision = certified(lo)
        hi_decision = certified(hi)
        @test lo_decision != hi_decision
        for _ in 1:80
            mid = (lo + hi) / 2
            # Bisect while preserving each endpoint's decision, so the
            # bracket keeps straddling the boundary in either
            # orientation.
            certified(mid) == lo_decision ? (lo = mid) : (hi = mid)
        end
        # The decision still flips across the bisected interval, so the
        # bracket sits on the boundary at the resolution of adjacent
        # Float64 values.
        @test certified(lo) == lo_decision
        @test certified(hi) == hi_decision
        @test certified(lo) != certified(hi)
        for theta in (lo, hi, prevfloat(lo), nextfloat(hi))
            prunable = GN._objective_prunable(theta, uw_out, um_out, pw, pm, config)
            payoff = first(
                equilibrium_payoff_reference(
                    theta, hw_status, hm_status, uw_out, um_out, pw, pm, config
                )
            )
            if prunable
                @test isequal(payoff, -Inf)
            end
            objective_value = prunable ? -Inf :
                first(
                    GN.equilibrium_payoff(
                        theta, hw_status, hm_status, uw_out, um_out, pw, pm, config
                    )
                )
            relaxed = solver_relaxed(config, theta, pw, pm)
            @test equiv(objective_value, payoff, VE_PAYOFF_ATOL, config, relaxed)
        end
    end
end

@testset "bargain certificate: boundary and fallback cases" begin
    specs = (
        ("additive", 0.5),
        ("ces", 0.2),
        ("ces", 1.5),
        ("ces", -0.5),
        ("ces", 0.0),
        ("multiplicative", 0.5),
        ("multiplicative_weighted", 0.5),
    )
    # Boundary draws: zero wages, zero conformism, zero weights, alpha
    # at 0 and 1, status-quo transfers at the bracket endpoints and
    # beyond, and non-finite outside options (zero wages on both
    # sides). The objective-level solver chain must match the frozen
    # reference bitwise on every draw (zero-wage and zero-conformism
    # households included), and a certified prune must still be the
    # exact `-Inf` of the reference objective. The `bargain_transfer`
    # result contract is checked in `test/test_bargaining_equivalence.jl`
    # and `test/test_transfer_search.jl` (see `MDR-0012`).
    for (utility, beta) in specs, alpha in (0.0, 1.0), (w_self, w_spouse) in (
                (0.0, 0.0), (0.0, 1.0), (1.0, 0.0), (1.0, 40.0), (40.0, 1.0),
            ), theta_init in (-1.0, 1.0, -1.5, 1.5, 0.0, -0.0), weights in (
                (1.0, 1.0, 1.0), (0.0, 0.0, 0.0),
            ), conformism in (0.0, 50.0)
        config = cert_config(utility, beta, weights)
        pw = GN.AgentPayoffParams{GN.Female}(
            wage_self = w_self, wage_spouse = w_spouse, alpha = alpha, conformism = conformism,
            N_h = 0.5, N_theta = 0.0, N_h_spouse = 0.5,
        )
        pm = GN.AgentPayoffParams{GN.Male}(
            wage_self = w_spouse, wage_spouse = w_self, alpha = alpha, conformism = conformism,
            N_h = 0.5, N_theta = 0.0, N_h_spouse = 0.5,
        )
        theta0 = clamp(theta_init, -1.0, 1.0)
        relaxed = solver_relaxed(config, theta0, pw, pm)
        live_mbr = GN.mutual_best_response(0.5, 0.4, theta0, pw, pm, config)
        ref_mbr = mutual_best_response_reference(0.5, 0.4, theta0, pw, pm, config)
        @test equiv(live_mbr[1], ref_mbr[1], VE_HOURS_ATOL, config, relaxed)
        @test equiv(live_mbr[2], ref_mbr[2], VE_HOURS_ATOL, config, relaxed)
        live_uw, live_um = GN.outside_options(0.5, 0.4, pw, pm, config)
        ref_uw, ref_um = outside_options_reference(0.5, 0.4, pw, pm, config)
        @test equiv(live_uw, ref_uw, VE_UTIL_ATOL, config, relaxed; rtol = VE_UTIL_RTOL)
        @test equiv(live_um, ref_um, VE_UTIL_ATOL, config, relaxed; rtol = VE_UTIL_RTOL)
        @test payoff_equiv(
            GN.nash_product(theta0, live_mbr..., live_uw, live_um, pw, pm, config),
            nash_product_reference(theta0, ref_mbr..., ref_uw, ref_um, pw, pm, config),
            config, relaxed,
        )
        for theta in (-1.0, -0.3, 0.0, 0.3, 1.0)
            prunable = GN._objective_prunable(theta, live_uw, live_um, pw, pm, config)
            ref_payoff = first(
                equilibrium_payoff_reference(
                    theta, ref_mbr..., ref_uw, ref_um, pw, pm, config
                )
            )
            live_payoff = first(
                GN.equilibrium_payoff(
                    theta, live_mbr..., live_uw, live_um, pw, pm, config
                )
            )
            @test payoff_equiv(live_payoff, ref_payoff, config, relaxed)
            if prunable
                # The certificate bounds the computed utility over every
                # working-time pair, so the exact `-Inf` claim is
                # chain-independent against the live outside options it
                # certifies with; the frozen-reference claim holds on
                # the bitwise (ineligible) draws and wherever the
                # outside options did not move.
                @test isequal(live_payoff, -Inf)
                if !relaxed || (isequal(live_uw, ref_uw) && isequal(live_um, ref_um))
                    @test isequal(ref_payoff, -Inf)
                end
            end
        end
    end
end

# Probe utility specs for the fast-path test below: counting
# `material` methods that observe how often the solver chain evaluates
# a utility, so the non-finite-outside fast path of `bargain_transfer`
# can be shown to skip the transfer search entirely (see `ADR-0015`).

struct ProbeCounted <: GN.UtilitySpec end

struct ProbeCountedNaN <: GN.UtilitySpec end

const PROBE_COUNT = Ref(0)

function GN.material(::ProbeCounted, x::Float64, Q::Float64, alpha::Float64)
    PROBE_COUNT[] += 1
    return alpha * sqrt(x) + (1.0 - alpha) * sqrt(Q)
end

function GN.material(
        ::ProbeCountedNaN, x::Float64, Q::Float64, alpha::Float64
    )
    PROBE_COUNT[] += 1
    return NaN
end

"""
    material_reference(::ProbeCounted, x::Float64, Q::Float64, alpha::Float64)

Frozen-reference counterpart of `GN.material(::ProbeCounted, ...)`: the
frozen oracle routes every utility through `material_reference`, so the
probe specs extend it with the identical counting delegation (the
oracle file itself stays untouched).
"""
material_reference(::ProbeCounted, x::Float64, Q::Float64, alpha::Float64) =
    GN.material(ProbeCounted(), x, Q, alpha)

"""
    material_reference(::ProbeCountedNaN, x::Float64, Q::Float64, alpha::Float64)

Frozen-reference counterpart of `GN.material(::ProbeCountedNaN, ...)`;
see `material_reference(::ProbeCounted, ...)`.
"""
material_reference(::ProbeCountedNaN, x::Float64, Q::Float64, alpha::Float64) =
    GN.material(ProbeCountedNaN(), x, Q, alpha)

"""
    probe_replay_count(theta_init::Float64, pw, pm, config)

Number of `material` evaluations of the exact pre-search phase of
`bargain_transfer`: the outside-option solve, the two outside-option
utilities, the status-quo solve (reused exactly when the clamped
status-quo transfer is bitwise `+0.0`, see `ADR-0015`), and the status
Nash product. The calls mirror `bargain_transfer` exactly, so the count
equals the live count whenever the transfer search is skipped. Counted
with the probe `config`, which must use one of the counting probe
specs.
"""
function probe_replay_count(
        theta_init::Float64, pw::GN.AgentPayoffParams, pm::GN.AgentPayoffParams, config
    )
    theta0 = clamp(theta_init, -1.0, 1.0)
    before = PROBE_COUNT[]
    hw_out, hm_out = GN.mutual_best_response(0.5, 0.4, 0.0, pw, pm, config)
    uw_out = GN.individual_utility(hw_out, hm_out, 0.0, pw, config)
    um_out = GN.individual_utility(hm_out, hw_out, 0.0, pm, config)
    hw_status, hm_status = theta0 === 0.0 ? (hw_out, hm_out) :
        GN.mutual_best_response(0.5, 0.4, theta0, pw, pm, config)
    GN.nash_product(theta0, hw_status, hm_status, uw_out, um_out, pw, pm, config)
    return PROBE_COUNT[] - before
end

@testset "bargain certificate: non-finite-outside fast path" begin
    pw = GN.AgentPayoffParams{GN.Female}(
        wage_self = 0.6, wage_spouse = 1.2, alpha = 0.5, conformism = 10.0,
        N_h = 0.5, N_theta = 0.0, N_h_spouse = 0.5,
    )
    pm = GN.AgentPayoffParams{GN.Male}(
        wage_self = 1.2, wage_spouse = 0.6, alpha = 0.5, conformism = 10.0,
        N_h = 0.5, N_theta = 0.0, N_h_spouse = 0.5,
    )
    for theta_init in (0.0, 0.3, -0.3)
        # Control run with finite outside options: the search runs and
        # evaluates more utilities than the pre-search phase alone.
        config = GN.UtilityConfig(func = ProbeCounted())
        expected = probe_replay_count(theta_init, pw, pm, config)
        PROBE_COUNT[] = 0
        live = GN.bargain_transfer(0.5, 0.4, theta_init, pw, pm, config)
        searched = PROBE_COUNT[]
        @test searched > expected

        # Non-finite outside options (the probe returns NaN): the fast
        # path must skip the search, so the utility count equals the
        # pre-search phase exactly, and the result stays bit-identical
        # to the frozen reference (which runs the full search on an
        # all-non-finite objective and falls back to the status quo).
        config_nan = GN.UtilityConfig(func = ProbeCountedNaN())
        expected_nan = probe_replay_count(theta_init, pw, pm, config_nan)
        PROBE_COUNT[] = 0
        live_nan = GN.bargain_transfer(0.5, 0.4, theta_init, pw, pm, config_nan)
        skipped = PROBE_COUNT[]
        PROBE_COUNT[] = 0
        ref_nan = bargain_transfer_reference(0.5, 0.4, theta_init, pw, pm, config_nan)
        reference_count = PROBE_COUNT[]
        @test skipped == expected_nan
        @test reference_count > skipped
        @test isequal(live_nan[1], ref_nan[1])
        @test isequal(live_nan[2], ref_nan[2])
        @test isequal(live_nan[3], ref_nan[3])
    end
end

@testset "bargain certificate: decision helper allocations" begin
    pw = GN.AgentPayoffParams{GN.Female}(
        wage_self = 0.6, wage_spouse = 1.2, alpha = 0.5, conformism = 10.0,
        N_h = 0.5, N_theta = 0.0, N_h_spouse = 0.5,
    )
    pm = GN.AgentPayoffParams{GN.Male}(
        wage_self = 1.2, wage_spouse = 0.6, alpha = 0.5, conformism = 10.0,
        N_h = 0.5, N_theta = 0.0, N_h_spouse = 0.5,
    )
    config = cert_config("ces", 0.5, (1.0, 1.0, 1.0))
    GN._objective_prunable(0.3, 1.0, 1.0, pw, pm, config)
    # The decision helper runs inside the payoff-only objective once
    # per sampled transfer; it must not allocate (see `MDR-0002` on the
    # boxing this guard exists to avoid).
    @test (@allocated GN._objective_prunable(0.3, 1.0, 1.0, pw, pm, config)) == 0
end
