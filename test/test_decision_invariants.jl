# Executable invariants of accepted decisions under
# `registry/code/decisions/`. Each testset cites the record it keeps
# honest; when a decision changes, this file changes with it (see
# `ADR-0008`).

using GenderNorms
using Test

const GN = GenderNorms

@testset "ADR-0005: ModelProperties is parametric in the network spec" begin
    networks = (
        GN.RandomNetwork(),
        GN.WattsStrogatz(),
        GN.PreferentialAttachment(),
        GN.SimilarityNetwork(),
        GN.HomophilyNetwork(),
        GN.NoNetwork(),
        GN.HomogeneousMixing(),
    )
    for network in networks
        properties = GN.ModelProperties(network = network)
        @test typeof(properties) === GN.ModelProperties{typeof(network)}
        # No abstractly typed field: the field type is the type parameter.
        @test fieldtype(typeof(properties), :network) === typeof(network)
    end
end

@testset "ADR-0007: choose_bundles owns extraction, solver stays pure" begin
    @test isdefined(GN, :choose_bundles)
    @test !isdefined(GN, :agent_payoff_params)
    @test !isdefined(GN, :gauss_seidel)
    @test hasmethod(
        GN.mutual_best_response,
        Tuple{
            Float64,Float64,Float64,GN.AgentPayoffParams,GN.AgentPayoffParams,GN.UtilityConfig
        },
    )
end
