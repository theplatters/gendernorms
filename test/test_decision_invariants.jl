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
    )
    properties = GN.ModelProperties(network = GN.NoNetwork())
    Ark.add_resource!(world, properties)
    @test Ark.get_resource(world, GN.ModelProperties) === properties
    @test hasmethod(GN.initialize_household, Tuple{Any})
    @test hasmethod(GN.generate_social_network, Tuple{Any})
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
