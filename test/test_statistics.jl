# Tests for the statistics system in `src/systems/statistics.jl`
# (NetLogo `update-statistics`, ODD section Statistics
# (`update-statistics`); see `MDR-0007` and the observer snapshot of
# `MDR-0019`-`MDR-0022`). Each testset builds a small world with
# `initialize_household`, overwrites the observed state with known
# values, and checks the lag copy in
# `update_old_working_time_and_transfer!`, the global means in
# `update_global_working_times!`, and the fused observer snapshot in
# `update_observer_stats!` (working time, pre-adaptation preference,
# committed-bundle utility, and the women's transfer mean) against
# hand-computed values.

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
    Ark.add_resource!(world, GN.WorkingTimeStats(0.0, 0.0, 0.0))
    Ark.add_resource!(world, GN.PreferenceStats(NaN, NaN))
    Ark.add_resource!(world, GN.UtilityStats(NaN, NaN))
    Ark.add_resource!(world, GN.TransferStats(NaN))
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

# Overwrite one agent's observed state for the observer-snapshot tests:
# current working time, current private preference (with a fixed `pre`),
# the committed-bundle utility observation, and the current transfer.
function set_observer_state!(world, entity; h, pref, util, theta)
    Ark.set_components!(
        world,
        entity,
        (
            GN.WorkingTime(h, h),
            GN.PreferencePrivate(pref, pref),
            GN.CommittedUtility(util),
            GN.TransferToWoman(theta, theta),
        ),
    )
    return nothing
end

# The four observer resources as a plain tuple, for before/after
# comparisons on failure paths (nothing may be published).
function observer_aggregates(world)
    working = Ark.get_resource(world, GN.WorkingTimeStats)
    preference = Ark.get_resource(world, GN.PreferenceStats)
    utility = Ark.get_resource(world, GN.UtilityStats)
    transfer = Ark.get_resource(world, GN.TransferStats)
    return (
        working.men, working.women, working.gap,
        preference.men, preference.women,
        utility.men, utility.women,
        transfer.mean,
    )
end

# Function-local allocation probe of the fused observer snapshot
# (`@allocated` in a function body, so no global-scope boxing).
observer_allocs(world) = @allocated GN.update_observer_stats!(world)

@testset "observer snapshot writes sex-distinct hand-computed means" begin
    Random.seed!(32)
    world, women, men = make_world(GN.NoNetwork(), 2)
    w1, w2 = women
    m1, m2 = men

    set_observer_state!(world, w1; h = 0.2, pref = 0.1, util = 2.0, theta = 0.25)
    set_observer_state!(world, w2; h = 0.4, pref = 0.3, util = 4.0, theta = 0.75)
    set_observer_state!(world, m1; h = 0.6, pref = 0.5, util = 1.0, theta = -0.4)
    set_observer_state!(world, m2; h = 0.8, pref = 0.9, util = 3.0, theta = -0.9)

    @test GN.update_observer_stats!(world) === nothing

    working = Ark.get_resource(world, GN.WorkingTimeStats)
    @test working.women ≈ 0.3
    @test working.men ≈ 0.7
    @test working.gap ≈ 0.4
    preference = Ark.get_resource(world, GN.PreferenceStats)
    @test preference.women ≈ 0.2
    @test preference.men ≈ 0.7
    utility = Ark.get_resource(world, GN.UtilityStats)
    @test utility.women ≈ 3.0
    @test utility.men ≈ 2.0
    # the transfer mean averages the women's column only
    @test Ark.get_resource(world, GN.TransferStats).mean ≈ 0.5
end

@testset "transfer mean averages over women only" begin
    Random.seed!(33)
    world, women, men = make_world(GN.NoNetwork(), 3)
    for (entity, theta) in zip(women, (0.2, 0.4, 0.9))
        set_observer_state!(world, entity; h = 0.5, pref = 0.5, util = 1.0, theta = theta)
    end
    # the men's mirrored column deliberately disagrees with their wives'
    for (entity, theta) in zip(men, (-0.5, -0.5, -0.5))
        set_observer_state!(world, entity; h = 0.5, pref = 0.5, util = 1.0, theta = theta)
    end

    GN.update_observer_stats!(world)

    @test Ark.get_resource(world, GN.TransferStats).mean ≈ 0.5
    @test !isequal(Ark.get_resource(world, GN.TransferStats).mean, -0.5)
end

@testset "observer snapshot is pre-adaptation with nonzero lambda" begin
    # `step_model!` observes the preference means after bargaining and
    # before `update_preferences` adapts the agents (MDR-0022): the
    # logged series equals the pre-adaptation mean bitwise although the
    # agents' preferences changed by the time the step returns.
    config = GN.parse_model_config(
        GN.GenderNormsModel,
        Dict{String, Any}(
            "agents_per_gender" => 6,
            "initial_lambda" => 0.5,
            "network" => Dict{String, Any}("type" => "none"),
        ),
    )
    @test config.properties.initial_lambda == 0.5
    world = GN.setup_world(GN.GenderNormsModel, config, Random.MersenneTwister(41))
    women = GN.entities_with(world, GN.Female)
    men = GN.entities_with(world, GN.Male)
    pref_of = e -> Ark.get_components(world, e, (GN.PreferencePrivate,))[1].current

    # The snapshot's own arithmetic on the untouched preference state.
    GN.update_observer_stats!(world)
    pre = Ark.get_resource(world, GN.PreferenceStats)
    pre_women, pre_men = pre.women, pre.men
    @test pre_women ≈ sum(pref_of(e) for e in women) / length(women)
    @test pre_men ≈ sum(pref_of(e) for e in men) / length(men)
    @test 0.0 <= pre_women <= 1.0
    @test 0.0 <= pre_men <= 1.0

    metrics = GN.model_metrics(GN.GenderNormsModel)
    GN.step_model!(GN.GenderNormsModel, world, config, 0)

    # Logged values are the pre-adaptation means, bitwise.
    @test isequal(metrics["preference_women"](world), pre_women)
    @test isequal(metrics["preference_men"](world), pre_men)
    # The step adapted the agents, so the published means are stale on
    # purpose: the observed state and the live state now differ.
    @test !isequal(sum(pref_of(e) for e in women) / length(women), pre_women)
    @test !isequal(sum(pref_of(e) for e in men) / length(men), pre_men)
end

@testset "observer snapshot throws on an empty gender before publishing" begin
    function empty_world(male, female)
        world = Ark.World(
            GN.Male,
            GN.Female,
            GN.WorkingTime,
            GN.PreferencePrivate,
            GN.CommittedUtility,
            GN.TransferToWoman,
        )
        Ark.add_resource!(world, GN.WorkingTimeStats(0.0, 0.0, 0.0))
        Ark.add_resource!(world, GN.PreferenceStats(NaN, NaN))
        Ark.add_resource!(world, GN.UtilityStats(NaN, NaN))
        Ark.add_resource!(world, GN.TransferStats(NaN))
        male && Ark.new_entity!(
            world,
            (
                GN.Male(), GN.WorkingTime(0.6, 0.6), GN.PreferencePrivate(0.5, 0.5),
                GN.CommittedUtility(1.0), GN.TransferToWoman(0.1, 0.1),
            ),
        )
        female && Ark.new_entity!(
            world,
            (
                GN.Female(), GN.WorkingTime(0.2, 0.2), GN.PreferencePrivate(0.3, 0.3),
                GN.CommittedUtility(2.0), GN.TransferToWoman(0.4, 0.4),
            ),
        )
        return world
    end

    # Only men: the missing women are named and nothing is published.
    world = empty_world(true, false)
    before = observer_aggregates(world)
    err = try
        GN.update_observer_stats!(world)
        nothing
    catch e
        e
    end
    @test err isa ArgumentError
    @test err isa ArgumentError && occursin("no women", err.msg)
    @test isequal(observer_aggregates(world), before)

    # Only women: the missing men are named and nothing is published.
    world_women = empty_world(false, true)
    before_women = observer_aggregates(world_women)
    err_women = try
        GN.update_observer_stats!(world_women)
        nothing
    catch e
        e
    end
    @test err_women isa ArgumentError
    @test err_women isa ArgumentError && occursin("no men", err_women.msg)
    @test isequal(observer_aggregates(world_women), before_women)
end

@testset "non-finite utility observations propagate into the means" begin
    Random.seed!(34)
    world, women, men = make_world(GN.NoNetwork(), 2)
    w1, w2 = women
    m1, m2 = men

    set_observer_state!(world, w1; h = 0.2, pref = 0.1, util = -Inf, theta = 0.0)
    set_observer_state!(world, w2; h = 0.4, pref = 0.3, util = 1.0, theta = 0.0)
    set_observer_state!(world, m1; h = 0.6, pref = 0.5, util = NaN, theta = 0.0)
    set_observer_state!(world, m2; h = 0.8, pref = 0.9, util = 3.0, theta = 0.0)

    GN.update_observer_stats!(world)

    utility = Ark.get_resource(world, GN.UtilityStats)
    # no clamping, no zero-filling: the means are exactly the propagated
    # non-finite values
    @test isinf(utility.women) && utility.women < 0
    @test isnan(utility.men)
end

@testset "fused working-time means are bitwise-equal to the standalone reducer" begin
    config = GN.parse_model_config(
        GN.GenderNormsModel,
        Dict{String, Any}(
            "agents_per_gender" => 7,
            "network" => Dict{String, Any}("type" => "none"),
        ),
    )
    world = GN.setup_world(GN.GenderNormsModel, config, Random.MersenneTwister(43))
    women = GN.entities_with(world, GN.Female)
    men = GN.entities_with(world, GN.Male)
    # heterogeneous committed hours and multiple female/male archetypes
    # (the `DirectlyAffected` tag splits the query batches), so the
    # addition order is exercised and must match the standalone order
    GN.set_theta!(world, config.utility)
    for entity in (women[2], women[5], men[3])
        Ark.add_components!(world, entity, (GN.DirectlyAffected(),))
    end
    @test length(
        collect(
            Ark.Query(
                world, (GN.WorkingTime, GN.PreferencePrivate, GN.CommittedUtility, GN.TransferToWoman);
                with = (GN.Female,),
            )
        )
    ) >= 2

    GN.update_global_working_times!(world)
    working = Ark.get_resource(world, GN.WorkingTimeStats)
    standalone = (working.men, working.women, working.gap)
    GN.update_observer_stats!(world)
    @test isequal(working.men, standalone[1])
    @test isequal(working.women, standalone[2])
    @test isequal(working.gap, standalone[3])
end

@testset "fused observer snapshot allocates nothing" begin
    config = GN.parse_model_config(
        GN.GenderNormsModel,
        Dict{String, Any}(
            "agents_per_gender" => 7,
            "network" => Dict{String, Any}("type" => "none"),
        ),
    )
    world = GN.setup_world(GN.GenderNormsModel, config, Random.MersenneTwister(44))
    women = GN.entities_with(world, GN.Female)
    men = GN.entities_with(world, GN.Male)
    GN.set_theta!(world, config.utility)
    # tagged and untagged agents of both sexes: more than one query
    # batch per reduction
    for entity in (women[1], women[4], men[2])
        Ark.add_components!(world, entity, (GN.DirectlyAffected(),))
    end
    GN.update_observer_stats!(world)
    GN.update_observer_stats!(world)
    @test observer_allocs(world) == 0
end
