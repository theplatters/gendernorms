# Tests for the household bargaining solver in
# `src/systems/household_bargaining.jl` (NetLogo `choose-bundle`, ODD
# section Labour best response). Each testset builds a small world with
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

@testset "mutual_best_response builds payoff bundles from the world" begin
    Random.seed!(20)
    network = GN.NoNetwork()
    world, women, men = make_bargaining_world(network, 1)
    woman = only(women)
    man = only(men)

    Ark.set_components!(
        world,
        woman,
        (
            GN.WorkingTime(0.20, 0.20),
            GN.TransferToWoman(0.0, 0.0),
            GN.Conformism(0.0),
            GN.Wage(1.0, 1.0),
            GN.PreferencePrivate(0.5),
        ),
    )
    Ark.set_components!(
        world,
        man,
        (
            GN.WorkingTime(0.80, 0.80),
            GN.TransferToWoman(0.0, 0.0),
            GN.Conformism(0.0),
            GN.Wage(1.0, 1.0),
            GN.PreferencePrivate(0.5),
        ),
    )
    Ark.add_resource!(
        world, GN.SocialNetwork(Graphs.SimpleGraph(1), Graphs.SimpleGraph(1), men, women)
    )

    hw, hm = GN.mutual_best_response(world, woman, man, 0.0, GN.UtilityConfig(), network)

    # With conformism 0, unit wages, and theta 0, both partners solve
    # h_self = 2 - h_self - h_spouse, so the fixed point is 2/3 each.
    @test hw ≈ 2 / 3 atol = 1.0e-2
    @test hm ≈ 2 / 3 atol = 1.0e-2
end
