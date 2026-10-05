# Tests for the committed-bundle utility observation (`CommittedUtility`,
# see `MDR-0019` and `ADR-0026`): `set_theta!` stores
# `individual_utility` at the committed bundle `(theta, hw, hm)` and the
# tick's prepared payoff parameters for both partners (NetLogo
# `current-utility` diagnostic intent, ODD sections Entities, state
# variables, and scales and Labour best response; the reference's
# mutable `choose-bundle` scratch semantics are deliberately not
# reproduced). Each capture testset snapshots the households'
# pre-bargaining parameters, runs `set_theta!`, and compares the stored
# values bitwise to `individual_utility` at the actual committed bundle,
# across connected, isolated, and homogeneous-mixing norms, status-quo
# retention, the non-finite fallback, both transfer signs, and every
# supported utility spec.

using Ark
using GenderNorms
using Graphs
using Random
using Test

const GN = GenderNorms

# Bit-level Float64 equality: `0.0` and `-0.0` (and distinct NaNs)
# compare distinguishably.
same_bits(a::Float64, b::Float64) = reinterpret(UInt64, a) == reinterpret(UInt64, b)

function make_capture_world(network::GN.NetworkSpec, n::Int, seed::Int)
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

# Apply one deterministic household `regime` (a NamedTuple covering
# every state `set_theta!` reads) to one household.
function apply_capture_regime!(world, woman, man, regime)
    for (entity, h, h_old, wage, pref, conf) in (
            (woman, regime.h_w, regime.h_w_old, regime.wage_w, regime.pref_w, regime.c_w),
            (man, regime.h_m, regime.h_m_old, regime.wage_m, regime.pref_m, regime.c_m),
        )
        Ark.set_components!(
            world,
            entity,
            (
                GN.WorkingTime(h, h_old),
                GN.TransferToWoman(regime.theta, regime.theta_old),
                GN.Conformism(conf),
                GN.Wage(wage, wage),
                GN.PreferencePrivate(pref, pref),
            ),
        )
    end
    return nothing
end

# Rebuild one household's prepared payoff parameters exactly as
# `set_theta!` builds them (`payoff_params` over `norm_means` of the
# lagged state, which bargaining does not touch), so the stored values
# can be checked bitwise against `individual_utility` at the committed
# bundle. Returns `(pw, pm)`.
function household_params(world, net, woman, man, globals)
    spouse_seen = Ark.Entity[]
    woman_vertex = findfirst(==(woman), net.women_entities)
    man_vertex = findfirst(==(man), net.men_entities)
    woman_norms = GN.norm_means(world, net, woman_vertex, true, globals, spouse_seen)
    man_norms = GN.norm_means(world, net, man_vertex, false, globals, spouse_seen)
    woman_wage, woman_pref, woman_conf =
        Ark.get_components(world, woman, (GN.Wage, GN.PreferencePrivate, GN.Conformism))
    man_wage, man_pref, man_conf =
        Ark.get_components(world, man, (GN.Wage, GN.PreferencePrivate, GN.Conformism))
    pw = GN.payoff_params(
        woman_wage.current, man_wage.current, woman_pref.current, woman_conf.amount,
        woman_norms, true,
    )
    pm = GN.payoff_params(
        man_wage.current, woman_wage.current, man_pref.current, man_conf.amount,
        man_norms, false,
    )
    return pw, pm
end

# Run one capture scenario: build the world, apply `regimes`, install
# the scenario `graphs`, snapshot every household's pre-bargaining
# parameters, run `set_theta!`, and assert for every household that the
# stored `CommittedUtility` values are bitwise `individual_utility` at
# the committed bundle. Returns the committed `(theta, hw, hm)` tuples
# in household order for scenario-specific assertions.
function run_capture_scenario(
        network::GN.NetworkSpec, graphs, n::Int, seed::Int, regimes, config::GN.UtilityConfig
    )
    world, women, men = make_capture_world(network, n, seed)
    for (woman, man, regime) in zip(women, men, regimes)
        apply_capture_regime!(world, woman, man, regime)
    end
    women_graph, men_graph = graphs(n)
    Ark.add_resource!(world, GN.SocialNetwork(men_graph, women_graph, men, women))
    net = Ark.get_resource(world, GN.SocialNetwork)
    globals = network isa GN.HomogeneousMixing ? GN.norm_global_means(world, net) : nothing
    params = map(zip(women, men)) do (woman, man)
        household_params(world, net, woman, man, globals)
    end

    @test GN.set_theta!(world, config) === nothing

    committed = map(zip(women, men, params)) do (woman, man, pair)
        pw, pm = pair
        time_w, transfer_w, utility_w =
            Ark.get_components(world, woman, (GN.WorkingTime, GN.TransferToWoman, GN.CommittedUtility))
        time_m, transfer_m, utility_m =
            Ark.get_components(world, man, (GN.WorkingTime, GN.TransferToWoman, GN.CommittedUtility))
        theta = transfer_w.current
        hw = time_w.current
        hm = time_m.current
        @test isequal(transfer_m.current, theta)
        @test same_bits(
            utility_w.value, GN.individual_utility(hw, hm, theta, pw, config)
        )
        @test same_bits(
            utility_m.value, GN.individual_utility(hm, hw, theta, pm, config)
        )
        return (theta, hw, hm)
    end
    return collect(committed)
end

# Empty-graph pair factory for the isolated and homogeneous-mixing
# scenarios.
empty_graphs(n::Int) = (Graphs.SimpleGraph(n), Graphs.SimpleGraph(n))

# Connected ring-plus-chords graphs (the neighbour branch of
# `norm_means`).
function connected_graphs(n::Int)
    women_graph = Graphs.SimpleGraph(n)
    men_graph = Graphs.SimpleGraph(n)
    for i in 1:n
        Graphs.add_edge!(women_graph, i, mod1(i + 1, n))
        Graphs.add_edge!(women_graph, i, mod1(i + 2, n))
        Graphs.add_edge!(men_graph, i, mod1(i + 1, n))
    end
    return women_graph, men_graph
end

function regime(;
        h_w = 0.4, h_w_old = 0.45, h_m = 0.6, h_m_old = 0.55,
        theta = 0.0, theta_old = 0.0,
        c_w = 2.0, c_m = 1.5,
        wage_w = 0.9, wage_m = 1.1,
        pref_w = 0.5, pref_m = 0.5,
    )
    return (;
        h_w, h_w_old, h_m, h_m_old, theta, theta_old, c_w, c_m, wage_w, wage_m, pref_w, pref_m,
    )
end

# Build one `UtilityConfig` through the model configuration parser, so
# the utility-spec matrix below covers exactly the specs a run
# specification can select (the `model.utility` table, `ADR-0012`).
function utility_config(utility_raw::Dict{String, Any})
    raw = Dict{String, Any}("utility" => utility_raw)
    return GN.parse_model_config(GN.GenderNormsModel, raw).utility
end

@testset "committed utilities match individual_utility at the committed bundle" begin
    config = GN.UtilityConfig()
    mixed = [
        regime(),
        regime(h_w = 0.2, h_m = 0.9, theta = 0.3, theta_old = -0.2, wage_w = 0.6, wage_m = 1.4),
        regime(h_w = 0.8, h_m = 0.3, theta = -0.5, theta_old = 0.4, c_w = 5.0, c_m = 0.0),
        regime(h_w = 1.0, h_m = 0.0, theta = 1.0, theta_old = 1.0, wage_w = 1.5, wage_m = 0.5),
    ]

    @testset "connected norms" begin
        run_capture_scenario(GN.NoNetwork(), connected_graphs, 4, 21, mixed, config)
    end
    @testset "isolated fallback norms" begin
        run_capture_scenario(GN.NoNetwork(), empty_graphs, 4, 22, mixed, config)
    end
    @testset "homogeneous-mixing global norms" begin
        run_capture_scenario(GN.HomogeneousMixing(), empty_graphs, 4, 23, mixed, config)
    end
end

@testset "committed utilities match individual_utility for every supported utility spec" begin
    configs = [
        "additive" => utility_config(Dict{String, Any}("type" => "additive")),
        "multiplicative" => utility_config(Dict{String, Any}("type" => "multiplicative")),
        "multiplicative_weighted" => utility_config(
            Dict{String, Any}(
                "type" => "multiplicative_weighted",
                "w_self" => 1.3,
                "w_partner" => 0.7,
                "w_transfer" => 0.4,
            )
        ),
        "ces with non-default beta" => utility_config(
            Dict{String, Any}(
                "type" => "ces",
                "beta" => 0.8,
                "w_self" => 0.8,
                "w_partner" => 1.2,
                "w_transfer" => 1.1,
            )
        ),
    ]
    # One household per config with an interior positive transfer: both
    # partner roles commit (recipient and payer, including the preserved
    # `MultiplicativeWeighted` payer branch) and are captured bitwise.
    interior = [
        regime(
            h_w = 0.5, h_w_old = 0.5, h_m = 0.5, h_m_old = 0.5, c_w = 0.0, c_m = 0.0,
            wage_w = 0.6, wage_m = 1.2
        ),
    ]
    for (i, (label, config)) in enumerate(configs)
        @testset "$label" begin
            run_capture_scenario(GN.NoNetwork(), empty_graphs, 1, 30 + i, interior, config)
        end
    end
end

@testset "status-quo retention keeps a zero transfer and records its utilities" begin
    config = GN.UtilityConfig()
    # The symmetric household has zero bargaining gains at theta = 0:
    # every candidate transfer makes the payer worse off than the
    # outside option, so the status quo is retained exactly.
    symmetric = [
        regime(
            h_w = 0.5, h_w_old = 0.5, h_m = 0.5, h_m_old = 0.5, c_w = 0.0, c_m = 0.0,
            wage_w = 1.0, wage_m = 1.0
        ),
    ]
    committed = run_capture_scenario(GN.NoNetwork(), empty_graphs, 1, 24, symmetric, config)
    theta, hw, hm = committed[1]
    @test isequal(theta, 0.0)
    @test 0.0 <= hw <= 1.0
    @test 0.0 <= hm <= 1.0
end

@testset "non-finite fallback propagates non-finite utilities bitwise" begin
    config = GN.UtilityConfig()
    regimes = [
        # zero wage: the woman's outside option is -Inf, so
        # `bargain_transfer` takes its non-finite fallback; her
        # committed utility is exactly -Inf (propagated, not clamped)
        regime(wage_w = 0.0, wage_m = 1.1, c_w = 0.0, c_m = 0.0),
        # NaN wage: the stored value is exactly the NaN of
        # `individual_utility` at the returned bundle
        regime(wage_w = NaN, wage_m = 1.1, c_w = 0.0, c_m = 0.0),
    ]
    world, women, men = make_capture_world(GN.NoNetwork(), 2, 25)
    for (woman, man, r) in zip(women, men, regimes)
        apply_capture_regime!(world, woman, man, r)
    end
    women_graph, men_graph = empty_graphs(2)
    Ark.add_resource!(world, GN.SocialNetwork(men_graph, women_graph, men, women))
    net = Ark.get_resource(world, GN.SocialNetwork)
    params = [household_params(world, net, w, m, nothing) for (w, m) in zip(women, men)]

    @test GN.set_theta!(world, config) === nothing

    time_w1, transfer_w1, utility_w1 =
        Ark.get_components(world, women[1], (GN.WorkingTime, GN.TransferToWoman, GN.CommittedUtility))
    time_m1, _, utility_m1 =
        Ark.get_components(world, men[1], (GN.WorkingTime, GN.TransferToWoman, GN.CommittedUtility))
    pw1, pm1 = params[1]
    @test isinf(utility_w1.value) && utility_w1.value < 0
    @test same_bits(
        utility_w1.value, GN.individual_utility(
            time_w1.current, time_m1.current, transfer_w1.current, pw1, config
        )
    )
    @test same_bits(
        utility_m1.value, GN.individual_utility(
            time_m1.current, time_w1.current, transfer_w1.current, pm1, config
        )
    )

    time_w2, transfer_w2, utility_w2 =
        Ark.get_components(world, women[2], (GN.WorkingTime, GN.TransferToWoman, GN.CommittedUtility))
    time_m2, _, utility_m2 =
        Ark.get_components(world, men[2], (GN.WorkingTime, GN.TransferToWoman, GN.CommittedUtility))
    pw2, pm2 = params[2]
    @test isnan(utility_w2.value)
    @test same_bits(
        utility_w2.value, GN.individual_utility(
            time_w2.current, time_m2.current, transfer_w2.current, pw2, config
        )
    )
    @test same_bits(
        utility_m2.value, GN.individual_utility(
            time_m2.current, time_w2.current, transfer_w2.current, pm2, config
        )
    )
end

@testset "transfer-sign households record both signed commits" begin
    config = GN.UtilityConfig()
    # Zero-conformism wage gaps drive interior transfers of both signs
    # from a zero status quo (`set-theta` with `calculate-payoff`).
    regimes = [
        regime(
            h_w = 0.5, h_w_old = 0.5, h_m = 0.5, h_m_old = 0.5, c_w = 0.0, c_m = 0.0,
            wage_w = 0.6, wage_m = 1.2
        ),
        regime(
            h_w = 0.5, h_w_old = 0.5, h_m = 0.5, h_m_old = 0.5, c_w = 0.0, c_m = 0.0,
            wage_w = 1.2, wage_m = 0.6
        ),
    ]
    committed = run_capture_scenario(GN.NoNetwork(), empty_graphs, 2, 26, regimes, config)
    theta_toward_woman = committed[1][1]
    theta_toward_man = committed[2][1]
    @test theta_toward_woman > 0.0
    @test theta_toward_man < 0.0
end

@testset "setup registers NaN committed utilities on every agent" begin
    # Full-model worlds carry `CommittedUtility` on every agent before
    # the first step: a missing component must never act as an intended
    # population filter in the observer reductions (MDR-0019).
    config = GN.parse_model_config(
        GN.GenderNormsModel,
        Dict{String, Any}(
            "agents_per_gender" => 5,
            "network" => Dict{String, Any}("type" => "watts_strogatz"),
        ),
    )
    world = GN.setup_world(GN.GenderNormsModel, config, Random.MersenneTwister(27))
    agents = vcat(GN.entities_with(world, GN.Female), GN.entities_with(world, GN.Male))
    @test length(agents) == 10
    observed = 0
    for entity in agents
        utility, = Ark.get_components(world, entity, (GN.CommittedUtility,))
        @test isnan(utility.value)
        observed += 1
    end
    matched = 0
    for (entities,) in Ark.Query(world, (GN.CommittedUtility,))
        matched += length(entities)
    end
    @test matched == observed == length(agents)
end

@testset "concrete individual_utility evaluation allocates nothing" begin
    config = GN.UtilityConfig()
    params = GN.AgentPayoffParams(
        wage_self = 0.9, wage_spouse = 1.1, alpha = 0.5, conformism = 2.0,
        N_h = 0.36, N_theta = 0.1, N_h_spouse = 0.77, is_woman = true,
    )
    utility_allocs(p::GN.AgentPayoffParams, c::GN.UtilityConfig) =
        @allocated GN.individual_utility(0.4, 0.6, 0.2, p, c)
    GN.individual_utility(0.4, 0.6, 0.2, params, config)
    @test utility_allocs(params, config) == 0
end
