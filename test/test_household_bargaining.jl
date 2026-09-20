# Tests for the household bargaining loop in
# `src/systems/household_bargaining.jl`: the pure labour solver
# `mutual_best_response` (NetLogo `choose-bundle`, ODD section Labour best
# response) and the `Ark.Query`-based household extraction in
# `choose_bundles`. Each testset builds a small world with
# `initialize_household`, overwrites the traits with known values, installs
# a controlled `SocialNetwork` resource directly, and checks the solver
# against hand-computed values.

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
        GN.CurrentUtility,
        GN.NormParameter,
        GN.PerceptionNormDivisionOfLabor,
    )
    Ark.add_resource!(world, GN.ModelProperties(agents_per_gender = n, network = network))
    Ark.add_resource!(world, GN.PaidTime())
    Ark.add_resource!(world, GN.MeanWage())
    Ark.add_resource!(world, GN.MeanPreference())
    Ark.add_resource!(world, GN.InitialConformism())
    women, men = GN.initialize_household(world, network)
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

@testset "choose_bundles extracts the household components in a query" begin
    Random.seed!(21)
    network = GN.NoNetwork()
    world, women, men = make_bargaining_world(network, 1)
    woman = only(women)
    man = only(men)

    Ark.set_components!(
        world,
        woman,
        (
            GN.WorkingTime(0.35, 0.30),
            GN.TransferToWoman(0.12, 0.10),
            GN.Conformism(2.0),
            GN.Wage(1.2, 1.2),
            GN.PreferencePrivate(0.4),
        ),
    )
    Ark.set_components!(
        world,
        man,
        (
            GN.WorkingTime(0.72, 0.70),
            GN.TransferToWoman(0.12, 0.10),
            GN.Conformism(1.5),
            GN.Wage(0.8, 0.8),
            GN.PreferencePrivate(0.6),
        ),
    )
    Ark.add_resource!(
        world, GN.SocialNetwork(Graphs.SimpleGraph(1), Graphs.SimpleGraph(1), men, women)
    )

    config = GN.UtilityConfig()
    theta = 0.12
    # Under `NoNetwork` every agent is isolated: the perceived norms fall
    # back to own lag, the lagged transfer, and the spouse lag.
    pw = GN.AgentPayoffParams(
        wage_self = 1.2, wage_spouse = 0.8, alpha = 0.4, conformism = 2.0,
        N_h = 0.30, N_theta = 0.10, N_h_spouse = 0.70, is_woman = true,
    )
    pm = GN.AgentPayoffParams(
        wage_self = 0.8, wage_spouse = 1.2, alpha = 0.6, conformism = 1.5,
        N_h = 0.70, N_theta = 0.10, N_h_spouse = 0.30, is_woman = false,
    )
    expected = GN.mutual_best_response(0.35, 0.72, theta, pw, pm, config)

    results = GN.choose_bundles(world, config, network)

    @test length(results) == 1
    @test results[1][1] ≈ expected[1]
    @test results[1][2] ≈ expected[2]
end
