# Tests for the norm perception system in `src/systems/norm_perception.jl`
# (NetLogo `calculate-utility`, ODD section Norm perception
# (`calculate-utility`)). Each testset builds a small world with
# `initialize_household`, overwrites the traits with known values, installs
# a controlled `SocialNetwork` resource directly, and checks the stored
# `PerceptionNormDivisionOfLabor` / `NormParameter` components against
# hand-computed values.

using Ark
using GenderNorms
using Graphs
using Random
using Test

const GN = GenderNorms

function make_world(network::GN.NetworkSpec, n::Int)
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
        GN.CommittedUtility,
    )
    Ark.add_resource!(world, GN.ModelProperties(agents_per_gender = n, network = network))
    Ark.add_resource!(world, GN.PaidTime())
    Ark.add_resource!(world, GN.MeanWage())
    Ark.add_resource!(world, GN.MeanPreference())
    Ark.add_resource!(world, GN.InitialConformism())
    women, men = GN.initialize_household(world, Random.default_rng())
    return world, women, men
end

function set_state!(world, entity; h, h_old, theta, theta_old, conformism = 2.0)
    Ark.set_components!(
        world,
        entity,
        (
            GN.WorkingTime(h, h_old),
            GN.TransferToWoman(theta, theta_old),
            GN.Conformism(conformism),
        ),
    )
    return nothing
end

function stored_percepts(world, entity)
    percept, penalty = Ark.get_components(
        world, entity, (GN.PerceptionNormDivisionOfLabor, GN.NormParameter)
    )
    return percept.amount, penalty.amount
end

@testset "linked women see neighbour and spouses-of-neighbours means" begin
    Random.seed!(10)
    network = GN.NoNetwork()
    world, women, men = make_world(network, 2)
    w1, w2 = women
    m1, m2 = men

    set_state!(world, w1; h = 0.35, h_old = 0.3, theta = 0.12, theta_old = 0.1, conformism = 2.0)
    set_state!(world, w2; h = 0.55, h_old = 0.5, theta = 0.32, theta_old = 0.3, conformism = 1.5)
    set_state!(world, m1; h = 0.72, h_old = 0.7, theta = 0.12, theta_old = 0.1, conformism = 2.0)
    set_state!(world, m2; h = 0.92, h_old = 0.9, theta = 0.32, theta_old = 0.3, conformism = 1.5)

    women_graph = Graphs.SimpleGraph(2)
    Graphs.add_edge!(women_graph, 1, 2)
    men_graph = Graphs.SimpleGraph(2)
    Ark.add_resource!(world, GN.SocialNetwork(men_graph, women_graph, men, women))

    GN.calculate_norm_perception!(world, GN.UtilityConfig())

    percept_w1, penalty_w1 = stored_percepts(world, w1)
    @test percept_w1 ≈ 0.5
    @test penalty_w1 ≈ -2.0 * ((0.35 - 0.5)^2 + (0.12 - 0.3)^2 + (0.72 - 0.9)^2)

    percept_w2, penalty_w2 = stored_percepts(world, w2)
    @test percept_w2 ≈ 0.3
    @test penalty_w2 ≈ -1.5 * ((0.55 - 0.3)^2 + (0.32 - 0.1)^2 + (0.92 - 0.7)^2)

    # Isolated men under a non-mixing network fall back to their own lag.
    percept_m1, penalty_m1 = stored_percepts(world, m1)
    @test percept_m1 ≈ 0.7
    @test penalty_m1 ≈ -2.0 * ((0.72 - 0.7)^2 + (0.12 - 0.1)^2 + (0.35 - 0.3)^2)
end

@testset "isolated agent under NoNetwork uses own lag and spouse lag" begin
    Random.seed!(11)
    network = GN.NoNetwork()
    world, women, men = make_world(network, 1)
    w1 = only(women)
    m1 = only(men)

    set_state!(world, w1; h = 0.4, h_old = 0.36, theta = 0.2, theta_old = 0.25, conformism = 3.0)
    set_state!(world, m1; h = 0.8, h_old = 0.77, theta = 0.2, theta_old = 0.25, conformism = 3.0)

    Ark.add_resource!(
        world, GN.SocialNetwork(Graphs.SimpleGraph(1), Graphs.SimpleGraph(1), men, women)
    )

    GN.calculate_norm_perception!(world, GN.UtilityConfig())

    percept_w1, penalty_w1 = stored_percepts(world, w1)
    @test percept_w1 ≈ 0.36
    @test penalty_w1 ≈ -3.0 * ((0.4 - 0.36)^2 + (0.2 - 0.25)^2 + (0.8 - 0.77)^2)

    percept_m1, penalty_m1 = stored_percepts(world, m1)
    @test percept_m1 ≈ 0.77
    @test penalty_m1 ≈ -3.0 * ((0.8 - 0.77)^2 + (0.2 - 0.25)^2 + (0.4 - 0.36)^2)
end

@testset "isolated agents under HomogeneousMixing use global lagged means" begin
    Random.seed!(12)
    network = GN.HomogeneousMixing()
    world, women, men = make_world(network, 2)
    w1, w2 = women
    m1, m2 = men

    set_state!(world, w1; h = 0.35, h_old = 0.3, theta = 0.12, theta_old = 0.1, conformism = 2.0)
    set_state!(world, w2; h = 0.55, h_old = 0.5, theta = 0.32, theta_old = 0.3, conformism = 2.0)
    set_state!(world, m1; h = 0.72, h_old = 0.7, theta = 0.12, theta_old = 0.1, conformism = 2.0)
    set_state!(world, m2; h = 0.92, h_old = 0.9, theta = 0.32, theta_old = 0.3, conformism = 2.0)

    # `HomogeneousMixing` generates an empty graph: every agent is isolated.
    net = GN.SocialNetwork(Graphs.SimpleGraph(2), Graphs.SimpleGraph(2), men, women)
    Ark.add_resource!(world, net)

    globals = GN.norm_global_means(world, net)
    @test globals.women_h ≈ 0.4
    @test globals.men_h ≈ 0.8
    @test globals.transfer ≈ 0.2

    GN.calculate_norm_perception!(world, GN.UtilityConfig())

    # Women see the women hours mean, the women transfer mean, and the men
    # hours mean for the spouse percept.
    percept_w1, penalty_w1 = stored_percepts(world, w1)
    @test percept_w1 ≈ 0.4
    @test penalty_w1 ≈ -2.0 * ((0.35 - 0.4)^2 + (0.12 - 0.2)^2 + (0.72 - 0.8)^2)

    # Men see the men hours mean, the same women transfer mean, and the
    # women hours mean for the spouse percept.
    percept_m1, penalty_m1 = stored_percepts(world, m1)
    @test percept_m1 ≈ 0.8
    @test penalty_m1 ≈ -2.0 * ((0.72 - 0.8)^2 + (0.12 - 0.2)^2 + (0.35 - 0.4)^2)
end

@testset "norm_means allocates nothing on the neighbour branch" begin
    # Allocation pin for the neighbour branch: `norm_means` iterates the
    # neighbour list without materialising it and deduplicates spouses into
    # the caller-owned scratch buffer (see `MDR-0004`), so the per-agent
    # norm computation allocates nothing.
    Random.seed!(10)
    network = GN.NoNetwork()
    world, women, men = make_world(network, 3)
    w1, w2, w3 = women
    m1, m2, m3 = men

    set_state!(world, w1; h = 0.35, h_old = 0.3, theta = 0.12, theta_old = 0.1, conformism = 2.0)
    set_state!(world, w2; h = 0.55, h_old = 0.5, theta = 0.32, theta_old = 0.3, conformism = 1.5)
    set_state!(world, w3; h = 0.45, h_old = 0.4, theta = 0.22, theta_old = 0.2, conformism = 2.0)
    set_state!(world, m1; h = 0.72, h_old = 0.7, theta = 0.12, theta_old = 0.1, conformism = 2.0)
    set_state!(world, m2; h = 0.92, h_old = 0.9, theta = 0.32, theta_old = 0.3, conformism = 1.5)
    set_state!(world, m3; h = 0.82, h_old = 0.8, theta = 0.22, theta_old = 0.2, conformism = 2.0)

    women_graph = Graphs.SimpleGraph(3)
    Graphs.add_edge!(women_graph, 1, 2)
    Graphs.add_edge!(women_graph, 1, 3)
    men_graph = Graphs.SimpleGraph(3)
    Ark.add_resource!(world, GN.SocialNetwork(men_graph, women_graph, men, women))

    net = Ark.get_resource(world, GN.SocialNetwork)
    spouse_seen = Ark.Entity[]
    GN.norm_means(world, net, 1, true, nothing, spouse_seen)

    @test @allocated(GN.norm_means(world, net, 1, true, nothing, spouse_seen)) == 0
end
