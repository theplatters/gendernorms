# Executable invariants of accepted decisions under
# `registry/code/decisions/`. Each testset cites the record it keeps
# honest; when a decision changes, this file changes with it (see
# `ADR-0008`).

using Ark
using GenderNorms
using Test

const GN = GenderNorms

@testset "ADR-0010: ModelProperties is a non-parametric resource" begin
    networks = (
        GN.RandomNetwork(),
        GN.WattsStrogatz(),
        GN.PreferentialAttachment(),
        GN.SimilarityNetwork(),
        GN.HomophilyNetwork(),
        GN.NoNetwork(),
        GN.HomogeneousMixing(),
    )
    for spec in networks
        @test typeof(GN.ModelProperties(network = spec)) === GN.ModelProperties
    end
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
    properties = GN.ModelProperties(network = GN.NoNetwork())
    Ark.add_resource!(world, properties)
    @test Ark.get_resource(world, GN.ModelProperties) === properties
    @test hasmethod(GN.initialize_household, Tuple{Any,Any})
    @test hasmethod(GN.generate_social_network, Tuple{Any,Any})
    @test hasmethod(GN.calculate_norm_perception!, Tuple{Any,GN.UtilityConfig})
    @test hasmethod(GN.set_theta!, Tuple{Any,GN.UtilityConfig})
end

@testset "ADR-0007: set_theta! owns extraction, solver stays pure" begin
    @test isdefined(GN, :set_theta!)
    @test !isdefined(GN, :choose_bundles)
    @test !isdefined(GN, :agent_payoff_params)
    @test !isdefined(GN, :gauss_seidel)
    @test hasmethod(
        GN.mutual_best_response,
        Tuple{
            Float64,Float64,Float64,GN.AgentPayoffParams,GN.AgentPayoffParams,GN.UtilityConfig
        },
    )
    @test hasmethod(
        GN.bargain_transfer,
        Tuple{Float64,Float64,Float64,GN.AgentPayoffParams,GN.AgentPayoffParams,GN.UtilityConfig},
    )
end

@testset "ADR-0022: specialized best response falls back bitwise" begin
    # The specialized `best_response_1d(::BestResponseObjective, ...)`
    # method is more specific than the generic one, the generic method
    # is unchanged for generic callers, and every fallback of the
    # specialized method runs the exact `MDR-0002` seeded expression
    # (bitwise, including `NaN`); `mutual_best_response` keeps its
    # signature and loop.
    @test hasmethod(GN.best_response_1d, Tuple{GN.BestResponseObjective{GN.CES},Float64})
    @test hasmethod(
        GN.mutual_best_response,
        Tuple{Float64,Float64,Float64,GN.AgentPayoffParams,GN.AgentPayoffParams,GN.UtilityConfig},
    )
    @test GN.best_response_1d(x -> 1.0 - (x - 0.3)^2, 0.3) isa Float64
    config = GN.UtilityConfig(func=GN.CES(beta=1.5))
    p = GN.AgentPayoffParams(wage_self=1.0, wage_spouse=1.0, is_woman=true)
    obj = GN.BestResponseObjective(0.2, 0.5, p, config)
    @test GN._derivative_applicable(obj, 0.3) == false
    for h_start in (0.0, 0.3, 1.0)
        @test isequal(
            GN.best_response_1d(obj, h_start),
            GN.maximize_1d(obj, 0.0, 1.0, h_start, GN.BEST_RESPONSE_WINDOW, GN.BEST_RESPONSE_TOL),
        )
    end
    @test isnan(GN.best_response_1d(obj, 0.3)) ==
        isnan(GN.maximize_1d(obj, 0.0, 1.0, 0.3, GN.BEST_RESPONSE_WINDOW, GN.BEST_RESPONSE_TOL))
end
