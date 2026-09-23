# Tests for the shock system in `src/systems/shocks.jl` (NetLogo
# `start-shock` and `end-shock`, ODD section Shocks (`start-shock`,
# `end-shock`); `update-wages`, ODD section Endogenous preference
# adaptation and wage growth; see `MDR-0009`). Each testset builds a
# small world with `initialize_household`, overwrites wages and
# preferences with known values, and checks the one-off shock, the
# exponential recovery, the tick dispatch in `update_shocks!`, the
# setup draw in `select_affected!`, and the gap-closing `update_wages!`
# against hand-computed values.

using Ark
using GenderNorms
using Random
using Test

const GN = GenderNorms

function make_shock_world(n::Int; seed::Int = 11)
    Random.seed!(seed)
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
        GN.DirectlyAffected,
    )
    Ark.add_resource!(world, GN.ModelProperties(agents_per_gender = n, network = GN.NoNetwork()))
    Ark.add_resource!(world, GN.PaidTime())
    Ark.add_resource!(world, GN.MeanWage())
    Ark.add_resource!(world, GN.MeanPreference())
    Ark.add_resource!(world, GN.InitialConformism())
    women, men = GN.initialize_household(world, Random.default_rng())
    return world, women, men
end

function set_wage!(world, entity, current::Float64, old::Float64)
    Ark.set_components!(world, entity, (GN.Wage(current, old),))
    return nothing
end

function set_preference!(world, entity, current::Float64, pre::Float64)
    Ark.set_components!(world, entity, (GN.PreferencePrivate(current, pre),))
    return nothing
end

function get_wage(world, entity)
    return Ark.get_components(world, entity, (GN.Wage,))[1]
end

function get_preference(world, entity)
    return Ark.get_components(world, entity, (GN.PreferencePrivate,))[1]
end

function count_tagged(world, gender::Type)
    total = 0
    for (batch,) in Ark.Query(world, (GN.DirectlyAffected,); with = (gender,))
        total += length(batch)
    end
    return total
end

@testset "preference shock shifts all turtles and saves baselines" begin
    world, women, men = make_shock_world(2)
    w1, w2 = women
    m1, m2 = men

    set_preference!(world, w1, 0.5, 0.0)
    set_preference!(world, w2, 0.05, 0.0)
    set_preference!(world, m1, 0.6, 0.0)
    set_preference!(world, m2, 0.05, 0.0)

    shock = GN.PreferenceShock(delta_men = 0.1, delta_woman = 0.2)
    @test GN.start_shock!(world, shock) === nothing

    @test get_preference(world, w1).current ≈ 0.3
    @test get_preference(world, w1).pre ≈ 0.5
    @test get_preference(world, w2).current ≈ 0.0
    @test get_preference(world, w2).pre ≈ 0.05
    @test get_preference(world, m1).current ≈ 0.5
    @test get_preference(world, m1).pre ≈ 0.6
    @test get_preference(world, m2).current ≈ 0.0
    @test get_preference(world, m2).pre ≈ 0.05
end

@testset "wage shock cuts only affected agents and saves baselines for all" begin
    world, women, men = make_shock_world(2)
    w1, w2 = women
    m1, m2 = men

    set_wage!(world, w1, 1.0, 0.0)
    set_wage!(world, w2, 2.0, 0.0)
    set_wage!(world, m1, 3.0, 0.0)
    set_wage!(world, m2, 4.0, 0.0)
    Ark.add_components!(world, w1, (GN.DirectlyAffected(),))
    Ark.add_components!(world, m2, (GN.DirectlyAffected(),))

    @test GN.start_shock!(world, GN.WageShock()) === nothing

    @test get_wage(world, w1).current ≈ 0.6 * 1.0
    @test get_wage(world, w1).old ≈ 1.0
    @test get_wage(world, w2).current ≈ 2.0
    @test get_wage(world, w2).old ≈ 2.0
    @test get_wage(world, m1).current ≈ 3.0
    @test get_wage(world, m1).old ≈ 3.0
    @test get_wage(world, m2).current ≈ 0.6 * 4.0
    @test get_wage(world, m2).old ≈ 4.0
end

@testset "recovery steps toward baselines without overshoot" begin
    world, women, men = make_shock_world(2)
    w1, w2 = women
    m1, m2 = men

    set_wage!(world, w1, 0.6, 1.0)
    set_wage!(world, w2, 2.0, 2.0)
    set_wage!(world, m1, 5.0, 4.0)
    set_preference!(world, w1, 0.3, 0.5)
    set_preference!(world, m1, 0.6, 0.6)
    set_preference!(world, m2, 0.9, 0.7)

    @test GN.recover_shock!(world, GN.WageShock(depreciation = 0.5)) === nothing
    @test GN.recover_shock!(world, GN.PreferenceShock(depreciation = 0.5)) === nothing

    @test get_wage(world, w1).current ≈ 0.6 + 0.5 * (1.0 - 0.6)
    @test get_wage(world, w1).old ≈ 1.0
    @test get_wage(world, w2).current ≈ 2.0
    @test get_wage(world, m1).current ≈ 5.0
    @test get_preference(world, w1).current ≈ 0.3 + 0.5 * (0.5 - 0.3)
    @test get_preference(world, w1).pre ≈ 0.5
    @test get_preference(world, m1).current ≈ 0.6
    @test get_preference(world, m2).current ≈ 0.9
end

@testset "update_shocks! dispatches on tick for both shocks" begin
    world, women, men = make_shock_world(2)
    w1, w2 = women
    m1, m2 = men

    set_wage!(world, w1, 1.0, 0.0)
    set_wage!(world, w2, 2.0, 0.0)
    set_wage!(world, m1, 3.0, 0.0)
    set_wage!(world, m2, 4.0, 0.0)
    set_preference!(world, w1, 0.5, 0.0)
    set_preference!(world, w2, 0.7, 0.0)
    set_preference!(world, m1, 0.6, 0.0)
    set_preference!(world, m2, 0.9, 0.0)
    Ark.add_components!(world, w1, (GN.DirectlyAffected(),))
    Ark.add_components!(world, m2, (GN.DirectlyAffected(),))
    Ark.add_resource!(world, GN.WageShock(start = 60, depreciation = 0.5))
    Ark.add_resource!(
        world, GN.PreferenceShock(start = 60, depreciation = 0.5, delta_men = 0.1, delta_woman = 0.2)
    )

    @test GN.update_shocks!(world, 59) === nothing
    @test get_wage(world, w1).current ≈ 1.0
    @test get_wage(world, w1).old ≈ 0.0
    @test get_preference(world, w1).current ≈ 0.5
    @test get_preference(world, w1).pre ≈ 0.0

    @test GN.update_shocks!(world, 60) === nothing
    @test get_wage(world, w1).current ≈ 0.6
    @test get_wage(world, w1).old ≈ 1.0
    @test get_wage(world, w2).current ≈ 2.0
    @test get_wage(world, w2).old ≈ 2.0
    @test get_wage(world, m2).current ≈ 2.4
    @test get_preference(world, w1).current ≈ 0.3
    @test get_preference(world, w1).pre ≈ 0.5
    @test get_preference(world, m1).current ≈ 0.5
    @test get_preference(world, m1).pre ≈ 0.6

    @test GN.update_shocks!(world, 61) === nothing
    @test get_wage(world, w1).current ≈ 0.6 + 0.5 * (1.0 - 0.6)
    @test get_wage(world, w2).current ≈ 2.0
    @test get_wage(world, m2).current ≈ 2.4 + 0.5 * (4.0 - 2.4)
    @test get_preference(world, w1).current ≈ 0.3 + 0.5 * (0.5 - 0.3)
    @test get_preference(world, w2).current ≈ 0.5 + 0.5 * (0.7 - 0.5)
    @test get_preference(world, m1).current ≈ 0.5 + 0.5 * (0.6 - 0.5)
end

@testset "update_shocks! without resources is a no-op" begin
    world, women, men = make_shock_world(2)
    w1 = first(women)
    m1 = first(men)

    set_wage!(world, w1, 1.0, 0.5)
    set_preference!(world, m1, 0.4, 0.2)

    @test GN.update_shocks!(world, 60) === nothing
    @test GN.update_shocks!(world, 61) === nothing
    @test get_wage(world, w1).current ≈ 1.0
    @test get_wage(world, w1).old ≈ 0.5
    @test get_preference(world, m1).current ≈ 0.4
    @test get_preference(world, m1).pre ≈ 0.2
end

@testset "update_shocks! alone runs only the present resource" begin
    wage_world, wage_women, wage_men = make_shock_world(2)
    ww = first(wage_women)
    wm = first(wage_men)
    set_wage!(wage_world, ww, 1.0, 0.0)
    set_wage!(wage_world, wm, 1.0, 0.0)
    set_preference!(wage_world, ww, 0.5, 0.0)
    Ark.add_components!(wage_world, ww, (GN.DirectlyAffected(),))
    Ark.add_resource!(wage_world, GN.WageShock(start = 60))

    @test GN.update_shocks!(wage_world, 60) === nothing
    @test get_wage(wage_world, ww).current ≈ 0.6
    @test get_preference(wage_world, ww).current ≈ 0.5
    @test get_preference(wage_world, ww).pre ≈ 0.0

    preference_world, preference_women, preference_men = make_shock_world(2; seed = 31)
    pw = first(preference_women)
    pm = first(preference_men)
    set_wage!(preference_world, pw, 1.0, 0.0)
    set_preference!(preference_world, pw, 0.5, 0.0)
    set_preference!(preference_world, pm, 0.5, 0.0)
    Ark.add_resource!(
        preference_world, GN.PreferenceShock(start = 60, delta_men = 0.2, delta_woman = 0.2)
    )

    @test GN.update_shocks!(preference_world, 60) === nothing
    @test get_wage(preference_world, pw).current ≈ 1.0
    @test get_wage(preference_world, pw).old ≈ 0.0
    @test get_preference(preference_world, pw).current ≈ 0.3
    @test get_preference(preference_world, pw).pre ≈ 0.5
    @test get_preference(preference_world, pm).current ≈ 0.3
end

@testset "select_affected! draws per-sex counts with n-of floor" begin
    world, women, men = make_shock_world(10; seed = 21)
    rng = Random.MersenneTwister(7)

    @test GN.select_affected!(world, 0.0, 30.0, rng) === nothing
    @test count_tagged(world, GN.Male) == 0
    @test count_tagged(world, GN.Female) == 3

    # NetLogo `n-of` rounds a fractional size down: 3 * 50 / 100 = 1.5 -> 1.
    rounding_world, _, _ = make_shock_world(3; seed = 22)
    rounding_rng = Random.MersenneTwister(8)
    @test GN.select_affected!(rounding_world, 50.0, 0.0, rounding_rng) === nothing
    @test count_tagged(rounding_world, GN.Male) == 1
    @test count_tagged(rounding_world, GN.Female) == 0
end

@testset "select_affected! validates the percent range" begin
    world, _, _ = make_shock_world(3; seed = 25)
    rng = Random.MersenneTwister(6)

    @test_throws ArgumentError GN.select_affected!(world, 101.0, 0.0, rng)
    @test_throws ArgumentError GN.select_affected!(world, 0.0, -1.0, rng)
    @test count_tagged(world, GN.Male) == 0
    @test count_tagged(world, GN.Female) == 0
end

@testset "select_affected! throws on a positive share of an empty breed" begin
    world = Ark.World(GN.Male, GN.Female, GN.DirectlyAffected)
    Ark.new_entity!(world, (GN.Female(),))
    rng = Random.MersenneTwister(9)

    @test_throws ArgumentError GN.select_affected!(world, 50.0, 50.0, rng)
    try
        GN.select_affected!(world, 50.0, 50.0, rng)
        @test false
    catch e
        @test occursin("men", sprint(showerror, e))
    end
    # NetLogo `n-of 0` of an empty agentset is empty, not an error.
    @test GN.select_affected!(world, 0.0, 0.0, rng) === nothing
end

@testset "update_wages! grows women wages while a gap remains" begin
    world, women, men = make_shock_world(2)
    w1, w2 = women
    m1, m2 = men

    set_wage!(world, w1, 0.8, 0.8)
    set_wage!(world, w2, 1.0, 1.0)
    set_wage!(world, m1, 1.0, 1.0)
    set_wage!(world, m2, 1.0, 1.0)

    growth = GN.WageGrowth(rate = 1.0)
    daily = (1.0 + 1.0)^(1.0 / 365.0) - 1.0
    @test GN.update_wages!(world, growth) === nothing
    @test get_wage(world, w1).current ≈ 0.8 * (1.0 + daily)
    @test get_wage(world, w2).current ≈ 1.0 * (1.0 + daily)
    @test get_wage(world, w1).old ≈ 0.8
    @test get_wage(world, m1).current ≈ 1.0
    @test get_wage(world, m2).current ≈ 1.0
end

@testset "update_wages! is a no-op without a gap or without a rate" begin
    world, women, men = make_shock_world(2)
    w1 = first(women)

    set_wage!(world, w1, 1.2, 1.2)
    for man in men
        set_wage!(world, man, 1.0, 1.0)
    end
    for woman in women
        if woman != w1
            set_wage!(world, woman, 1.2, 1.2)
        end
    end

    @test GN.update_wages!(world, GN.WageGrowth(rate = 1.0)) === nothing
    @test get_wage(world, w1).current ≈ 1.2

    gap_world, gap_women, gap_men = make_shock_world(1; seed = 23)
    gw = first(gap_women)
    gm = first(gap_men)
    set_wage!(gap_world, gw, 0.5, 0.5)
    set_wage!(gap_world, gm, 1.0, 1.0)
    @test GN.update_wages!(gap_world, GN.WageGrowth(rate = 0.0)) === nothing
    @test get_wage(gap_world, gw).current ≈ 0.5
end

@testset "tick path allocates nothing at steady state" begin
    world, women, men = make_shock_world(4; seed = 24)
    for entity in vcat(women, men)
        set_wage!(world, entity, 1.0, 2.0)
        set_preference!(world, entity, 0.4, 0.6)
    end
    Ark.add_components!(world, first(women), (GN.DirectlyAffected(),))
    Ark.add_components!(world, first(men), (GN.DirectlyAffected(),))
    Ark.add_resource!(world, GN.WageShock(start = 60, depreciation = 0.005))
    Ark.add_resource!(world, GN.PreferenceShock(depreciation = 0.005))

    wage_shock = GN.WageShock()
    preference_shock = GN.PreferenceShock(delta_men = 0.1, delta_woman = 0.1)
    GN.start_shock!(world, wage_shock)
    GN.start_shock!(world, preference_shock)
    GN.recover_shock!(world, wage_shock)
    GN.recover_shock!(world, preference_shock)
    GN.update_shocks!(world, 61)

    @test @allocated(GN.start_shock!(world, wage_shock)) == 0
    @test @allocated(GN.start_shock!(world, preference_shock)) == 0
    @test @allocated(GN.recover_shock!(world, wage_shock)) == 0
    @test @allocated(GN.recover_shock!(world, preference_shock)) == 0
    @test @allocated(GN.update_shocks!(world, 61)) == 0
end
