# Tests for the GenderNorms model binding in
# `src/runtime/gender_norms_model.jl` (see `ADR-0012` and `MDR-0010`).
# Covers `parse_model_config` defaults, full mappings, round-trips,
# and aggregated validation failures, plus `setup_world` pairing and a
# small `run` smoke test through the binding.

function model_message(raw)
    return try
        GN.parse_model_config(GN.GenderNormsModel, raw)
        error("expected RunSpecError")
    catch e
        e isa GN.RunSpecError || rethrow()
        sprint(showerror, e)
    end
end

function model_problems(raw)
    return try
        GN.parse_model_config(GN.GenderNormsModel, raw)
        error("expected RunSpecError")
    catch e
        e isa GN.RunSpecError || rethrow()
        e.problems
    end
end

function tiny_model_config(; agents = 4)
    raw = Dict{String,Any}(
        "agents_per_gender" => agents,
        "network" => Dict{String,Any}("type" => "none"),
    )
    return GN.parse_model_config(GN.GenderNormsModel, raw)
end

function full_model_raw()
    return Dict{String,Any}(
        "agents_per_gender" => 10,
        "std_dev" => 0.1,
        "initial_transfer" => 0.2,
        "initial_lambda" => 0.3,
        "network" => Dict{String,Any}(
            "type" => "watts_strogatz", "neighbors_per_side" => 2, "rewiring" => 0.2
        ),
        "paid_time" => Dict{String,Any}("men" => 0.8, "women" => 0.4),
        "mean_wage" => Dict{String,Any}("men" => 1.1, "women" => 1.0),
        "mean_preference" => Dict{String,Any}("men" => 0.5, "women" => 0.6),
        "initial_conformism" => Dict{String,Any}("men" => 5.0, "women" => 6.0),
        "utility" => Dict{String,Any}(
            "type" => "ces",
            "beta" => 0.7,
            "w_self" => 2.0,
            "w_partner" => 0.5,
            "w_transfer" => 1.5,
        ),
    )
end

@testset "empty dict yields the struct defaults" begin
    cfg = GN.parse_model_config(GN.GenderNormsModel, Dict{String,Any}())
    @test cfg.properties.agents_per_gender == 400
    @test cfg.properties.std_dev == 0.2
    @test cfg.properties.initial_transfer == 0.0
    @test cfg.properties.initial_lambda == 0.5
    @test cfg.properties.network isa GN.WattsStrogatz
    @test cfg.properties.network.neighbors_per_side == 1
    @test cfg.properties.network.rewiring == 0.1
    @test cfg.paid_time.men == 0.77
    @test cfg.paid_time.woman == 0.36
    @test cfg.mean_wage.men == 1.0
    @test cfg.mean_wage.woman == 0.9
    @test cfg.mean_preference.men == 0.45
    @test cfg.mean_preference.woman == 0.48
    @test cfg.initial_conformism.men == 10.0
    @test cfg.initial_conformism.woman == 10.0
    @test cfg.utility.func isa GN.CES
    @test cfg.utility.func.beta == 0.5
    @test cfg.utility.w_self == 1.0
    @test cfg.utility.w_partner == 1.0
    @test cfg.utility.w_transfer == 1.0
end

@testset "full valid dict maps to typed values" begin
    cfg = GN.parse_model_config(GN.GenderNormsModel, full_model_raw())
    @test cfg.properties.agents_per_gender == 10
    @test cfg.properties.std_dev == 0.1
    @test cfg.properties.initial_transfer == 0.2
    @test cfg.properties.initial_lambda == 0.3
    @test cfg.properties.network == GN.WattsStrogatz(neighbors_per_side = 2, rewiring = 0.2)
    @test (cfg.paid_time.men, cfg.paid_time.woman) == (0.8, 0.4)
    @test (cfg.mean_wage.men, cfg.mean_wage.woman) == (1.1, 1.0)
    @test (cfg.mean_preference.men, cfg.mean_preference.woman) == (0.5, 0.6)
    @test (cfg.initial_conformism.men, cfg.initial_conformism.woman) == (5.0, 6.0)
    @test cfg.utility.func == GN.CES(beta = 0.7)
    @test (cfg.utility.w_self, cfg.utility.w_partner, cfg.utility.w_transfer) == (2.0, 0.5, 1.5)
end

@testset "every network type parses" begin
    cases = (
        (Dict{String,Any}("type" => "random", "p" => 0.05), GN.RandomNetwork(p = 0.05)),
        (
            Dict{String,Any}(
                "type" => "watts_strogatz", "neighbors_per_side" => 2, "rewiring" => 0.3
            ),
            GN.WattsStrogatz(neighbors_per_side = 2, rewiring = 0.3),
        ),
        (
            Dict{String,Any}("type" => "preferential_attachment", "m" => 2),
            GN.PreferentialAttachment(m = 2),
        ),
        (
            Dict{String,Any}("type" => "similarity", "m" => 2, "trait" => "wage"),
            GN.SimilarityNetwork(m = 2, trait = :wage),
        ),
        (
            Dict{String,Any}("type" => "similarity", "m" => 3, "trait" => "conformism"),
            GN.SimilarityNetwork(m = 3, trait = :conformism),
        ),
        (
            Dict{String,Any}("type" => "similarity", "trait" => "preference_private"),
            GN.SimilarityNetwork(m = 1, trait = :preference_private),
        ),
        (Dict{String,Any}("type" => "homophily", "m" => 2), GN.HomophilyNetwork(m = 2)),
        (Dict{String,Any}("type" => "none"), GN.NoNetwork()),
        (Dict{String,Any}("type" => "homogeneous_mixing"), GN.HomogeneousMixing()),
    )
    for (network_raw, expected) in cases
        raw = Dict{String,Any}("network" => network_raw)
        cfg = GN.parse_model_config(GN.GenderNormsModel, raw)
        @test cfg.properties.network == expected
    end
end

@testset "every utility type parses" begin
    additive = GN.parse_model_config(
        GN.GenderNormsModel, Dict{String,Any}("utility" => Dict{String,Any}("type" => "additive"))
    )
    @test additive.utility.func isa GN.Additive
    @test (additive.utility.w_self, additive.utility.w_partner, additive.utility.w_transfer) ==
          (1.0, 1.0, 1.0)
    ces_default = GN.parse_model_config(
        GN.GenderNormsModel, Dict{String,Any}("utility" => Dict{String,Any}("type" => "ces"))
    )
    @test ces_default.utility.func == GN.CES(beta = 0.5)
    multiplicative = GN.parse_model_config(
        GN.GenderNormsModel,
        Dict{String,Any}("utility" => Dict{String,Any}("type" => "multiplicative")),
    )
    @test multiplicative.utility.func isa GN.Multiplicative
    weighted = GN.parse_model_config(
        GN.GenderNormsModel,
        Dict{String,Any}(
            "utility" => Dict{String,Any}("type" => "multiplicative_weighted", "w_self" => 2.0)
        ),
    )
    @test weighted.utility.func isa GN.MultiplicativeWeighted
    @test weighted.utility.w_self == 2.0
end

@testset "config round-trips through config_to_dict" begin
    cfg = GN.parse_model_config(GN.GenderNormsModel, full_model_raw())
    echoed = GN.config_to_dict(GN.GenderNormsModel, cfg)
    @test GN.config_to_dict(GN.GenderNormsModel, GN.parse_model_config(GN.GenderNormsModel, echoed)) ==
          echoed
    defaults = GN.parse_model_config(GN.GenderNormsModel, Dict{String,Any}())
    default_echoed = GN.config_to_dict(GN.GenderNormsModel, defaults)
    @test GN.config_to_dict(
        GN.GenderNormsModel, GN.parse_model_config(GN.GenderNormsModel, default_echoed)
    ) == default_echoed
end

@testset "unknown top-level key is rejected" begin
    @test occursin("[model", model_message(Dict{String,Any}("bogus" => 1)))
end

@testset "bad agents_per_gender is rejected" begin
    @test occursin("[model", model_message(Dict{String,Any}("agents_per_gender" => 0)))
    @test occursin("[model", model_message(Dict{String,Any}("agents_per_gender" => "ten")))
    @test occursin("[model", model_message(Dict{String,Any}("agents_per_gender" => true)))
end

@testset "out-of-range scalars are rejected" begin
    @test occursin("[model", model_message(Dict{String,Any}("std_dev" => -0.1)))
    @test occursin("[model", model_message(Dict{String,Any}("initial_transfer" => 2)))
    @test occursin("[model", model_message(Dict{String,Any}("initial_lambda" => -0.1)))
end

@testset "non-finite scalars are rejected" begin
    @test occursin("[model.std_dev]", model_message(Dict{String,Any}("std_dev" => Inf)))
    @test occursin("[model.std_dev]", model_message(Dict{String,Any}("std_dev" => NaN)))
    message = model_message(
        Dict{String,Any}("utility" => Dict{String,Any}("type" => "ces", "beta" => Inf)),
    )
    @test occursin("[model.utility.beta]", message)
end

@testset "unknown network type is rejected" begin
    raw = Dict{String,Any}("network" => Dict{String,Any}("type" => "small_world"))
    message = model_message(raw)
    @test occursin("[model", message)
    @test occursin("small_world", message)
    @test occursin("watts_strogatz", message)
end

@testset "network key outside its type is rejected" begin
    raw = Dict{String,Any}(
        "network" => Dict{String,Any}("type" => "watts_strogatz", "p" => 0.1)
    )
    message = model_message(raw)
    @test occursin("[model", message)
    @test occursin("p", message)
end

@testset "bad similarity trait is rejected" begin
    raw = Dict{String,Any}(
        "network" => Dict{String,Any}("type" => "similarity", "trait" => "income")
    )
    message = model_message(raw)
    @test occursin("[model", message)
    @test occursin("income", message)
end

@testset "beta outside ces is rejected" begin
    raw = Dict{String,Any}(
        "utility" => Dict{String,Any}("type" => "additive", "beta" => 0.5)
    )
    message = model_message(raw)
    @test occursin("[model", message)
    @test occursin("beta", message)
end

@testset "bad utility type is rejected" begin
    raw = Dict{String,Any}("utility" => Dict{String,Any}("type" => "quadratic"))
    message = model_message(raw)
    @test occursin("[model", message)
    @test occursin("quadratic", message)
end

@testset "non-numeric paid_time entry is rejected" begin
    raw = Dict{String,Any}("paid_time" => Dict{String,Any}("women" => "high"))
    message = model_message(raw)
    @test occursin("[model", message)
    @test occursin("women", message)
end

@testset "multiple problems aggregate into one error" begin
    problems = model_problems(Dict{String,Any}("bogus" => 1, "agents_per_gender" => 0))
    @test length(problems) >= 2
    message = model_message(Dict{String,Any}("bogus" => 1, "agents_per_gender" => 0))
    @test occursin("[model", message)
    @test occursin("bogus", message)
    @test occursin("agents_per_gender", message)
end

@testset "setup_world builds paired households without a network" begin
    cfg = tiny_model_config()
    world = GN.setup_world(GN.GenderNormsModel, cfg, Random.MersenneTwister(1))
    for resource in (
        GN.ModelProperties,
        GN.PaidTime,
        GN.MeanWage,
        GN.MeanPreference,
        GN.InitialConformism,
        GN.WorkingTimeStats,
        GN.SocialNetwork,
    )
        @test Ark.has_resource(world, resource)
    end
    women = GN.entities_with(world, GN.Female)
    men = GN.entities_with(world, GN.Male)
    @test length(women) == cfg.properties.agents_per_gender
    @test length(men) == cfg.properties.agents_per_gender
    men_set = Set(men)
    women_set = Set(women)
    for woman in women
        spouse, = Ark.get_components(world, woman, (GN.Spouse,))
        @test spouse.entity in men_set
    end
    for man in men
        spouse, = Ark.get_components(world, man, (GN.Spouse,))
        @test spouse.entity in women_set
    end
    @test Ark.get_resource(world, GN.SocialNetwork) isa GN.SocialNetwork
end

@testset "run executes two ticks with finite metric series" begin
    raw = Dict{String,Any}(
        "run" => Dict{String,Any}("name" => "tiny", "seed" => 1),
        "model" => Dict{String,Any}(
            "name" => "gender_norms",
            "agents_per_gender" => 4,
            "network" => Dict{String,Any}("type" => "none"),
        ),
        "runtime" => Dict{String,Any}("ticks" => 2),
    )
    spec = GN.parse_spec(raw)
    result = GN.run(GN.create_world(spec))
    @test GN.is_success(result)
    @test result.ticks_executed == 2
    for name in ("working_time_men", "working_time_women", "working_time_gap")
        @test haskey(result.metrics, name)
        @test length(result.metrics[name]) == 2
        @test all(isfinite, result.metrics[name])
    end
end
