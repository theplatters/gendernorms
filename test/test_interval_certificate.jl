# Soundness tests for the interval-exclusion certificate
# `_objective_interval_prunable` and its per-partner bound
# `_payoff_interval_bound` of `ADR-0017` (Stage A prefilter of the
# payoff-only transfer objective; optimization-only, not ported
# NetLogo behavior). The contract under test is soundness, not
# coverage: whenever the interval certificate claims a closed interval,
# EVERY transfer of that interval must have the directly computed Nash
# payoff `-Inf` - checked at the endpoints, at boundary-adjacent
# representable floats, and at sampled interior points, across all four
# utility specs and the guard paths. Every uncertain input must fail
# open. The zero point (both signed zeros) is a payer point for both
# partners and is excluded only when the pointwise
# `_objective_prunable` would exclude it; that rule is tested
# explicitly. The solver semantics are pinned by `MDR-0002` and
# `MDR-0012`; the certificate must never change them.

using GenderNorms
using Random
using Test

const GN = GenderNorms

# Unenveloped probe spec for the fail-open path: a `UtilitySpec`
# subtype without a certified `_material_envelope` must never certify
# on a material bound (only the exact zero-wage rule may).
struct IntervalUnknown <: GN.UtilitySpec end

GN.material(::IntervalUnknown, x::Float64, Q::Float64, alpha::Float64) =
    alpha * sqrt(x) + (1 - alpha) * sqrt(Q)

"""
    interval_config(utility::String, beta::Float64, weights)

`UtilityConfig` of one interval case from its spec string, with the
given `(w_self, w_partner, w_transfer)` weights.
"""
function interval_config(utility::String, beta::Float64, weights)
    w_self, w_partner, w_transfer = weights
    if utility == "additive"
        func = GN.Additive()
    elseif utility == "ces"
        func = GN.CES(beta = beta)
    elseif utility == "multiplicative"
        func = GN.Multiplicative()
    elseif utility == "multiplicative_weighted"
        func = GN.MultiplicativeWeighted()
    elseif utility == "unknown"
        func = IntervalUnknown()
    else
        error("unknown utility spec $(repr(utility))")
    end
    return GN.UtilityConfig(
        func = func, w_self = w_self, w_partner = w_partner, w_transfer = w_transfer
    )
end

"""
    interval_payoff(theta::Float64, hw_start::Float64, hm_start::Float64, uw_out::Float64, um_out::Float64, pw, pm, config)

The directly computed Nash payoff of the reference solver chain at
transfer `theta` (the `equilibrium_payoff` of `bargain_transfer`), warm
started like the search objective. Returns a `Float64`.
"""
function interval_payoff(
        theta::Float64, hw_start::Float64, hm_start::Float64,
        uw_out::Float64, um_out::Float64,
        pw::GN.AgentPayoffParams, pm::GN.AgentPayoffParams, config,
    )
    return first(
        GN.equilibrium_payoff(
            theta, hw_start, hm_start, uw_out, um_out, pw, pm, config
        )
    )
end

@testset "interval certificate: zero point and signed zeros" begin
    # The zero point is excluded through the interval path only when
    # the pointwise `_objective_prunable` would exclude it; the signed
    # zeros `-0.0` and `+0.0` share one decision and one payoff.
    config = interval_config("ces", 0.5, (1.0, 1.0, 1.0))
    # A household whose zero-transfer payoff is the finite 0.0 of the
    # status quo: no interval containing zero may certify.
    pw = GN.AgentPayoffParams(
        wage_self = 1.0, wage_spouse = 1.0, alpha = 0.5, conformism = 1.0,
        N_h = 0.5, N_theta = 0.0, N_h_spouse = 0.5, is_woman = true,
    )
    pm = GN.AgentPayoffParams(
        wage_self = 1.0, wage_spouse = 1.0, alpha = 0.5, conformism = 1.0,
        N_h = 0.5, N_theta = 0.0, N_h_spouse = 0.5, is_woman = false,
    )
    uw_out, um_out = GN.outside_options(0.5, 0.5, pw, pm, config)
    @test isfinite(uw_out) && isfinite(um_out)
    @test !GN._objective_prunable(0.0, uw_out, um_out, pw, pm, config)
    @test !GN._objective_prunable(-0.0, uw_out, um_out, pw, pm, config)
    for (lo, hi) in (
            (0.0, 0.0), (-0.0, -0.0), (-0.0, 0.0), (0.0, -0.0),
            (-0.0, 0.5), (0.0, 0.5), (-0.5, -0.0), (-0.5, 0.0), (-0.5, 0.5),
        )
        @test !GN._objective_interval_prunable(lo, hi, uw_out, um_out, pw, pm, config)
    end
    # Against the true outside options the zero point is a feasible
    # zero-gain point (finite payoff 0.0) and never certifies, so no
    # interval containing zero ever certifies. The exclusion path for
    # zero is reachable only when the pointwise logic also excludes it,
    # which needs outside options above the zero-transfer utility: with
    # `uw_out == um_out == 5.0` both partners gain negatively at every
    # transfer, the pointwise certificate excludes zero, and the
    # interval certificate may exclude intervals containing it. The
    # directly computed payoff at both signed zeros is `-Inf` there.
    @test GN._objective_prunable(0.0, 5.0, 5.0, pw, pm, config)
    @test GN._objective_prunable(-0.0, 5.0, 5.0, pw, pm, config)
    for (lo, hi) in ((-0.5, 0.5), (-0.0, 0.5), (-0.5, 0.0), (-0.5, -0.0), (0.0, 0.5), (0.0, 0.0))
        @test GN._objective_interval_prunable(lo, hi, 5.0, 5.0, pw, pm, config)
        for theta in (0.0, -0.0, lo, hi)
            @test isequal(
                interval_payoff(
                    theta, 0.5, 0.5, 5.0, 5.0, pw, pm, config
                ), -Inf
            )
        end
    end
    # Asymmetric outside options: only the man's zero point is
    # excludable against 5.0; whatever the interval decision is, it
    # must be sound at the signed zeros.
    @test GN._objective_prunable(0.0, uw_out, 5.0, pw, pm, config)
    for theta in (0.0, -0.0)
        if GN._objective_interval_prunable(-0.5, 0.5, uw_out, 5.0, pw, pm, config)
            @test isequal(interval_payoff(theta, 0.5, 0.5, uw_out, 5.0, pw, pm, config), -Inf)
        end
    end
end

@testset "interval certificate: fail-open guards" begin
    # Non-finite and out-of-range inputs, non-finite outside options,
    # and unenveloped utility specs fail open (never certify) except
    # for the exact zero-wage rule, which is spec-independent.
    config = interval_config("ces", 0.5, (1.0, 1.0, 1.0))
    pw = GN.AgentPayoffParams(
        wage_self = 1.0, wage_spouse = 1.0, alpha = 0.5, conformism = 50.0,
        N_h = 0.5, N_theta = 0.9, N_h_spouse = 0.5, is_woman = true,
    )
    pm = GN.AgentPayoffParams(
        wage_self = 1.0, wage_spouse = 1.0, alpha = 0.5, conformism = 50.0,
        N_h = 0.5, N_theta = -0.9, N_h_spouse = 0.5, is_woman = false,
    )
    uw_out, um_out = GN.outside_options(0.5, 0.5, pw, pm, config)
    # Sanity: this household certifies on a far slab away from the
    # domain boundary.
    @test GN._objective_interval_prunable(0.4, 0.9, uw_out, um_out, pw, pm, config)
    # A slab reaching `theta == 1.0` mixes exactly-zero consumption at
    # its endpoint with positive consumption inside; the subnormal
    # consumption band there makes the pointwise certificate fail open
    # on real transfers, so the interval certificate fails open too
    # (the bisection descends to pointwise checks at the boundary).
    @test !GN._objective_interval_prunable(0.4, 1.0, uw_out, um_out, pw, pm, config)
    @test !GN._objective_interval_prunable(-1.0, -0.4, uw_out, um_out, pw, pm, config)
    for (lo, hi) in (
            (NaN, 0.5), (0.0, NaN), (-Inf, 0.5), (0.0, Inf),
            (0.5, 0.4), (1.0, 1.5), (-1.5, -1.0), (-1.5, 1.5),
        )
        @test !GN._objective_interval_prunable(lo, hi, uw_out, um_out, pw, pm, config)
    end
    @test !GN._objective_interval_prunable(0.4, 0.9, NaN, um_out, pw, pm, config)
    @test !GN._objective_interval_prunable(0.4, 0.9, uw_out, Inf, pw, pm, config)
    # Non-finite and out-of-range parameter guards (mirror the draws of
    # the pointwise certificate).
    for (wage_self, wage_spouse, alpha, conformism) in (
            (NaN, 1.0, 0.5, 10.0), (1.0, -1.0, 0.5, 10.0), (1.0, 1.0, 1.5, 10.0),
            (1.0, 1.0, 0.5, NaN), (1.0, 1.0, 0.5, -1.0),
        )
        bad_w = GN.AgentPayoffParams(
            wage_self = wage_self, wage_spouse = wage_spouse, alpha = alpha, conformism = conformism,
            N_h = 0.5, N_theta = 0.0, N_h_spouse = 0.5, is_woman = true,
        )
        bad_m = GN.AgentPayoffParams(
            wage_self = wage_spouse, wage_spouse = wage_self, alpha = alpha, conformism = conformism,
            N_h = 0.5, N_theta = 0.0, N_h_spouse = 0.5, is_woman = false,
        )
        @test !GN._objective_interval_prunable(0.4, 0.9, 1.0, 1.0, bad_w, bad_m, config)
    end
    # Unknown `UtilitySpec`: no material envelope, so no certification
    # on a material bound; the exact zero-wage rule is the only
    # exception and is sound for every spec.
    unknown = interval_config("unknown", 0.5, (1.0, 1.0, 1.0))
    @test !GN._objective_interval_prunable(0.4, 0.9, uw_out, um_out, pw, pm, unknown)
    zero_wage_w = GN.AgentPayoffParams(
        wage_self = 0.0, wage_spouse = 0.0, alpha = 0.5, conformism = 0.0,
        N_h = 0.5, N_theta = 0.0, N_h_spouse = 0.5, is_woman = true,
    )
    zero_wage_m = GN.AgentPayoffParams(
        wage_self = 0.0, wage_spouse = 0.0, alpha = 0.5, conformism = 0.0,
        N_h = 0.5, N_theta = 0.0, N_h_spouse = 0.5, is_woman = false,
    )
    # With zero wages every consumption is exactly zero, so every
    # transfer is `-Inf` for both partners under every spec, including
    # the unenveloped one (the exact `x <= 0 -> -Inf` rule of
    # `ADR-0015`); with finite outside options the interval certificate
    # excludes the whole slab.
    @test GN._objective_interval_prunable(0.4, 1.0, 1.0, 1.0, zero_wage_w, zero_wage_m, unknown)
    hw_zero, hm_zero = GN.mutual_best_response(0.5, 0.5, 0.0, zero_wage_w, zero_wage_m, unknown)
    for theta in (0.4, 1.0, 0.7)
        @test isequal(interval_payoff(theta, hw_zero, hm_zero, 1.0, 1.0, zero_wage_w, zero_wage_m, unknown), -Inf)
    end
    # Mixed zero/nonzero consumption ranges fail open right next to
    # the exact rule: `mixed_w` receives on a positive slab with
    # `wage_self == 0` and `wage_spouse > 0`, so her consumption is
    # zero at `theta == 0` but positive inside, and the man's payer
    # consumption is positive throughout; the unknown spec rules out
    # any material certification, and the directly computed payoff is
    # FINITE inside the slab, so declining is mandatory (parity
    # genuinely fails there).
    mixed_w = GN.AgentPayoffParams(
        wage_self = 0.0, wage_spouse = 1.0, alpha = 0.5, conformism = 0.0,
        N_h = 0.5, N_theta = 0.0, N_h_spouse = 0.5, is_woman = true,
    )
    mixed_m = GN.AgentPayoffParams(
        wage_self = 1.0, wage_spouse = 0.0, alpha = 0.5, conformism = 0.0,
        N_h = 0.5, N_theta = 0.0, N_h_spouse = 0.5, is_woman = false,
    )
    @test !GN._objective_interval_prunable(0.0, 0.5, 0.1, 0.1, mixed_w, mixed_m, unknown)
    @test isfinite(interval_payoff(0.25, 0.5, 0.5, 0.1, 0.1, mixed_w, mixed_m, unknown))
    # The exact rule strengthens certification only where it holds: the
    # woman pays on the negative slab with zero wage, so her
    # consumption (and the Nash payoff) is exactly `-Inf` at every
    # transfer there and the slab certifies.
    @test GN._objective_interval_prunable(-0.5, -0.2, 1.0, 1.0, mixed_w, mixed_m, unknown)
    for theta in (-0.5, -0.2, -0.35)
        @test isequal(interval_payoff(theta, 0.5, 0.5, 1.0, 1.0, mixed_w, mixed_m, unknown), -Inf)
    end
end

@testset "interval certificate: CES certified band" begin
    # Below `CES_CERT_MIN_BETA` the interval certificate fails open on
    # the envelope path exactly like the pointwise one; at and above
    # the floor it certifies the same far slab.
    pw = GN.AgentPayoffParams(
        wage_self = 0.125, wage_spouse = 0.25, alpha = 0.3, conformism = 50.0,
        N_h = 0.5, N_theta = 0.9, N_h_spouse = 0.5, is_woman = true,
    )
    pm = GN.AgentPayoffParams(
        wage_self = 0.25, wage_spouse = 0.125, alpha = 0.3, conformism = 50.0,
        N_h = 0.5, N_theta = -0.9, N_h_spouse = 0.5, is_woman = false,
    )
    for beta in (1.0e-12, 1.0e-6, 0.5e-3, 0.999e-3)
        config = interval_config("ces", beta, (1.0, 1.0, 1.0))
        uw_out, um_out = GN.outside_options(0.5, 0.5, pw, pm, config)
        (isfinite(uw_out) && isfinite(um_out)) || continue
        @test !GN._objective_interval_prunable(0.4, 0.9, uw_out, um_out, pw, pm, config)
    end
    for beta in (1.0e-3, 1.001e-3, 0.5, 1.5)
        config = interval_config("ces", beta, (1.0, 1.0, 1.0))
        uw_out, um_out = GN.outside_options(0.5, 0.5, pw, pm, config)
        (isfinite(uw_out) && isfinite(um_out)) || continue
        @test GN._objective_interval_prunable(0.4, 0.9, uw_out, um_out, pw, pm, config)
        hw_status, hm_status = GN.mutual_best_response(0.5, 0.5, 0.0, pw, pm, config)
        for theta in (0.4, 0.9, nextfloat(0.4), prevfloat(0.9), 0.7)
            @test isequal(
                interval_payoff(
                    theta, hw_status, hm_status, uw_out, um_out, pw, pm, config
                ), -Inf
            )
        end
    end
end

@testset "interval certificate: soundness fuzz" begin
    # Randomized slabs across all four utility specs and the guard
    # paths: wherever the interval certificate returns true, the
    # directly computed `equilibrium_payoff` must be exactly `-Inf` at
    # the endpoints, at boundary-adjacent representable floats, and at
    # sampled interior points (and the pointwise certificate must agree
    # at every sampled point: interval exclusion never removes a
    # solve). Every scenario draws slabs on either side of and
    # containing the norm `N_theta`, zero-touching slabs with signed
    # zeros, and free slabs. At least 10000 interval decisions, zero
    # unsound.
    rng = MersenneTwister(0x01A7E2A1)
    specs = (
        ("additive", 0.5),
        ("ces", 1.0e-12), ("ces", 0.5e-3), ("ces", 1.0e-3), ("ces", 1.5e-3),
        ("ces", 0.5), ("ces", 1.5),
        ("multiplicative", 0.5),
        ("multiplicative_weighted", 0.5),
        ("unknown", 0.5),
    )
    alphas = (0.0, 0.1, 0.5, 0.9, 1.0)
    wage_pairs = (
        (0.0, 0.0), (0.0, 1.0), (1.0, 0.0), (1.0e-8, 1.0), (1.0, 1.0e-8),
        (40.0, 1.0), (1.0, 40.0), (0.125, 0.25), (0.05, 2.0),
    )
    conformisms = (0.0, 10.0, 50.0, 1.0e4)
    weights = (
        (1.0, 1.0, 1.0), (0.0, 0.0, 0.0), (0.5, 2.0, 1.5),
        (1.0, 0.0, 1.0), (0.0, 1.0, 1.0),
    )
    decisions = 0
    certified = 0
    for _ in 1:5000
        utility, beta = rand(rng, specs)
        config = interval_config(utility, beta, rand(rng, weights))
        wage_self, wage_spouse = rand(rng, wage_pairs)
        if rand(rng) < 0.5
            wage_self *= rand(rng)
            wage_spouse *= rand(rng)
        end
        conformism = rand(rng, conformisms) * (rand(rng) < 0.5 ? 1.0 : rand(rng))
        n_theta = 2.0 * rand(rng) - 1.0
        pw = GN.AgentPayoffParams(
            wage_self = wage_self, wage_spouse = wage_spouse,
            alpha = rand(rng, alphas),
            conformism = conformism,
            N_h = rand(rng) * 1.5 - 0.25,
            N_theta = n_theta,
            N_h_spouse = rand(rng) * 1.5 - 0.25,
            is_woman = true,
        )
        pm = GN.AgentPayoffParams(
            wage_self = wage_spouse, wage_spouse = wage_self,
            alpha = rand(rng, alphas),
            conformism = conformism,
            N_h = rand(rng) * 1.5 - 0.25,
            N_theta = n_theta,
            N_h_spouse = rand(rng) * 1.5 - 0.25,
            is_woman = false,
        )
        hw_init = rand(rng, (0.0, 1.0, 0.5)) + (rand(rng) < 0.5 ? 0.0 : 0.4 * rand(rng))
        hm_init = rand(rng, (0.0, 1.0, 0.5)) + (rand(rng) < 0.5 ? 0.0 : 0.4 * rand(rng))
        hw_status, hm_status = GN.mutual_best_response(hw_init, hm_init, 0.0, pw, pm, config)
        uw_out = GN.individual_utility(hw_status, hm_status, 0.0, pw, config)
        um_out = GN.individual_utility(hm_status, hw_status, 0.0, pm, config)
        (isfinite(uw_out) && isfinite(um_out)) || continue
        # Five slab draws per scenario: below the norm, above the norm,
        # containing the norm, a zero-touching slab with signed-zero
        # endpoints, and a free slab.
        span = 0.5 * rand(rng) + 0.05
        below = clamp(n_theta - span - 0.5 * rand(rng), -1.0, 1.0)
        below_hi = min(clamp(n_theta - 0.05 * rand(rng), -1.0, 1.0), below + span)
        above_lo = max(clamp(n_theta + 0.05 * rand(rng), -1.0, 1.0), n_theta)
        slabs = (
            (below, below_hi),
            (above_lo, clamp(above_lo + span, -1.0, 1.0)),
            (clamp(n_theta - span, -1.0, 1.0), clamp(n_theta + span, -1.0, 1.0)),
            (rand(rng, (0.0, -0.0, -0.5 * rand(rng))), rand(rng, (0.0, -0.0, 0.5 * rand(rng)))),
            (min(2.0 * rand(rng) - 1.0, 2.0 * rand(rng) - 1.0), max(2.0 * rand(rng) - 1.0, 2.0 * rand(rng) - 1.0)),
        )
        for (lo, hi) in slabs
            lo > hi && ((lo, hi) = (hi, lo))
            decisions += 1
            prunable = GN._objective_interval_prunable(lo, hi, uw_out, um_out, pw, pm, config)
            prunable || continue
            certified += 1
            sample = Float64[lo, hi]
            lo == hi || append!(sample, (nextfloat(lo), prevfloat(hi), lo + 0.5 * (hi - lo)))
            lo <= 0.0 <= hi && push!(sample, 0.0)
            for theta in sample
                (lo <= theta <= hi) || continue
                payoff = interval_payoff(
                    theta, hw_status, hm_status, uw_out, um_out, pw, pm, config
                )
                @test isequal(payoff, -Inf)
                # Interval exclusion never removes a solve: the
                # pointwise certificate certifies every covered sample
                # too.
                @test GN._objective_prunable(theta, uw_out, um_out, pw, pm, config)
            end
        end
    end
    @test decisions >= 10000
    @test certified >= 1000
end
