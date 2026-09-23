# Tests for the statistics system in `src/systems/statistics.jl`
# (NetLogo `update-statistics`, ODD section Statistics
# (`update-statistics`); see `MDR-0007`). Each testset builds a small world
# with `initialize_household`, overwrites the working times and transfers
# with known values, and checks the lag copy in
# `update_old_working_time_and_transfer!` plus the global means in
# `update_global_working_times!` against hand-computed values.

using Ark
using GenderNorms
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
        GN.CurrentUtility,
        GN.NormParameter,
        GN.PerceptionNormDivisionOfLabor,
        GN.Lambda,
    )
    Ark.add_resource!(world, GN.ModelProperties(agents_per_gender = n, network = network))
    Ark.add_resource!(world, GN.PaidTime())
    Ark.add_resource!(world, GN.MeanWage())
    Ark.add_resource!(world, GN.MeanPreference())
    Ark.add_resource!(world, GN.InitialConformism())
    Ark.add_resource!(world, GN.WorkingTimeStats(0.0, 0.0, 0.0))
    women, men = GN.initialize_household(world, Random.default_rng())
    return world, women, men
end

function set_state!(world, entity; h, h_old, theta, theta_old)
    Ark.set_components!(
        world,
        entity,
        (
            GN.WorkingTime(h, h_old),
            GN.TransferToWoman(theta, theta_old),
        ),
    )
    return nothing
end

function stored_times(world, entity)
    time, transfer = Ark.get_components(world, entity, (GN.WorkingTime, GN.TransferToWoman))
    return time, transfer
end

@testset "lag copy preserves current and sets old" begin
    Random.seed!(30)
    world, women, men = make_world(GN.NoNetwork(), 2)
    w1, w2 = women
    m1, m2 = men

    set_state!(world, w1; h = 0.2, h_old = 0.0, theta = 0.1, theta_old = 0.0)
    set_state!(world, w2; h = 0.4, h_old = 0.0, theta = 0.3, theta_old = 0.0)
    set_state!(world, m1; h = 0.6, h_old = 0.0, theta = 0.1, theta_old = 0.0)
    set_state!(world, m2; h = 0.8, h_old = 0.0, theta = 0.3, theta_old = 0.0)

    @test GN.update_old_working_time_and_transfer!(world) === nothing

    for (entity, h, theta) in ((w1, 0.2, 0.1), (w2, 0.4, 0.3), (m1, 0.6, 0.1), (m2, 0.8, 0.3))
        time, transfer = stored_times(world, entity)
        @test time.current ≈ h
        @test time.old ≈ h
        @test transfer.current ≈ theta
        @test transfer.old ≈ theta
    end
end

@testset "global means and gap" begin
    Random.seed!(31)
    world, women, men = make_world(GN.NoNetwork(), 2)
    w1, w2 = women
    m1, m2 = men

    set_state!(world, w1; h = 0.2, h_old = 0.0, theta = 0.1, theta_old = 0.0)
    set_state!(world, w2; h = 0.4, h_old = 0.0, theta = 0.3, theta_old = 0.0)
    set_state!(world, m1; h = 0.6, h_old = 0.0, theta = 0.1, theta_old = 0.0)
    set_state!(world, m2; h = 0.8, h_old = 0.0, theta = 0.3, theta_old = 0.0)

    @test GN.update_global_working_times!(world) === nothing

    stats = Ark.get_resource(world, GN.WorkingTimeStats)
    @test stats.women ≈ 0.3
    @test stats.men ≈ 0.7
    @test stats.gap ≈ 0.4
end

@testset "empty gender throws" begin
    world = Ark.World(GN.Male, GN.Female, GN.WorkingTime)
    Ark.add_resource!(world, GN.WorkingTimeStats(0.0, 0.0, 0.0))
    Ark.new_entity!(world, (GN.Male(), GN.WorkingTime(0.6, 0.6)))
    Ark.new_entity!(world, (GN.Male(), GN.WorkingTime(0.8, 0.8)))

    @test_throws ArgumentError GN.update_global_working_times!(world)

    world_women = Ark.World(GN.Male, GN.Female, GN.WorkingTime)
    Ark.add_resource!(world_women, GN.WorkingTimeStats(0.0, 0.0, 0.0))
    Ark.new_entity!(world_women, (GN.Female(), GN.WorkingTime(0.2, 0.2)))
    Ark.new_entity!(world_women, (GN.Female(), GN.WorkingTime(0.4, 0.4)))

    @test_throws ArgumentError GN.update_global_working_times!(world_women)

    try
        GN.update_global_working_times!(world)
        @test false
    catch e
        @test occursin("women", sprint(showerror, e))
    end
end
