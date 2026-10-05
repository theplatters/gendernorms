# Tests for the multithreaded world loops of `calculate_norm_perception!`
# (`src/systems/norm_perception.jl`, NetLogo `calculate-utility`, ODD
# section Norm perception) and `set_theta!`
# (`src/systems/household_bargaining.jl`, NetLogo `set-theta` and
# `calculate-payoff`, ODD section Transfer bargaining). Both loops run
# disjoint work items concurrently (both with the bounded worker-task
# scheduling and task-owned `spouse_seen` scratch, `ADR-0023` for
# `set_theta!` and `ADR-0024` for `calculate_norm_perception!`,
# selected by their `chunk` and `schedule` keyword arguments) and must
# be bit-identical to the sequential reference for any thread count and
# any chunking (see `ADR-0014`, `ADR-0023`, and `ADR-0024`). The tests build paired
# identical worlds with the same `initialize_household` RNG stream, run
# the test-local sequential reference implementations on one world and
# the parallel entry points on the other, and compare every agent's
# components and the mean results exactly; the `set_theta!` comparisons
# are bitwise (`threading_bits`) so signed zeros and NaNs cannot hide a
# divergence. `test/threading_driver.jl` (not included in
# `test/runtests.jl`) checks full-run determinism across thread counts,
# same-seed repeat runs, and forced `schedule` values in fresh
# subprocesses, down to per-agent final-state rows.

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
# internals of `GenderNorms`). The `search` keyword selects the
# transfer-search mode handed to the standalone `bargain_transfer`
# entry point (fresh scratch per household), matching the mode
# `set_theta!` passes to its task-owned scratch; the default reproduces
# the historical call exactly.
function serial_set_theta!(world, config::GN.UtilityConfig; search::Symbol = :local)
    net = Ark.get_resource(world, GN.SocialNetwork)
    properties = Ark.get_resource(world, GN.ModelProperties)
    globals = properties.network isa GN.HomogeneousMixing ? GN.norm_global_means(world, net) : nothing
    women_index = Dict(entity => vertex for (vertex, entity) in enumerate(net.women_entities))
    men_index = Dict(entity => vertex for (vertex, entity) in enumerate(net.men_entities))
    component_types = (GN.Wage, GN.WorkingTime, GN.TransferToWoman, GN.Conformism, GN.PreferencePrivate, GN.Spouse, GN.CommittedUtility)
    spouse_seen = Ark.Entity[]
    for (entities, wages, times, transfers, conformisms, preferences, spouses, utilities) in
        Ark.Query(world, component_types; with = (GN.Female,))
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
                conformisms[f].amount, woman_norms, GN.Female()
            )
            pm = GN.payoff_params(
                man_wage.current, wages[f].current, man_preference.current,
                man_conformism.amount, man_norms, GN.Male()
            )

            theta, hw, hm = GN.bargain_transfer(
                times[f].current, man_time.current, transfers[f].current, pw, pm, config;
                search = search,
            )
            # committed-bundle utility observation (`MDR-0019`), verbatim
            # the `set_theta!` commit step
            utility_woman = GN.individual_utility(hw, hm, theta, pw, config)
            utility_man = GN.individual_utility(hm, hw, theta, pm, config)
            # the woman is in the query, so the views write in place
            times[f] = GN.WorkingTime(hw, times[f].old)
            transfers[f] = GN.TransferToWoman(theta, transfers[f].old)
            utilities[f] = GN.CommittedUtility(utility_woman)
            # the man is not in the women's query, so only the entity API exists
            Ark.set_components!(
                world,
                man,
                (
                    GN.WorkingTime(hm, man_time.old),
                    GN.TransferToWoman(theta, man_transfer.old),
                    GN.CommittedUtility(utility_man),
                ),
            )
        end
    end
    return nothing
end

function threading_snapshot(world, entities)
    return map(entities) do entity
        time, transfer, param, percept, utility = Ark.get_components(
            world,
            entity,
            (
                GN.WorkingTime,
                GN.TransferToWoman,
                GN.NormParameter,
                GN.PerceptionNormDivisionOfLabor,
                GN.CommittedUtility,
            ),
        )
        (time.current, time.old, transfer.current, transfer.old, param.amount, percept.amount, utility.value)
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
        sum(s[7] for s in snapshot) / n,
    )
end

# Bit-level projection of one agent snapshot: every recorded Float64
# becomes its `UInt64` bit pattern, so `0.0` and `-0.0` (and distinct
# NaNs) compare distinguishably. Equality of the returned vectors is
# bitwise identity of the committed state, strictly stronger than `==`.
threading_bits(snapshot) = map(row -> map(x -> reinterpret(UInt64, x), row), snapshot)

# Deterministic household regimes for the cohort worlds: one NamedTuple
# per household with the field set `threading_apply_regimes!` consumes,
# drawn from `rng` in the style of `set_threading_state!` plus explicit
# wages and preferences.
function threading_regimes(rng, n::Int)
    return map(1:n) do _
        (
            h_w = 0.1 + 0.5 * rand(rng),
            h_w_old = 0.1 + 0.5 * rand(rng),
            h_m = 0.4 + 0.6 * rand(rng),
            h_m_old = 0.4 + 0.6 * rand(rng),
            theta = 2 * rand(rng) - 1,
            theta_old = 2 * rand(rng) - 1,
            c_w = 0.5 + 3.0 * rand(rng),
            c_m = 0.5 + 3.0 * rand(rng),
            wage_w = 0.6 + 1.2 * rand(rng),
            wage_m = 0.6 + 1.2 * rand(rng),
            pref_w = 0.2 + 0.6 * rand(rng),
            pref_m = 0.2 + 0.6 * rand(rng),
        )
    end
end

# Apply explicit household `regimes` (one NamedTuple per household with
# fields `h_w`, `h_w_old`, `h_m`, `h_m_old`, `theta`, `theta_old`,
# `c_w`, `c_m`, `wage_w`, `wage_m`, `pref_w`, `pref_m`) to one world.
function threading_apply_regimes!(world, women, men, regimes)
    length(regimes) == length(women) ||
        throw(ArgumentError("need one regime per household"))
    for (woman, man, regime) in zip(women, men, regimes)
        Ark.set_components!(
            world,
            woman,
            (
                GN.WorkingTime(regime.h_w, regime.h_w_old),
                GN.TransferToWoman(regime.theta, regime.theta_old),
                GN.Conformism(regime.c_w),
                GN.Wage(regime.wage_w, regime.wage_w),
                GN.PreferencePrivate(regime.pref_w, regime.pref_w),
            ),
        )
        Ark.set_components!(
            world,
            man,
            (
                GN.WorkingTime(regime.h_m, regime.h_m_old),
                GN.TransferToWoman(regime.theta, regime.theta_old),
                GN.Conformism(regime.c_m),
                GN.Wage(regime.wage_m, regime.wage_m),
                GN.PreferencePrivate(regime.pref_m, regime.pref_m),
            ),
        )
    end
    return nothing
end

# Build `count` identically seeded worlds (the same `seed` makes the
# `initialize_household` draws identical), each with the explicit
# household `regimes` applied and its own copy of the scenario graphs
# of `threading_graphs(kind, n)`.
function threading_cohort(
        network::GN.NetworkSpec, kind::Symbol, n::Int, seed::Int, regimes, count::Int
    )
    cohort = Tuple{Ark.World, Vector{Ark.Entity}, Vector{Ark.Entity}}[]
    for _ in 1:count
        world, women, men = make_threading_world(network, n, seed)
        threading_apply_regimes!(world, women, men, regimes)
        women_graph, men_graph = threading_graphs(kind, n)
        Ark.add_resource!(world, GN.SocialNetwork(men_graph, women_graph, men, women))
        push!(cohort, (world, women, men))
    end
    return cohort
end

# Run the sequential oracle on `cohort[1]` and `set_theta!` with each
# `(chunk, schedule)` variant on the remaining worlds. Returns
# `(reference, runs)`: `reference` is the oracle's `(women, men)`
# snapshot pair, `runs` one snapshot pair per variant in order. All
# cross-comparisons must use `threading_bits` (bitwise identity).
function threading_theta_variants(
        cohort, config::GN.UtilityConfig, variants; search::Symbol = :local
    )
    world_a, women_a, men_a = cohort[1]
    serial_set_theta!(world_a, config; search = search)
    reference = (threading_snapshot(world_a, women_a), threading_snapshot(world_a, men_a))
    runs = typeof(reference)[]
    for (index, (chunk, schedule)) in enumerate(variants)
        world_b, women_b, men_b = cohort[index + 1]
        GN.set_theta!(world_b, config; search = search, chunk = chunk, schedule = schedule)
        push!(runs, (threading_snapshot(world_b, women_b), threading_snapshot(world_b, men_b)))
    end
    return reference, runs
end

# Run the sequential oracle on `cohort[1]` and
# `calculate_norm_perception!` with each `(chunk, schedule)` variant on
# the remaining worlds. Returns `(reference, runs)` in the layout of
# `threading_theta_variants`; all cross-comparisons must use
# `threading_bits` (bitwise identity).
function threading_norm_variants(cohort, config::GN.UtilityConfig, variants)
    world_a, women_a, men_a = cohort[1]
    serial_calculate_norm_perception!(world_a, config)
    reference = (threading_snapshot(world_a, women_a), threading_snapshot(world_a, men_a))
    runs = typeof(reference)[]
    for (index, (chunk, schedule)) in enumerate(variants)
        world_b, women_b, men_b = cohort[index + 1]
        GN.calculate_norm_perception!(world_b, config; chunk = chunk, schedule = schedule)
        push!(runs, (threading_snapshot(world_b, women_b), threading_snapshot(world_b, men_b)))
    end
    return reference, runs
end

# Build `count` identically seeded shared-spouse worlds of the
# spouse-dedup fixture: `n = 4` women and men drawn with the seeds of
# the dedup testset below, women 2 and 3 neighbours of woman 1 and both
# wired to man 2 as spouse, so `norm_means` deduplicates the shared
# spouse (`MDR-0004` first-occurrence order).
function threading_shared_spouse_cohort(count::Int)
    cohort = Tuple{Ark.World, Vector{Ark.Entity}, Vector{Ark.Entity}}[]
    for _ in 1:count
        world, women, men = make_threading_world(GN.NoNetwork(), 4, 9)
        set_threading_state!(world, women, men, 10)
        women_graph = Graphs.SimpleGraph(4)
        Graphs.add_edge!(women_graph, 1, 2)
        Graphs.add_edge!(women_graph, 1, 3)
        men_graph = Graphs.SimpleGraph(4)
        Ark.add_resource!(world, GN.SocialNetwork(men_graph, women_graph, men, women))
        Ark.set_components!(world, women[3], (GN.Spouse(men[2]),))
        push!(cohort, (world, women, men))
    end
    return cohort
end

# The printed lines of one `test/threading_driver.jl` block: every line
# starting with `prefix`, with the prefix stripped, in printed order.
function threading_driver_block(output::AbstractString, prefix::AbstractString)
    lines = String[]
    for line in split(output, '\n')
        (isempty(line) || !startswith(line, prefix)) && continue
        push!(lines, chopprefix(line, prefix))
    end
    return lines
end

function run_threading_driver(nthreads::Int)
    driver = joinpath(@__DIR__, "threading_driver.jl")
    project = pkgdir(GenderNorms)
    io = IOBuffer()
    run(
        pipeline(
            `$(Base.julia_cmd()) --startup-file=no --project=$project -t $nthreads $driver`;
            stdout = io,
        )
    )
    return String(take!(io))
end

# Run `f()` and return the thrown exception, or `nothing` when `f`
# returns normally; used to inspect the exact exception shape of the
# worker-failure tests instead of only its type via `@test_throws`.
function threading_captured(f)
    try
        f()
    catch err
        return err
    end
    return nothing
end

# Flatten a thrown exception into its root causes: a worker-task failure
# surfaces through the `@sync` join of `set_theta!` as a
# `TaskFailedException` and/or `CompositeException` around the exception
# the task threw (`ADR-0023`), so the guard `ArgumentError` sits at the
# bottom of the chain and must be pinned through the walk.
function threading_leaf_exceptions(err)
    leaves = Any[]
    stack = Any[err]
    while !isempty(stack)
        current = pop!(stack)
        if current isa TaskFailedException
            push!(stack, current.task.exception)
        elseif current isa CompositeException
            append!(stack, current.exceptions)
        else
            push!(leaves, current)
        end
    end
    return leaves
end

# Failure fixture: a full clone of the household's man that is
# deliberately missing from the `SocialNetwork` entity vectors, wired
# in as the last woman's spouse. `set_theta!` resolves the man through
# the entity-to-vertex map and throws its
# `man is not in the men entity vector` `ArgumentError` guard for this
# household, before writing anything of it.
function threading_unindexed_spouse!(world, women, men)
    parts = Ark.get_components(
        world,
        men[end],
        (
            GN.Male,
            GN.WorkingTime,
            GN.Wage,
            GN.Conformism,
            GN.PreferencePrivate,
            GN.NormParameter,
            GN.PerceptionNormDivisionOfLabor,
            GN.Lambda,
            GN.TransferToWoman,
            GN.CommittedUtility,
            GN.Spouse,
        ),
    )
    ghost = Ark.new_entity!(world, parts)
    Ark.set_components!(world, women[end], (GN.Spouse(ghost),))
    return ghost
end

# Full-state bit snapshot for the worker-failure tests: every component
# of `entities`, each Float64 as its `UInt64` bit pattern (as in
# `threading_bits`) and the `Spouse` handle verbatim, so `0.0`/`-0.0`,
# distinct NaNs, or a rewired spouse cannot hide a divergence between
# two snapshots of the same world.
function threading_state_bits(world, entities)
    return map(entities) do entity
        time, transfer, wage, pref, conf, param, percept, lambda, utility, spouse = Ark.get_components(
            world,
            entity,
            (
                GN.WorkingTime,
                GN.TransferToWoman,
                GN.Wage,
                GN.PreferencePrivate,
                GN.Conformism,
                GN.NormParameter,
                GN.PerceptionNormDivisionOfLabor,
                GN.Lambda,
                GN.CommittedUtility,
                GN.Spouse,
            ),
        )
        return map(
            x -> x isa Float64 ? reinterpret(UInt64, x) : x,
            (
                time.current,
                time.old,
                transfer.current,
                transfer.old,
                wage.current,
                wage.old,
                pref.current,
                pref.pre,
                conf.amount,
                param.amount,
                percept.amount,
                lambda.amount,
                utility.value,
                spouse.entity,
            ),
        )
    end
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
            for schedule in (:parallel, :serial)
                GN.calculate_norm_perception!(world_b, config; chunk = 3, schedule = schedule)
                for (entities_a, entities_b) in ((women_a, women_b), (men_a, men_b))
                    snap_a = threading_snapshot(world_a, entities_a)
                    snap_b = threading_snapshot(world_b, entities_b)
                    # Bitwise comparison (as in `threading_bits`), so
                    # signed zeros and NaNs (the unobserved
                    # `CommittedUtility` of norm-only runs) cannot hide
                    # a divergence.
                    @test threading_bits(snap_a) == threading_bits(snap_b)
                    @test isequal(threading_means(snap_a), threading_means(snap_b))
                end
            end

            serial_set_theta!(world_a, config)
            GN.set_theta!(world_b, config)
            for (entities_a, entities_b) in ((women_a, women_b), (men_a, men_b))
                snap_a = threading_snapshot(world_a, entities_a)
                snap_b = threading_snapshot(world_b, entities_b)
                @test threading_bits(snap_a) == threading_bits(snap_b)
                @test isequal(threading_means(snap_a), threading_means(snap_b))
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
            for schedule in (:parallel, :serial)
                GN.calculate_norm_perception!(world_b, config; chunk = 3, schedule = schedule)
                for (entities_a, entities_b) in ((women_a, women_b), (men_a, men_b))
                    snap_a = threading_snapshot(world_a, entities_a)
                    snap_b = threading_snapshot(world_b, entities_b)
                    @test threading_bits(snap_a) == threading_bits(snap_b)
                    @test isequal(threading_means(snap_a), threading_means(snap_b))
                end
            end

            serial_set_theta!(world_a, config)
            GN.set_theta!(world_b, config)
            for (entities_a, entities_b) in ((women_a, women_b), (men_a, men_b))
                snap_a = threading_snapshot(world_a, entities_a)
                snap_b = threading_snapshot(world_b, entities_b)
                @test threading_bits(snap_a) == threading_bits(snap_b)
                @test isequal(threading_means(snap_a), threading_means(snap_b))
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
    for schedule in (:parallel, :serial)
        GN.calculate_norm_perception!(world_b, config; chunk = 3, schedule = schedule)
        for (entities_a, entities_b) in ((women_a, women_b), (men_a, men_b))
            snap_a = threading_snapshot(world_a, entities_a)
            snap_b = threading_snapshot(world_b, entities_b)
            @test threading_bits(snap_a) == threading_bits(snap_b)
            @test isequal(threading_means(snap_a), threading_means(snap_b))
        end
    end
end

@testset "norm perception chunk sizes and schedules match the oracle bitwise" begin
    # Every `(chunk, schedule)` variant of `calculate_norm_perception!`
    # (`ADR-0024`) on a short-chunk world (`n = 17`: one full plus one
    # partial chunk at `chunk = 16`, many chunks at `chunk = 1`) and on
    # the shared-spouse world of the dedup branch (`n = 4`), checked
    # bitwise against the serial oracle and against each other: the
    # arithmetic chunk decode, the task-owned scratch reuse across
    # chunks, and the worker path at tiny and huge chunk counts must not
    # change a single bit (TASK-0026).
    config = GN.UtilityConfig()
    variants = Tuple{Int, Symbol}[
        (chunk, schedule) for schedule in (:serial, :parallel, :auto) for chunk in (1, 3, 16, 64, 256)
    ]
    regimes = threading_regimes(Random.MersenneTwister(8), 17)
    short_cohort = threading_cohort(
        GN.NoNetwork(), :connected, 17, 7, regimes, length(variants) + 1
    )
    for (label, cohort) in (
            ("short-chunk n = 17", short_cohort),
            ("shared-spouse n = 4", threading_shared_spouse_cohort(length(variants) + 1)),
        )
        @testset "$label" begin
            reference, runs = threading_norm_variants(cohort, config, variants)
            for run in runs
                @test threading_bits(run[1]) == threading_bits(reference[1])
                @test threading_bits(run[2]) == threading_bits(reference[2])
            end
            for run in runs
                @test threading_bits(run[1]) == threading_bits(runs[1][1])
                @test threading_bits(run[2]) == threading_bits(runs[1][2])
            end
        end
    end
end

@testset "norm perception :auto matches the oracle above the serial cutoff" begin
    # The `:auto` schedule selects the parallel path above
    # `NORM_PERCEPTION_SERIAL_CUTOFF` total agents on multithreaded runs
    # and the serial path otherwise; the population is derived from the
    # constant (its value is provisional and not pinned) so the parallel
    # branch runs at `JULIA_NUM_THREADS = 8` whatever the crossover is
    # tuned to (TASK-0026). The first run uses the pinned
    # two-positional-argument defaults, the second one a chunk per agent.
    config = GN.UtilityConfig()
    n = cld(GN.NORM_PERCEPTION_SERIAL_CUTOFF, 2) + 1
    regimes = threading_regimes(Random.MersenneTwister(8), n)
    cohort = threading_cohort(GN.NoNetwork(), :connected, n, 7, regimes, 3)
    world_a, women_a, men_a = cohort[1]
    serial_calculate_norm_perception!(world_a, config)
    reference = (threading_snapshot(world_a, women_a), threading_snapshot(world_a, men_a))
    runs = typeof(reference)[]
    world_b, women_b, men_b = cohort[2]
    GN.calculate_norm_perception!(world_b, config)
    push!(runs, (threading_snapshot(world_b, women_b), threading_snapshot(world_b, men_b)))
    world_c, women_c, men_c = cohort[3]
    GN.calculate_norm_perception!(world_c, config; chunk = 1, schedule = :auto)
    push!(runs, (threading_snapshot(world_c, women_c), threading_snapshot(world_c, men_c)))
    for run in runs
        @test threading_bits(run[1]) == threading_bits(reference[1])
        @test threading_bits(run[2]) == threading_bits(reference[2])
    end
end

@testset "norm perception matches the oracle with fewer chunks than workers" begin
    # Two chunks for up to eight workers (`n = 2`, `chunk = 16`) and one
    # chunk per gender (`n = 1`, `chunk = 64`): idle workers must not
    # disturb the processed chunks (TASK-0026).
    config = GN.UtilityConfig()
    for (n, chunk) in ((2, 16), (1, 64))
        @testset "n = $n, chunk = $chunk" begin
            regimes = threading_regimes(Random.MersenneTwister(8), n)
            variants = ((chunk, :parallel), (chunk, :auto))
            cohort = threading_cohort(
                GN.NoNetwork(), :connected, n, 7, regimes, length(variants) + 1
            )
            reference, runs = threading_norm_variants(cohort, config, variants)
            for run in runs
                @test threading_bits(run[1]) == threading_bits(reference[1])
                @test threading_bits(run[2]) == threading_bits(reference[2])
            end
        end
    end
end

@testset "norm perception many-chunk parallel runs never share worker scratch" begin
    # Regression for the task-owned scratch of `ADR-0024` (TASK-0026):
    # 130 chunks of one agent (`n = 65`, `chunk = 1`) and 66 chunks
    # (`n = 130`, `chunk = 4`) force every worker task to pull many
    # chunks concurrently and reuse its `spouse_seen` buffer across
    # them; scratch shared between concurrent workers corrupts the
    # spouse dedup and fails these bitwise comparisons loudly.
    config = GN.UtilityConfig()
    for (n, chunk) in ((65, 1), (130, 4))
        @testset "n = $n, chunk = $chunk" begin
            regimes = threading_regimes(Random.MersenneTwister(8), n)
            variants = ((chunk, :parallel),)
            cohort = threading_cohort(
                GN.NoNetwork(), :connected, n, 7, regimes, length(variants) + 1
            )
            reference, runs = threading_norm_variants(cohort, config, variants)
            for run in runs
                @test threading_bits(run[1]) == threading_bits(reference[1])
                @test threading_bits(run[2]) == threading_bits(reference[2])
            end
        end
    end
end

@testset "norm perception validates chunk and schedule before touching the world" begin
    config = GN.UtilityConfig()
    @test_throws ArgumentError GN.calculate_norm_perception!(Ark.World(), config; chunk = 0)
    @test_throws ArgumentError GN.calculate_norm_perception!(Ark.World(), config; chunk = -1)
    @test_throws ArgumentError GN.calculate_norm_perception!(
        Ark.World(), config; chunk = -3, schedule = :parallel
    )
    @test_throws ArgumentError GN.calculate_norm_perception!(Ark.World(), config; schedule = :bogus)
    # All validation precedes every write and every worker task: a
    # populated world is bit-untouched by the failing calls (TASK-0026).
    regimes = threading_regimes(Random.MersenneTwister(8), 4)
    world, women, men = threading_cohort(GN.NoNetwork(), :connected, 4, 7, regimes, 1)[1]
    before = (
        threading_bits(threading_snapshot(world, women)),
        threading_bits(threading_snapshot(world, men)),
    )
    @test_throws ArgumentError GN.calculate_norm_perception!(
        world, config; chunk = 0, schedule = :parallel
    )
    @test_throws ArgumentError GN.calculate_norm_perception!(
        world, config; chunk = -1, schedule = :parallel
    )
    @test_throws ArgumentError GN.calculate_norm_perception!(
        world, config; chunk = 4, schedule = :bogus
    )
    after = (
        threading_bits(threading_snapshot(world, women)),
        threading_bits(threading_snapshot(world, men)),
    )
    @test after == before
end

@testset "norm perception runs zero chunks on empty worlds" begin
    # A zero-agent world runs zero chunks on every path, and a world
    # with one empty gender processes only the other gender: zero
    # chunks must be a no-op for that gender (TASK-0026).
    config = GN.UtilityConfig()
    world, women, men = make_threading_world(GN.NoNetwork(), 0, 7)
    women_graph, men_graph = threading_graphs(:connected, 0)
    Ark.add_resource!(world, GN.SocialNetwork(men_graph, women_graph, men, women))
    before = (
        threading_bits(threading_snapshot(world, women)),
        threading_bits(threading_snapshot(world, men)),
    )
    for schedule in (:auto, :serial, :parallel)
        @test GN.calculate_norm_perception!(world, config; chunk = 4, schedule = schedule) === nothing
    end
    after = (
        threading_bits(threading_snapshot(world, women)),
        threading_bits(threading_snapshot(world, men)),
    )
    @test after == before
    @test isempty(women)
    @test isempty(men)

    # One empty gender: the women entity vector and the women graph are
    # empty, only the men run, and both snapshots match the serial
    # oracle bitwise.
    world_a, women_a, men_a = make_threading_world(GN.NoNetwork(), 4, 7)
    set_threading_state!(world_a, women_a, men_a, 8)
    world_b, women_b, men_b = make_threading_world(GN.NoNetwork(), 4, 7)
    set_threading_state!(world_b, women_b, men_b, 8)
    for (world_one, women_one, men_one) in ((world_a, women_a, men_a), (world_b, women_b, men_b))
        _, men_graph_one = threading_graphs(:connected, 4)
        Ark.add_resource!(
            world_one,
            GN.SocialNetwork(men_graph_one, Graphs.SimpleGraph(0), men_one, Ark.Entity[]),
        )
    end
    serial_calculate_norm_perception!(world_a, config)
    for schedule in (:auto, :serial, :parallel)
        GN.calculate_norm_perception!(world_b, config; chunk = 3, schedule = schedule)
        for (entities_a, entities_b) in ((women_a, women_b), (men_a, men_b))
            @test threading_bits(threading_snapshot(world_a, entities_a)) ==
                threading_bits(threading_snapshot(world_b, entities_b))
        end
    end

    # One empty gender, mirrored: the men entity vector and the men
    # graph are empty, only the women run, and both snapshots match
    # the serial oracle bitwise.
    world_c, women_c, men_c = make_threading_world(GN.NoNetwork(), 4, 7)
    set_threading_state!(world_c, women_c, men_c, 8)
    world_d, women_d, men_d = make_threading_world(GN.NoNetwork(), 4, 7)
    set_threading_state!(world_d, women_d, men_d, 8)
    for (world_one, women_one, men_one) in ((world_c, women_c, men_c), (world_d, women_d, men_d))
        women_graph_one, _ = threading_graphs(:connected, 4)
        Ark.add_resource!(
            world_one,
            GN.SocialNetwork(Graphs.SimpleGraph(0), women_graph_one, Ark.Entity[], women_one),
        )
    end
    serial_calculate_norm_perception!(world_c, config)
    for schedule in (:auto, :serial, :parallel)
        GN.calculate_norm_perception!(world_d, config; chunk = 3, schedule = schedule)
        for (entities_c, entities_d) in ((women_c, women_d), (men_c, men_d))
            @test threading_bits(threading_snapshot(world_c, entities_c)) ==
                threading_bits(threading_snapshot(world_d, entities_d))
        end
    end
end

@testset "set_theta! chunk sizes match the oracle and the chunk-4 run bitwise" begin
    # Every production chunk size (4, 8, 16, 32) and edge sizes (1, 3)
    # on the serial path and the bounded-worker path, checked bitwise
    # against the serial oracle and against a forced `chunk = 4`
    # reference run; `n = 17` leaves a short final chunk at every size.
    config = GN.UtilityConfig()
    n = 17
    regimes = threading_regimes(Random.MersenneTwister(8), n)
    variants = (
        (4, :parallel),  # the chunk-4 reference run
        (1, :parallel),
        (3, :parallel),
        (8, :parallel),
        (16, :parallel),
        (32, :parallel),
        (1, :serial),
        (3, :serial),
        (4, :serial),
        (8, :serial),
        (16, :serial),
        (32, :serial),
        (4, :auto),
    )
    for search in (:local, :discovery)
        @testset "$search" begin
            cohort = threading_cohort(GN.NoNetwork(), :connected, n, 7, regimes, length(variants) + 1)
            reference, runs = threading_theta_variants(cohort, config, variants; search = search)
            chunk4 = runs[1]
            for run in runs
                @test threading_bits(run[1]) == threading_bits(reference[1])
                @test threading_bits(run[2]) == threading_bits(reference[2])
                @test threading_bits(run[1]) == threading_bits(chunk4[1])
                @test threading_bits(run[2]) == threading_bits(chunk4[2])
            end
        end
    end
end

@testset "set_theta! matches the oracle on incomplete final chunks" begin
    # One full plus one partial chunk (`n = 17`, `chunk = 16`), a
    # single partial chunk (`n = 5`, `chunk = 8`), and two full plus
    # one partial chunk (`n = 7`, `chunk = 3`).
    config = GN.UtilityConfig()
    for (n, chunk) in ((17, 16), (5, 8), (7, 3))
        for search in (:local, :discovery)
            @testset "n = $n, chunk = $chunk, $search" begin
                regimes = threading_regimes(Random.MersenneTwister(8), n)
                variants = ((chunk, :parallel), (chunk, :serial), (chunk, :auto))
                cohort = threading_cohort(GN.NoNetwork(), :connected, n, 7, regimes, length(variants) + 1)
                reference, runs = threading_theta_variants(cohort, config, variants; search = search)
                for run in runs
                    @test threading_bits(run[1]) == threading_bits(reference[1])
                    @test threading_bits(run[2]) == threading_bits(reference[2])
                end
            end
        end
    end
end

@testset "set_theta! schedules agree bitwise at $(Threads.nthreads()) thread(s)" begin
    # Forced `:serial`, forced `:parallel`, and `:auto`, each bitwise
    # identical to the serial oracle and to each other; forced
    # `:parallel` runs the bounded worker path even at one thread
    # (`nworkers = min(nthreads, nchunks)`), and the whole suite runs
    # under `JULIA_NUM_THREADS = 1` and `= 8`, so every thread context
    # sees all three schedules.
    config = GN.UtilityConfig()
    n = 17
    regimes = threading_regimes(Random.MersenneTwister(8), n)
    variants = ((4, :serial), (4, :parallel), (4, :auto))
    for search in (:local, :discovery)
        @testset "$search" begin
            cohort = threading_cohort(GN.NoNetwork(), :connected, n, 7, regimes, length(variants) + 1)
            reference, runs = threading_theta_variants(cohort, config, variants; search = search)
            for run in runs
                @test threading_bits(run[1]) == threading_bits(reference[1])
                @test threading_bits(run[2]) == threading_bits(reference[2])
            end
            for run in runs
                @test threading_bits(run[1]) == threading_bits(runs[1][1])
                @test threading_bits(run[2]) == threading_bits(runs[1][2])
            end
        end
    end
end

@testset "set_theta! runs no households on an empty world" begin
    # A zero-household world runs zero chunks on every path and never
    # errors or writes (TASK-0025 item 4).
    config = GN.UtilityConfig()
    for search in (:local, :discovery)
        @testset "$search" begin
            world, women, men = make_threading_world(GN.NoNetwork(), 0, 7)
            women_graph, men_graph = threading_graphs(:connected, 0)
            Ark.add_resource!(world, GN.SocialNetwork(men_graph, women_graph, men, women))
            before = (
                threading_bits(threading_snapshot(world, women)),
                threading_bits(threading_snapshot(world, men)),
            )
            for schedule in (:auto, :serial, :parallel)
                @test GN.set_theta!(
                    world, config; search = search, chunk = 4, schedule = schedule
                ) === nothing
            end
            after = (
                threading_bits(threading_snapshot(world, women)),
                threading_bits(threading_snapshot(world, men)),
            )
            @test after == before
            @test isempty(women)
            @test isempty(men)
        end
    end
end

@testset "set_theta! matches the oracle with fewer chunks than workers" begin
    # Three chunks for up to eight workers (`n = 10`, `chunk = 4`) and
    # one chunk for up to eight workers (`n = 2`, `chunk = 16`): idle
    # workers must not disturb the processed chunks (TASK-0025 item 5).
    config = GN.UtilityConfig()
    for (n, chunk) in ((10, 4), (2, 16))
        for search in (:local, :discovery)
            @testset "n = $n, chunk = $chunk, $search" begin
                regimes = threading_regimes(Random.MersenneTwister(8), n)
                variants = ((chunk, :parallel), (chunk, :auto))
                cohort = threading_cohort(GN.NoNetwork(), :connected, n, 7, regimes, length(variants) + 1)
                reference, runs = threading_theta_variants(cohort, config, variants; search = search)
                for run in runs
                    @test threading_bits(run[1]) == threading_bits(reference[1])
                    @test threading_bits(run[2]) == threading_bits(reference[2])
                end
            end
        end
    end
end

@testset "set_theta! many-chunk parallel runs never share worker scratch" begin
    # Regression for the concurrent scratch-sharing race of `ADR-0023`
    # (TASK-0025 item 6): 65 chunks of one household (`n = 65`,
    # `chunk = 1`) and 33 chunks (`n = 130`, `chunk = 4`) force every
    # worker task to pull many chunks concurrently; scratch shared
    # between concurrent workers corrupts committed state and fails
    # these bitwise comparisons loudly.
    config = GN.UtilityConfig()
    for (n, chunk) in ((65, 1), (130, 4))
        for search in (:local, :discovery)
            @testset "n = $n, chunk = $chunk, $search" begin
                regimes = threading_regimes(Random.MersenneTwister(8), n)
                variants = ((chunk, :parallel),)
                cohort = threading_cohort(GN.NoNetwork(), :connected, n, 7, regimes, length(variants) + 1)
                reference, runs = threading_theta_variants(cohort, config, variants; search = search)
                for run in runs
                    @test threading_bits(run[1]) == threading_bits(reference[1])
                    @test threading_bits(run[2]) == threading_bits(reference[2])
                end
            end
        end
    end
end

@testset "set_theta! results ignore heterogeneous solve costs" begin
    # Four regime families with widely different per-household solve
    # and search costs (cheap interior solves, a hard high-conformism
    # corner search, a zero-wage status fallback, and boundary hours
    # and transfers): dynamic chunk scheduling may only move work
    # between workers, never change results (TASK-0025 item 7).
    config = GN.UtilityConfig()
    easy = (
        h_w = 0.5, h_w_old = 0.5, h_m = 0.5, h_m_old = 0.5, theta = 0.0, theta_old = 0.0,
        c_w = 0.0, c_m = 0.0, wage_w = 1.0, wage_m = 1.0, pref_w = 0.5, pref_m = 0.5,
    )
    hard = (
        h_w = 0.05, h_w_old = 0.2, h_m = 0.98, h_m_old = 0.8, theta = 0.93, theta_old = -0.6,
        c_w = 12.0, c_m = 25.0, wage_w = 0.15, wage_m = 3.5, pref_w = 0.85, pref_m = 0.15,
    )
    fallback = (
        h_w = 0.3, h_w_old = 0.3, h_m = 0.7, h_m_old = 0.7, theta = -0.7, theta_old = 0.2,
        c_w = 5.0, c_m = 5.0, wage_w = 0.0, wage_m = 0.0, pref_w = 0.5, pref_m = 0.5,
    )
    corner = (
        h_w = 0.0, h_w_old = 0.1, h_m = 1.0, h_m_old = 0.9, theta = -0.999, theta_old = 0.999,
        c_w = 25.0, c_m = 1.0, wage_w = 4.0, wage_m = 0.05, pref_w = 0.02, pref_m = 0.98,
    )
    families = (easy, hard, fallback, corner)
    regimes = [families[mod1(i, 4)] for i in 1:24]
    variants = ((1, :parallel), (3, :parallel), (7, :parallel), (4, :serial), (4, :auto))
    for search in (:local, :discovery)
        @testset "$search" begin
            cohort = threading_cohort(GN.NoNetwork(), :connected, 24, 7, regimes, length(variants) + 1)
            reference, runs = threading_theta_variants(cohort, config, variants; search = search)
            for run in runs
                @test threading_bits(run[1]) == threading_bits(reference[1])
                @test threading_bits(run[2]) == threading_bits(reference[2])
            end
        end
    end
end

@testset "set_theta! preserves signed-zero transfers bitwise" begin
    # `bargain_transfer` treats its `theta0 === 0.0` guard as strict
    # bitwise identity (`-0.0 === 0.0` is false), so a `-0.0` status
    # quo must survive the status fallback commit with its sign; the
    # cross-path comparisons use `threading_bits`, so `0.0` and `-0.0`
    # cannot hide a divergence (TASK-0025 item 8).
    config = GN.UtilityConfig()
    zero_wage_neg = (
        h_w = 0.3, h_w_old = 0.3, h_m = 0.6, h_m_old = 0.6, theta = -0.0, theta_old = 0.4,
        c_w = 1.0, c_m = 1.0, wage_w = 0.0, wage_m = 0.0, pref_w = 0.5, pref_m = 0.5,
    )
    zero_wage_pos = (
        h_w = 0.3, h_w_old = 0.3, h_m = 0.6, h_m_old = 0.6, theta = 0.0, theta_old = 0.4,
        c_w = 1.0, c_m = 1.0, wage_w = 0.0, wage_m = 0.0, pref_w = 0.5, pref_m = 0.5,
    )
    symmetric_neg = (
        h_w = 0.5, h_w_old = 0.5, h_m = 0.5, h_m_old = 0.5, theta = -0.0, theta_old = 0.3,
        c_w = 0.0, c_m = 0.0, wage_w = 1.0, wage_m = 1.0, pref_w = 0.5, pref_m = 0.5,
    )
    symmetric_pos = (
        h_w = 0.5, h_w_old = 0.5, h_m = 0.5, h_m_old = 0.5, theta = 0.0, theta_old = 0.3,
        c_w = 0.0, c_m = 0.0, wage_w = 1.0, wage_m = 1.0, pref_w = 0.5, pref_m = 0.5,
    )
    regimes = [
        zero_wage_neg,
        zero_wage_pos,
        symmetric_neg,
        symmetric_pos,
        (
            h_w = 0.35, h_w_old = 0.3, h_m = 0.72, h_m_old = 0.7, theta = -0.0, theta_old = 0.1,
            c_w = 2.0, c_m = 1.5, wage_w = 1.2, wage_m = 0.8, pref_w = 0.4, pref_m = 0.6,
        ),
        (
            h_w = 0.55, h_w_old = 0.5, h_m = 0.85, h_m_old = 0.8, theta = 0.0, theta_old = 0.2,
            c_w = 1.0, c_m = 2.5, wage_w = 0.9, wage_m = 1.1, pref_w = 0.5, pref_m = 0.45,
        ),
        (
            h_w = 0.35, h_w_old = 0.3, h_m = 0.72, h_m_old = 0.7, theta = -0.31, theta_old = 0.1,
            c_w = 2.0, c_m = 1.5, wage_w = 1.2, wage_m = 0.8, pref_w = 0.4, pref_m = 0.6,
        ),
        (
            h_w = 0.55, h_w_old = 0.5, h_m = 0.85, h_m_old = 0.8, theta = 0.42, theta_old = 0.2,
            c_w = 1.0, c_m = 2.5, wage_w = 0.9, wage_m = 1.1, pref_w = 0.5, pref_m = 0.45,
        ),
    ]
    variants = ((3, :parallel), (3, :serial), (3, :auto))
    for search in (:local, :discovery)
        @testset "$search" begin
            cohort = threading_cohort(GN.NoNetwork(), :connected, 8, 7, regimes, length(variants) + 1)
            reference, runs = threading_theta_variants(cohort, config, variants; search = search)
            for (women_snap, men_snap) in vcat([reference], runs)
                # Households 1 and 2 (zero wages, non-finite outside
                # options) and households 3 and 4 (symmetric, the
                # status quo beats every candidate) take the status
                # fallback and commit their `theta0` verbatim.
                @test women_snap[1][3] === -0.0
                @test women_snap[2][3] === 0.0
                @test women_snap[3][3] === -0.0
                @test women_snap[4][3] === 0.0
                @test men_snap[1][3] === -0.0
                @test men_snap[2][3] === 0.0
                @test men_snap[3][3] === -0.0
                @test men_snap[4][3] === 0.0
            end
            for run in runs
                @test threading_bits(run[1]) == threading_bits(reference[1])
                @test threading_bits(run[2]) == threading_bits(reference[2])
            end
        end
    end
end

@testset "set_theta! :auto matches the oracle above the serial crossover" begin
    # The `:auto` schedule selects the parallel path above
    # `HOUSEHOLD_BARGAIN_SERIAL_CUTOFF` households on multithreaded
    # runs and the serial path otherwise; the population is derived
    # from the constant (its value is provisional and not pinned) so
    # the parallel branch runs at `JULIA_NUM_THREADS = 8` whatever the
    # crossover is tuned to (TASK-0025 item 2).
    config = GN.UtilityConfig()
    n = GN.HOUSEHOLD_BARGAIN_SERIAL_CUTOFF + 1
    regimes = threading_regimes(Random.MersenneTwister(8), n)
    variants = ((4, :auto), (1, :auto))
    for search in (:local, :discovery)
        @testset "$search" begin
            cohort = threading_cohort(GN.NoNetwork(), :connected, n, 7, regimes, length(variants) + 1)
            reference, runs = threading_theta_variants(cohort, config, variants; search = search)
            for run in runs
                @test threading_bits(run[1]) == threading_bits(reference[1])
                @test threading_bits(run[2]) == threading_bits(reference[2])
            end
        end
    end
end

@testset "set_theta! validates chunk and schedule before touching the world" begin
    config = GN.UtilityConfig()
    @test_throws ArgumentError GN.set_theta!(Ark.World(), config; chunk = 0)
    @test_throws ArgumentError GN.set_theta!(Ark.World(), config; chunk = -1)
    @test_throws ArgumentError GN.set_theta!(Ark.World(), config; chunk = -3, schedule = :parallel)
    @test_throws ArgumentError GN.set_theta!(Ark.World(), config; schedule = :bogus)
    @test_throws ArgumentError GN.set_theta!(Ark.World(), config; search = :unknown)
    # All validation precedes every write and every worker task: a
    # populated world is bit-untouched by the failing calls
    # (TASK-0025 item 12).
    regimes = threading_regimes(Random.MersenneTwister(8), 4)
    world, women, men = threading_cohort(GN.NoNetwork(), :connected, 4, 7, regimes, 1)[1]
    before = (
        threading_bits(threading_snapshot(world, women)),
        threading_bits(threading_snapshot(world, men)),
    )
    @test_throws ArgumentError GN.set_theta!(world, config; chunk = 0, schedule = :parallel)
    @test_throws ArgumentError GN.set_theta!(world, config; chunk = -1, schedule = :parallel)
    @test_throws ArgumentError GN.set_theta!(world, config; chunk = 4, schedule = :bogus)
    @test_throws ArgumentError GN.set_theta!(world, config; search = :unknown, schedule = :parallel)
    after = (
        threading_bits(threading_snapshot(world, women)),
        threading_bits(threading_snapshot(world, men)),
    )
    @test after == before
end

@testset "set_theta! worker failures join every worker before rethrowing" begin
    # Regression for the completion barrier of `ADR-0023`: the failing
    # household sits in the LAST chunk of the loop, so every schedule
    # and chunking commits the same households exactly once before the
    # vertex-lookup guard throws (a household reads only the pre-call
    # `old` fields of its neighbours, so committed state is order
    # independent) and the `@sync` join guarantees that no worker task
    # writes anything once the failure has surfaced. Forced `:parallel`
    # at one chunk covers `nworkers = 1` at any thread count, forced
    # `:parallel` at `chunk = 1` and `4` runs several workers at eight
    # threads with the failing household outside the first chunk, and
    # the whole file also runs at one thread.
    config = GN.UtilityConfig()
    n = 25
    regimes = threading_regimes(Random.MersenneTwister(8), n)
    variants = (
        (1, :parallel),   # 25 chunks: several workers, failing chunk last
        (4, :parallel),   # trailing partial chunk, several workers
        (32, :parallel),  # one chunk: nworkers = 1 at any thread count
        (1, :serial),     # bare guard error, no tasks
        (1, :auto),       # auto-selected path at any thread count
    )
    for search in (:local, :discovery)
        @testset "$search" begin
            # Serial oracle twin: the bare `ArgumentError` of the guard
            # and the deterministic post-failure state that every
            # schedule must reproduce bit for bit.
            world_o, women_o, men_o = threading_cohort(GN.NoNetwork(), :connected, n, 7, regimes, 1)[1]
            ghost_o = threading_unindexed_spouse!(world_o, women_o, men_o)
            entities_o = vcat(women_o, men_o, [ghost_o])
            err_o = threading_captured(() -> serial_set_theta!(world_o, config; search = search))
            @test err_o isa ArgumentError
            @test err_o isa ArgumentError &&
                occursin("man is not in the men entity vector", err_o.msg)
            state_o = threading_state_bits(world_o, entities_o)
            sleep(0.05)
            @test threading_state_bits(world_o, entities_o) == state_o
            # Recovery oracle: the deterministic failed state plus one
            # full `set_theta!` application on the repaired world.
            Ark.set_components!(world_o, women_o[end], (GN.Spouse(men_o[end]),))
            @test serial_set_theta!(world_o, config; search = search) === nothing
            recovery_o = threading_state_bits(world_o, entities_o)

            for (chunk, schedule) in variants
                @testset "chunk = $chunk, $schedule" begin
                    world, women, men = threading_cohort(GN.NoNetwork(), :connected, n, 7, regimes, 1)[1]
                    ghost = threading_unindexed_spouse!(world, women, men)
                    entities = vcat(women, men, [ghost])
                    err = threading_captured(
                        () -> GN.set_theta!(
                            world, config; search = search, chunk = chunk, schedule = schedule
                        )
                    )
                    # The call throws and the root cause of the chain is
                    # the guard `ArgumentError`; no other failure kind
                    # appears anywhere in it.
                    @test err !== nothing
                    leaves = threading_leaf_exceptions(err)
                    @test all(e -> e isa ArgumentError, leaves)
                    @test any(
                        e -> e isa ArgumentError &&
                            occursin("man is not in the men entity vector", e.msg),
                        leaves,
                    )
                    if schedule === :serial
                        # The serial path throws the bare guard error.
                        @test err isa ArgumentError
                    elseif schedule === :parallel
                        # Observed wrapping under Julia 1.12: one
                        # `TaskFailedException` inside a
                        # `CompositeException`; pin the documented
                        # envelope and the root cause, not the exact
                        # container type.
                        @test err isa CompositeException || err isa TaskFailedException
                    else
                        # `:auto` wraps only when it selects the
                        # parallel path (thread count and crossover
                        # dependent), so accept both shapes here.
                        @test err isa ArgumentError ||
                            err isa CompositeException ||
                            err isa TaskFailedException
                    end
                    # Every worker joined before the throw: the
                    # post-failure state equals the serial oracle's and
                    # nothing writes afterwards.
                    state = threading_state_bits(world, entities)
                    @test state == state_o
                    sleep(0.05)
                    @test threading_state_bits(world, entities) == state
                    # No lingering workers: a second `set_theta!` call
                    # on the repaired world reaches exactly the oracle
                    # recovery state.
                    Ark.set_components!(world, women[end], (GN.Spouse(men[end]),))
                    @test GN.set_theta!(
                        world, config; search = search, chunk = chunk, schedule = schedule
                    ) === nothing
                    @test threading_state_bits(world, entities) == recovery_o
                end
            end
        end
    end
end

@testset "set_theta! matches the oracle across multiple female query groups" begin
    # `Ark.Query(world, component_types; with=(Female,))` iterates one
    # batch per matching archetype, so the serial and the parallel
    # region of `set_theta!` run once per batch per call; the per-batch
    # scratch, worker-task, and closure setup of `ADR-0023` must
    # survive repeated query-loop iterations. Removing the unused
    # `Lambda` component from every second woman splits the women into
    # two archetypes and forces two (or more) batches per call (checked
    # on the fixture below); the committed world state must stay
    # bitwise identical to the serial oracle for every forced schedule
    # and chunk size.
    config = GN.UtilityConfig()
    n = 21
    regimes = threading_regimes(Random.MersenneTwister(8), n)
    variants = (
        (1, :parallel),
        (4, :parallel),
        (1, :serial),
        (4, :serial),
        (1, :auto),
        (4, :auto),
    )
    for search in (:local, :discovery)
        @testset "$search" begin
            cohort = threading_cohort(GN.NoNetwork(), :connected, n, 7, regimes, length(variants) + 1)
            for (world, women, _) in cohort
                for index in 2:2:length(women)
                    Ark.remove_components!(world, women[index], (GN.Lambda,))
                end
            end
            # Fixture sanity: the query really iterates more than one
            # batch, and every woman is still in exactly one of them.
            world_a, _, _ = cohort[1]
            groups = collect(
                Ark.Query(
                    world_a,
                    (GN.Wage, GN.WorkingTime, GN.TransferToWoman, GN.Conformism, GN.PreferencePrivate, GN.Spouse, GN.CommittedUtility);
                    with = (GN.Female,),
                )
            )
            @test length(groups) >= 2
            @test sum(batch -> length(first(batch)), groups) == n
            reference, runs = threading_theta_variants(cohort, config, variants; search = search)
            for run in runs
                @test threading_bits(run[1]) == threading_bits(reference[1])
                @test threading_bits(run[2]) == threading_bits(reference[2])
            end
        end
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
    # The same-seed repeat block of the driver is byte-identical to the
    # run block, and the forced-schedule segments (`:serial`,
    # `:parallel`, `:auto` at `chunk = 3`, an incomplete final chunk
    # included) are byte-identical to each other within one invocation,
    # and thereby across the `-t 1` and `-t 4` invocations above
    # (TASK-0025 item 11). The run and repeat blocks also print one
    # deterministic final-state row per agent in the segment row
    # format, so the byte-identity covers individual agents and not
    # only aggregate means.
    run_lines = filter(
        line -> !isempty(line) && !startswith(line, "repeat ") && !startswith(line, "segment "),
        split(out1, '\n'),
    )
    @test length(run_lines) > 15
    @test threading_driver_block(out1, "repeat ") == run_lines
    @test count(line -> startswith(line, "agent "), run_lines) == 128
    serial_rows = threading_driver_block(out1, "segment serial ")
    @test length(serial_rows) == 128
    @test threading_driver_block(out1, "segment parallel ") == serial_rows
    @test threading_driver_block(out1, "segment auto ") == serial_rows
end
