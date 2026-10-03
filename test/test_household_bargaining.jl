# Tests for the household bargaining loop in
# `src/systems/household_bargaining.jl`: the pure labour solver
# `mutual_best_response` (NetLogo `choose-bundle`, ODD section Labour best
# response), the pure transfer helpers `outside_options`, `nash_product` and
# `equilibrium_payoff` plus the transfer solver `bargain_transfer` (NetLogo
# `set-theta` and `calculate-payoff`, ODD section Transfer bargaining,
# `MDR-0016`), and the `Ark.Query`-based household extraction in `set_theta!`.
# Each world testset builds a small world with `initialize_household`,
# overwrites the traits with known values, installs a controlled
# `SocialNetwork` resource directly, and checks the solvers against
# hand-computed values and an independent coarse-grid reference of the same
# Nash product.

using Ark
using GenderNorms
using Graphs
using Random
using Test

const GN = GenderNorms

function make_bargaining_world(network::GN.NetworkSpec, n::Int)
    world = Ark.World(
        GN.Male,
        GN.Female,
        GN.WorkingTime,
        GN.TransferToWoman,
        GN.Spouse,
        GN.Wage,
        GN.PreferencePrivate,
        GN.Conformism,
        GN.NormParameter,
        GN.PerceptionNormDivisionOfLabor,
        GN.Lambda,
    )
    Ark.add_resource!(world, GN.ModelProperties(agents_per_gender = n, network = network))
    Ark.add_resource!(world, GN.PaidTime())
    Ark.add_resource!(world, GN.MeanWage())
    Ark.add_resource!(world, GN.MeanPreference())
    Ark.add_resource!(world, GN.InitialConformism())
    women, men = GN.initialize_household(world, Random.default_rng())
    return world, women, men
end

@testset "mutual_best_response solves the asymmetric interior fixed point" begin
    # theta 0 and conformism 0: both first-order conditions are
    # h_i = K_i * (2 - h_w - h_m) with K_i = alpha_i^2 * wage_i / (1 - alpha_i)^2,
    # so the fixed point is h_i = 2 K_i / (1 + K_w + K_m).
    pw = GN.AgentPayoffParams(
        wage_self = 1.2, wage_spouse = 0.8, alpha = 0.5, conformism = 0.0, is_woman = true
    )
    pm = GN.AgentPayoffParams(
        wage_self = 0.8, wage_spouse = 1.2, alpha = 0.5, conformism = 0.0, is_woman = false
    )

    hw, hm = GN.mutual_best_response(0.2, 0.8, 0.0, pw, pm, GN.UtilityConfig())

    @test hw ≈ 2 * 1.2 / (1 + 1.2 + 0.8) atol = 1.0e-2
    @test hm ≈ 2 * 0.8 / (1 + 1.2 + 0.8) atol = 1.0e-2
end

@testset "bargain_transfer finds an interior transfer optimum" begin
    config = GN.UtilityConfig()
    # A wage gap with zero conformism: the transfer toward the lower-wage
    # woman has a positive Nash product for both partners.
    pw = GN.AgentPayoffParams(
        wage_self = 0.6, wage_spouse = 1.2, alpha = 0.5, conformism = 0.0,
        N_h = 0.5, N_theta = 0.0, N_h_spouse = 0.5, is_woman = true,
    )
    pm = GN.AgentPayoffParams(
        wage_self = 1.2, wage_spouse = 0.6, alpha = 0.5, conformism = 0.0,
        N_h = 0.5, N_theta = 0.0, N_h_spouse = 0.5, is_woman = false,
    )
    uw, um = GN.outside_options(0.5, 0.5, pw, pm, config)

    theta, hw, hm = GN.bargain_transfer(0.5, 0.5, 0.0, pw, pm, config)
    gain_w = GN.individual_utility(hw, hm, theta, pw, config) - uw
    gain_m = GN.individual_utility(hm, hw, theta, pm, config) - um

    @test 0.0 < theta < 1.0
    @test gain_w > 0.0
    @test gain_m > 0.0

    # Independent grid reference of the same Nash product.
    grid_payoff, grid_theta = -Inf, NaN
    for candidate in -1.0:0.01:1.0
        value, _, _ = GN.equilibrium_payoff(candidate, 0.5, 0.5, uw, um, pw, pm, config)
        if value > grid_payoff
            grid_payoff, grid_theta = value, candidate
        end
    end
    payoff = GN.nash_product(theta, hw, hm, uw, um, pw, pm, config)
    @test payoff >= grid_payoff - 1.0e-9
    @test abs(theta - grid_theta) <= 0.01
end

@testset "bargain_transfer finds a negative optimum when the woman earns more" begin
    config = GN.UtilityConfig()
    pw = GN.AgentPayoffParams(
        wage_self = 1.2, wage_spouse = 0.6, alpha = 0.5, conformism = 0.0,
        N_h = 0.5, N_theta = 0.0, N_h_spouse = 0.5, is_woman = true,
    )
    pm = GN.AgentPayoffParams(
        wage_self = 0.6, wage_spouse = 1.2, alpha = 0.5, conformism = 0.0,
        N_h = 0.5, N_theta = 0.0, N_h_spouse = 0.5, is_woman = false,
    )
    uw, um = GN.outside_options(0.5, 0.5, pw, pm, config)

    theta, hw, hm = GN.bargain_transfer(0.5, 0.5, 0.0, pw, pm, config)
    gain_w = GN.individual_utility(hw, hm, theta, pw, config) - uw
    gain_m = GN.individual_utility(hm, hw, theta, pm, config) - um

    @test -1.0 < theta < 0.0
    @test gain_w >= 0.0
    @test gain_m >= 0.0
end

@testset "bargain_transfer stays near a sharply peaked status quo" begin
    config = GN.UtilityConfig()
    # Huge conformism with the transfer norm at the status quo: the
    # status quo sits on the objective's sharp peak, so the sparse
    # search of `MDR-0016` keeps it as its best candidate and the
    # committed hours match the labour equilibrium there (the
    # exact case where no candidate beats the status quo is constructed
    # in `test/test_transfer_search.jl`).
    pw = GN.AgentPayoffParams(
        wage_self = 0.9, wage_spouse = 1.0, alpha = 0.48, conformism = 1.0e4,
        N_h = 0.36, N_theta = 0.3, N_h_spouse = 0.77, is_woman = true,
    )
    pm = GN.AgentPayoffParams(
        wage_self = 1.0, wage_spouse = 0.9, alpha = 0.45, conformism = 1.0e4,
        N_h = 0.77, N_theta = 0.3, N_h_spouse = 0.36, is_woman = false,
    )
    uw, um = GN.outside_options(0.36, 0.77, pw, pm, config)
    hw_status, hm_status = GN.mutual_best_response(0.36, 0.77, 0.3, pw, pm, config)
    status_payoff = GN.nash_product(0.3, hw_status, hm_status, uw, um, pw, pm, config)
    @test status_payoff > 0.0

    theta, hw, hm = GN.bargain_transfer(0.36, 0.77, 0.3, pw, pm, config)

    @test theta > 0.1
    @test theta ≈ 0.3 atol = 1.0e-3
    equilibrium_w, equilibrium_m = GN.mutual_best_response(0.36, 0.77, theta, pw, pm, config)
    @test hw ≈ equilibrium_w atol = 1.0e-3
    @test hm ≈ equilibrium_m atol = 1.0e-3
    @test GN.nash_product(theta, hw, hm, uw, um, pw, pm, config) >= status_payoff
end

@testset "bargain_transfer falls back to the status quo when nothing is feasible" begin
    config = GN.UtilityConfig()
    # A zero male wage makes the male outside option non-finite, so no
    # candidate can be evaluated; the household keeps its transfer and the
    # labour equilibrium at that transfer.
    pw = GN.AgentPayoffParams(
        wage_self = 0.9, wage_spouse = 0.0, alpha = 0.48, conformism = 10.0,
        N_h = 0.36, N_theta = 0.0, N_h_spouse = 0.77, is_woman = true,
    )
    pm = GN.AgentPayoffParams(
        wage_self = 0.0, wage_spouse = 0.9, alpha = 0.45, conformism = 10.0,
        N_h = 0.77, N_theta = 0.0, N_h_spouse = 0.36, is_woman = false,
    )

    theta, hw, hm = GN.bargain_transfer(0.36, 0.77, 0.4, pw, pm, config)

    @test theta == 0.4
    status_w, status_m = GN.mutual_best_response(0.36, 0.77, 0.4, pw, pm, config)
    @test hw ≈ status_w atol = 1.0e-12
    @test hm ≈ status_m atol = 1.0e-12
end

@testset "bargain_transfer finds the narrow feasible band next to zero" begin
    config = GN.UtilityConfig()
    # Extreme corner characterized in `MDR-0005` and reproduced in
    # `benchmark/transfer_search_diagnosis.md`: a feasible transfer band
    # next to zero is narrower than the probe points of the unseeded
    # Brent search of `MDR-0005`, which missed the band and fell back to
    # zero transfer. The production search of `MDR-0016` evaluates the
    # anchor neighbourhood of the status quo and commits inside the
    # band; the fallback kept the old outcome safe, the current search
    # finds what it missed.
    pw = GN.AgentPayoffParams(
        wage_self = 0.05, wage_spouse = 2.0, alpha = 0.9, conformism = 0.0,
        N_h = 0.5, N_theta = 0.0, N_h_spouse = 0.5, is_woman = true,
    )
    pm = GN.AgentPayoffParams(
        wage_self = 2.0, wage_spouse = 0.05, alpha = 0.9, conformism = 0.0,
        N_h = 0.5, N_theta = 0.0, N_h_spouse = 0.5, is_woman = false,
    )
    uw, um = GN.outside_options(0.5, 0.5, pw, pm, config)

    band_payoff = -Inf
    for candidate in 0.0:0.005:0.1
        value, _, _ = GN.equilibrium_payoff(candidate, 0.5, 0.5, uw, um, pw, pm, config)
        band_payoff = max(band_payoff, value)
    end

    theta, hw, hm = GN.bargain_transfer(0.5, 0.5, 0.0, pw, pm, config)

    @test band_payoff > 0.0
    @test 0.0 < theta < 0.1
    payoff = GN.nash_product(theta, hw, hm, uw, um, pw, pm, config)
    @test payoff >= band_payoff
    gain_w = GN.individual_utility(hw, hm, theta, pw, config) - uw
    gain_m = GN.individual_utility(hm, hw, theta, pm, config) - um
    @test gain_w >= 0.0
    @test gain_m >= 0.0
end

@testset "mutual_best_response settles on a bitwise fixed point" begin
    # Under `MDR-0017` each eligible best response solves the continuous
    # first-order condition instead of sticking to the seeded discrete
    # local maximum of `MDR-0002`, so a restart at the `eps`-converged
    # output takes one more contraction step rather than returning it
    # unchanged (the exact legacy restart was a probe-quantum artifact
    # of the seeded search). Iterating the restart converges to a
    # bitwise fixed point of the alternation - both partners inside the
    # derivative solve's certification band - at which
    # `mutual_best_response` returns its input exactly. That fixed-point
    # property is what the transfer chain relies on when it re-solves a
    # cached labour equilibrium (see `MDR-0017`).
    pw = GN.AgentPayoffParams(
        wage_self=1.2, wage_spouse=0.8, alpha=0.5, conformism=0.0, is_woman=true
    )
    pm = GN.AgentPayoffParams(
        wage_self=0.8, wage_spouse=1.2, alpha=0.5, conformism=0.0, is_woman=false
    )
    config = GN.UtilityConfig()

    hw, hm = GN.mutual_best_response(0.2, 0.8, 0.0, pw, pm, config)
    settled = false
    for _ in 1:40
        hw_next, hm_next = GN.mutual_best_response(hw, hm, 0.0, pw, pm, config)
        if hw_next == hw && hm_next == hm
            settled = true
            break
        end
        hw, hm = hw_next, hm_next
    end
    @test settled
    hw3, hm3 = GN.mutual_best_response(hw, hm, 0.0, pw, pm, config)
    @test hw3 == hw
    @test hm3 == hm
end

@testset "mutual_best_response hours satisfy the own-response condition" begin
    # The hours of the settled fixed point satisfy each partner's
    # own-response condition at the tier that settled them
    # (`MDR-0017`): either they sit inside the tier-1 seed enclosure
    # (within `BEST_RESPONSE_TOL` of the optimum, which is where the
    # alternation stops when both partners' seeds certify), or they
    # satisfy the tier-2 first-order condition tightly (`|g|` tiny at
    # interior hours; hours exactly at a boundary carry the boundary
    # derivative sign selecting them and are checked in the solver
    # battery).
    tol = GN.BEST_RESPONSE_TOL
    for spec in (
        GN.CES(), GN.Multiplicative(), GN.MultiplicativeWeighted(), GN.Additive(),
        GN.CES(beta=0.9),
    )
        config = GN.UtilityConfig(func=spec)
        pw = GN.AgentPayoffParams(
            wage_self=1.2, wage_spouse=0.8, alpha=0.5, conformism=2.0, is_woman=true
        )
        pm = GN.AgentPayoffParams(
            wage_self=0.8, wage_spouse=1.2, alpha=0.45, conformism=2.0, is_woman=false
        )
        hw, hm = GN.mutual_best_response(0.2, 0.8, 0.0, pw, pm, config)
        for _ in 1:40
            hw_next, hm_next = GN.mutual_best_response(hw, hm, 0.0, pw, pm, config)
            (hw_next == hw && hm_next == hm) && break
            hw, hm = hw_next, hm_next
        end
        obj_w = GN.BestResponseObjective(0.0, hm, pw, config)
        obj_m = GN.BestResponseObjective(0.0, hw, pm, config)
        for (obj, h) in ((obj_w, hw), (obj_m, hm))
            if GN._derivative_applicable(obj, h) && h != 0.0 && h != 1.0
                gl = GN._best_response_gradient_sign(obj, h - tol)
                gr = GN._best_response_gradient_sign(obj, h + tol)
                enclosed =
                    (isfinite(gl) && isfinite(gr) && gl >= 0.0 && gr <= 0.0) ||
                    (isfinite(gr) && !isfinite(gl) && h <= tol && gr <= 0.0) ||
                    (isfinite(gl) && !isfinite(gr) && h >= 1.0 - tol && gl >= 0.0)
                if enclosed
                    @test GN._derivative_seed_certificate(obj, h)
                else
                    g, _, _ = GN._best_response_derivatives(obj, h)
                    @test abs(g) <= 1.0e-6
                end
            end
        end
    end
end

# Allocation probe of the labour loop: measured through a top-level
# helper so the testset scope cannot box the solver arguments.
mbr_allocs(
    hw::Float64, hm::Float64, theta::Float64,
    pw::GN.AgentPayoffParams, pm::GN.AgentPayoffParams, config::GN.UtilityConfig,
)::Int = @allocated GN.mutual_best_response(hw, hm, theta, pw, pm, config)

@testset "mutual_best_response allocates nothing" begin
    # Allocation pin for the labour loop across all four utility specs
    # (the `MDR-0017` derivative route), one unsupported `CES` `beta`
    # (the bitwise `MDR-0002` fallback route), and the all-infeasible
    # payer (whose solve falls back to the legacy `NaN` contract): each
    # captured partner hour is bound immutably per iteration (see
    # `MDR-0002`), and the specialized solve keeps the chain
    # allocation-free (`ADR-0022`).
    for spec in (
        GN.CES(), GN.Multiplicative(), GN.MultiplicativeWeighted(), GN.Additive(),
        GN.CES(beta=1.5),
    )
        config = GN.UtilityConfig(func=spec)
        pw = GN.AgentPayoffParams(
            wage_self=1.2, wage_spouse=0.8, alpha=0.5, conformism=0.0, is_woman=true
        )
        pm = GN.AgentPayoffParams(
            wage_self=0.8, wage_spouse=1.2, alpha=0.5, conformism=0.0, is_woman=false
        )
        GN.mutual_best_response(0.2, 0.8, 0.0, pw, pm, config)
        @test mbr_allocs(0.2, 0.8, 0.0, pw, pm, config) == 0
    end
    # The all-infeasible payer: zero own wage and a payer transfer make
    # `A == B == 0`, so his solve is inapplicable and keeps the current
    # hours through the legacy `NaN` path.
    config = GN.UtilityConfig()
    pw = GN.AgentPayoffParams(
        wage_self=0.9, wage_spouse=0.0, alpha=0.48, conformism=10.0,
        N_h=0.36, N_theta=0.0, N_h_spouse=0.77, is_woman=true,
    )
    pm = GN.AgentPayoffParams(
        wage_self=0.0, wage_spouse=0.9, alpha=0.45, conformism=10.0,
        N_h=0.77, N_theta=0.0, N_h_spouse=0.36, is_woman=false,
    )
    GN.mutual_best_response(0.36, 0.77, 0.4, pw, pm, config)
    @test mbr_allocs(0.36, 0.77, 0.4, pw, pm, config) == 0
end

@testset "set_theta! runs both stages and commits the bargain" begin
    Random.seed!(21)
    network = GN.NoNetwork()
    world, women, men = make_bargaining_world(network, 2)

    # Two households with different wages, preferences, and transfers.
    states = (
        (h_w = 0.35, h_w_old = 0.30, h_m = 0.72, h_m_old = 0.70, theta = 0.12, theta_old = 0.10, c_w = 2.0, c_m = 1.5, wage_w = 1.2, wage_m = 0.8, pref_w = 0.4, pref_m = 0.6),
        (h_w = 0.55, h_w_old = 0.50, h_m = 0.85, h_m_old = 0.80, theta = 0.25, theta_old = 0.20, c_w = 1.0, c_m = 2.5, wage_w = 0.9, wage_m = 1.1, pref_w = 0.5, pref_m = 0.45),
    )
    for (woman, man, state) in zip(women, men, states)
        Ark.set_components!(
            world,
            woman,
            (
                GN.WorkingTime(state.h_w, state.h_w_old),
                GN.TransferToWoman(state.theta, state.theta_old),
                GN.Conformism(state.c_w),
                GN.Wage(state.wage_w, state.wage_w),
                GN.PreferencePrivate(state.pref_w, state.pref_w),
            ),
        )
        Ark.set_components!(
            world,
            man,
            (
                GN.WorkingTime(state.h_m, state.h_m_old),
                GN.TransferToWoman(state.theta, state.theta_old),
                GN.Conformism(state.c_m),
                GN.Wage(state.wage_m, state.wage_m),
                GN.PreferencePrivate(state.pref_m, state.pref_m),
            ),
        )
    end
    Ark.add_resource!(
        world, GN.SocialNetwork(Graphs.SimpleGraph(2), Graphs.SimpleGraph(2), men, women)
    )

    config = GN.UtilityConfig()
    # Under `NoNetwork` every agent is isolated: the perceived norms fall
    # back to own lag, the lagged transfer, and the spouse lag.
    expected = map(states) do state
        pw = GN.AgentPayoffParams(
            wage_self = state.wage_w, wage_spouse = state.wage_m, alpha = state.pref_w, conformism = state.c_w,
            N_h = state.h_w_old, N_theta = state.theta_old, N_h_spouse = state.h_m_old, is_woman = true,
        )
        pm = GN.AgentPayoffParams(
            wage_self = state.wage_m, wage_spouse = state.wage_w, alpha = state.pref_m, conformism = state.c_m,
            N_h = state.h_m_old, N_theta = state.theta_old, N_h_spouse = state.h_w_old, is_woman = false,
        )
        theta, hw, hm = GN.bargain_transfer(state.h_w, state.h_m, state.theta, pw, pm, config)
        (; theta, hw, hm, pw, pm, h_w = state.h_w, h_m = state.h_m)
    end

    @test GN.set_theta!(world, config) === nothing

    for (woman, man, state, want) in zip(women, men, states, expected)
        committed_woman = Ark.get_components(world, woman, (GN.WorkingTime, GN.TransferToWoman))
        committed_man = Ark.get_components(world, man, (GN.WorkingTime, GN.TransferToWoman))
        @test committed_woman[1].current ≈ want.hw
        @test committed_woman[2].current ≈ want.theta
        @test committed_man[1].current ≈ want.hm
        @test committed_man[2].current ≈ want.theta
        # The lagged values stay untouched for the statistics stage.
        @test committed_woman[1].old == state.h_w_old
        @test committed_woman[2].old == state.theta_old
        @test committed_man[1].old == state.h_m_old
        @test committed_man[2].old == state.theta_old
        # The committed hours are the labour equilibrium at the committed transfer.
        equilibrium_w, equilibrium_m =
            GN.mutual_best_response(want.h_w, want.h_m, want.theta, want.pw, want.pm, config)
        @test committed_woman[1].current ≈ equilibrium_w atol = 1.0e-3
        @test committed_man[1].current ≈ equilibrium_m atol = 1.0e-3
    end
end
