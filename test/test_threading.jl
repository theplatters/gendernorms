# Tests for the multithreaded world loops of `calculate_norm_perception!`
# (`src/systems/norm_perception.jl`, NetLogo `calculate-utility`, ODD
# section Norm perception) and `set_theta!`
# (`src/systems/household_bargaining.jl`, NetLogo `set-theta` and
# `calculate-payoff`, ODD section Transfer bargaining). Both loops run
# with `Threads.@threads :greedy` over disjoint work items and must be
# bit-identical to the sequential reference for any thread count (see
# `ADR-0014`). The tests build paired identical worlds with the same
# `initialize_household` RNG stream, run the test-local sequential
# reference implementations on one world and the parallel entry points
# on the other, and compare every agent's components and the mean
# results exactly. `test/threading_driver.jl` (not included in
# `test/runtests.jl`) checks full-run determinism across thread counts
# in fresh subprocesses.

using Ark
using GenderNorms
using Graphs
using Random
using Test

const GN = GenderNorms

function make_threading_world(network::GN.NetworkSpec, n::Int, seed::Int)
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
    women, men = GN.initialize_household(world, Random.MersenneTwister(seed))
    return world, women, men
end

function set_threading_state!(world, women, men, seed::Int)
    rng = Random.MersenneTwister(seed)
    for (woman, man) in zip(women, men)
        theta = 2 * rand(rng) - 1
        theta_old = 2 * rand(rng) - 1
        for (entity, lo, span) in ((woman, 0.1, 0.5), (man, 0.4, 0.6))
            h = lo + span * rand(rng)
            h_old = lo + span * rand(rng)
            conformism = 0.5 + 3.0 * rand(rng)
            Ark.set_components!(
                world,
                entity,
                (
                    GN.WorkingTime(h, h_old),
                    GN.TransferToWoman(theta, theta_old),
                    GN.Conformism(conformism),
                ),
            )
        end
    end
    return nothing
end

# Scenario graphs: a connected ring-plus-chords graph (neighbour branch
# of `norm_means`) and empty graphs (fallback branches).
function threading_graphs(kind::Symbol, n::Int)
    if kind === :connected
        women_graph = Graphs.SimpleGraph(n)
        men_graph = Graphs.SimpleGraph(n)
        for i in 1:n
            Graphs.add_edge!(women_graph, i, mod1(i + 1, n))
            Graphs.add_edge!(women_graph, i, mod1(i + 3, n))
            Graphs.add_edge!(men_graph, i, mod1(i + 1, n))
            Graphs.add_edge!(men_graph, i, mod1(i + 3, n))
        end
        return women_graph, men_graph
    end
    return Graphs.SimpleGraph(n), Graphs.SimpleGraph(n)
end

# Sequential reference implementation: verbatim copy of the loop body of
# `calculate_norm_perception!` before `ADR-0014` (module-qualified access
# to the internals of `GenderNorms`).
function serial_calculate_norm_perception!(world, config::GN.UtilityConfig)
    net = Ark.get_resource(world, GN.SocialNetwork)
    properties = Ark.get_resource(world, GN.ModelProperties)
    globals = properties.network isa GN.HomogeneousMixing ? GN.norm_global_means(world, net) : nothing
    spouse_seen = Ark.Entity[]
    for (entities, is_woman) in ((net.women_entities, true), (net.men_entities, false))
        for (vertex, entity) in enumerate(entities)
            means = GN.norm_means(world, net, vertex, is_woman, globals, spouse_seen)
            working_time, transfer, conformism, spouse =
                Ark.get_components(world, entity, (GN.WorkingTime, GN.TransferToWoman, GN.Conformism, GN.Spouse))
            spouse_working_time, = Ark.get_components(world, spouse.entity, (GN.WorkingTime,))
            penalty = GN.norm_penalty(
                conformism.amount, working_time.current, spouse_working_time.current, transfer.current, means, config,
            )
            Ark.set_components!(
                world, entity, (GN.PerceptionNormDivisionOfLabor(means.division_of_labor), GN.NormParameter(penalty)),
            )
        end
    end
    return nothing
end

# Sequential reference implementation: verbatim copy of the loop body of
# `set_theta!` before `ADR-0014` (module-qualified access to the
# internals of `GenderNorms`).
function serial_set_theta!(world, config::GN.UtilityConfig)
    net = Ark.get_resource(world, GN.SocialNetwork)
    properties = Ark.get_resource(world, GN.ModelProperties)
    globals = properties.network isa GN.HomogeneousMixing ? GN.norm_global_means(world, net) : nothing
    women_index = Dict(entity => vertex for (vertex, entity) in enumerate(net.women_entities))
    men_index = Dict(entity => vertex for (vertex, entity) in enumerate(net.men_entities))
    component_types = (GN.Wage, GN.WorkingTime, GN.TransferToWoman, GN.Conformism, GN.PreferencePrivate, GN.Spouse)
    spouse_seen = Ark.Entity[]
    for (entities, wages, times, transfers, conformisms, preferences, spouses) in
        Ark.Query(world, component_types; with=(GN.Female,))
        for f in eachindex(entities)
            woman = entities[f]
            man = spouses[f].entity
            man_wage, man_time, man_transfer, man_conformism, man_preference =
                Ark.get_components(world, man, (GN.Wage, GN.WorkingTime, GN.TransferToWoman, GN.Conformism, GN.PreferencePrivate))
            woman_vertex = get(women_index, woman, 0)
            woman_vertex == 0 && throw(ArgumentError("woman is not in the women entity vector"))
            man_vertex = get(men_index, man, 0)
            man_vertex == 0 && throw(ArgumentError("man is not in the men entity vector"))

            woman_norms = GN.norm_means(world, net, woman_vertex, true, globals, spouse_seen)
            man_norms = GN.norm_means(world, net, man_vertex, false, globals, spouse_seen)

            pw = GN.payoff_params(
                wages[f].current, man_wage.current, preferences[f].current,
                conformisms[f].amount, woman_norms, true
            )
            pm = GN.payoff_params(
                man_wage.current, wages[f].current, man_preference.current,
                man_conformism.amount, man_norms, false
            )

            theta, hw, hm = GN.bargain_transfer(
                times[f].current, man_time.current, transfers[f].current, pw, pm, config
            )
            # the woman is in the query, so the views write in place
            times[f] = GN.WorkingTime(hw, times[f].old)
            transfers[f] = GN.TransferToWoman(theta, transfers[f].old)
            # the man is not in the women's query, so only the entity API exists
            Ark.set_components!(
                world, man, (GN.WorkingTime(hm, man_time.old), GN.TransferToWoman(theta, man_transfer.old))
            )
        end
    end
    return nothing
end

function threading_snapshot(world, entities)
    return map(entities) do entity
        time, transfer, param, percept = Ark.get_components(
            world,
            entity,
            (GN.WorkingTime, GN.TransferToWoman, GN.NormParameter, GN.PerceptionNormDivisionOfLabor),
        )
        (time.current, time.old, transfer.current, transfer.old, param.amount, percept.amount)
    end
end

function threading_means(snapshot)
    n = length(snapshot)
    return (
        sum(s[1] for s in snapshot) / n,
        sum(s[2] for s in snapshot) / n,
        sum(s[3] for s in snapshot) / n,
        sum(s[4] for s in snapshot) / n,
        sum(s[5] for s in snapshot) / n,
        sum(s[6] for s in snapshot) / n,
    )
end

function run_threading_driver(nthreads::Int)
    driver = joinpath(@__DIR__, "threading_driver.jl")
    project = pkgdir(GenderNorms)
    io = IOBuffer()
    run(pipeline(
        `$(Base.julia_cmd()) --startup-file=no --project=$project -t $nthreads $driver`;
        stdout = io,
    ))
    return String(take!(io))
end

@testset "parallel world loops match the sequential reference" begin
    n = 64
    config = GN.UtilityConfig()
    scenarios = (
        (:connected, GN.NoNetwork()),
        (:homogeneous_mixing, GN.HomogeneousMixing()),
        (:isolated, GN.NoNetwork()),
    )
    for (kind, network) in scenarios
        @testset "$kind" begin
            world_a, women_a, men_a = make_threading_world(network, n, 7)
            world_b, women_b, men_b = make_threading_world(network, n, 7)
            set_threading_state!(world_a, women_a, men_a, 8)
            set_threading_state!(world_b, women_b, men_b, 8)
            women_graph_a, men_graph_a = threading_graphs(kind, n)
            women_graph_b, men_graph_b = threading_graphs(kind, n)
            Ark.add_resource!(world_a, GN.SocialNetwork(men_graph_a, women_graph_a, men_a, women_a))
            Ark.add_resource!(world_b, GN.SocialNetwork(men_graph_b, women_graph_b, men_b, women_b))

            serial_calculate_norm_perception!(world_a, config)
            GN.calculate_norm_perception!(world_b, config)
            for (entities_a, entities_b) in ((women_a, women_b), (men_a, men_b))
                snap_a = threading_snapshot(world_a, entities_a)
                snap_b = threading_snapshot(world_b, entities_b)
                @test snap_a == snap_b
                @test threading_means(snap_a) == threading_means(snap_b)
            end

            serial_set_theta!(world_a, config)
            GN.set_theta!(world_b, config)
            for (entities_a, entities_b) in ((women_a, women_b), (men_a, men_b))
                snap_a = threading_snapshot(world_a, entities_a)
                snap_b = threading_snapshot(world_b, entities_b)
                @test snap_a == snap_b
                @test threading_means(snap_a) == threading_means(snap_b)
            end
        end
    end
end

@testset "serial reference matches at chunk boundaries and single item" begin
    # `n = 17` leaves a short final chunk (one household for the
    # bargaining loop) and `n = 1` is a single work item.
    config = GN.UtilityConfig()
    for n in (17, 1)
        @testset "n = $n" begin
            world_a, women_a, men_a = make_threading_world(GN.NoNetwork(), n, 7)
            world_b, women_b, men_b = make_threading_world(GN.NoNetwork(), n, 7)
            set_threading_state!(world_a, women_a, men_a, 8)
            set_threading_state!(world_b, women_b, men_b, 8)
            women_graph_a, men_graph_a = threading_graphs(:connected, n)
            women_graph_b, men_graph_b = threading_graphs(:connected, n)
            Ark.add_resource!(world_a, GN.SocialNetwork(men_graph_a, women_graph_a, men_a, women_a))
            Ark.add_resource!(world_b, GN.SocialNetwork(men_graph_b, women_graph_b, men_b, women_b))

            serial_calculate_norm_perception!(world_a, config)
            GN.calculate_norm_perception!(world_b, config)
            for (entities_a, entities_b) in ((women_a, women_b), (men_a, men_b))
                snap_a = threading_snapshot(world_a, entities_a)
                snap_b = threading_snapshot(world_b, entities_b)
                @test snap_a == snap_b
                @test threading_means(snap_a) == threading_means(snap_b)
            end

            serial_set_theta!(world_a, config)
            GN.set_theta!(world_b, config)
            for (entities_a, entities_b) in ((women_a, women_b), (men_a, men_b))
                snap_a = threading_snapshot(world_a, entities_a)
                snap_b = threading_snapshot(world_b, entities_b)
                @test snap_a == snap_b
                @test threading_means(snap_a) == threading_means(snap_b)
            end
        end
    end
end

@testset "norm perception matches the reference when neighbours share a spouse" begin
    # The spouse-dedup branch of `norm_means` needs two neighbours with
    # the same spouse; only `calculate_norm_perception!` runs on such a
    # world because `set_theta!` would write the shared man twice.
    config = GN.UtilityConfig()
    world_a, women_a, men_a = make_threading_world(GN.NoNetwork(), 4, 9)
    world_b, women_b, men_b = make_threading_world(GN.NoNetwork(), 4, 9)
    set_threading_state!(world_a, women_a, men_a, 10)
    set_threading_state!(world_b, women_b, men_b, 10)
    women_graph = Graphs.SimpleGraph(4)
    Graphs.add_edge!(women_graph, 1, 2)
    Graphs.add_edge!(women_graph, 1, 3)
    men_graph = Graphs.SimpleGraph(4)
    Ark.add_resource!(world_a, GN.SocialNetwork(men_graph, women_graph, men_a, women_a))
    Ark.add_resource!(world_b, GN.SocialNetwork(men_graph, women_graph, men_b, women_b))
    # Women 2 and 3 are neighbours of woman 1 and share man 2 as spouse.
    Ark.set_components!(world_a, women_a[3], (GN.Spouse(men_a[2]),))
    Ark.set_components!(world_b, women_b[3], (GN.Spouse(men_b[2]),))

    serial_calculate_norm_perception!(world_a, config)
    GN.calculate_norm_perception!(world_b, config)

    for (entities_a, entities_b) in ((women_a, women_b), (men_a, men_b))
        snap_a = threading_snapshot(world_a, entities_a)
        snap_b = threading_snapshot(world_b, entities_b)
        @test snap_a == snap_b
        @test threading_means(snap_a) == threading_means(snap_b)
    end
end

@testset "full runs are bit-identical across thread counts" begin
    # Fresh subprocesses (see `ADR-0014`): the active project under
    # `Pkg.test` is a temporary test environment, so the driver is run
    # with the package project explicitly.
    out1 = run_threading_driver(1)
    out4 = run_threading_driver(4)
    @test occursin("mean norm_parameter", out1)
    @test length(out1) > 200
    @test out1 == out4
end
