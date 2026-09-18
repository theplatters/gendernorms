abstract type NetworkSpec end

Base.@kwdef struct RandomNetwork <: NetworkSpec
    p::Float64 = 0.01
end

Base.@kwdef struct WattsStrogatz <: NetworkSpec
    neighbors_per_side::Int = 1
    rewiring::Float64 = 0.1
end

Base.@kwdef struct PreferentialAttachment <: NetworkSpec
    m::Int = 1
end

Base.@kwdef struct SimilarityNetwork <: NetworkSpec
    m::Int = 1
    trait::Symbol = :preference_private
end

Base.@kwdef struct HomophilyNetwork <: NetworkSpec
    m::Int = 1
end

struct NoNetwork <: NetworkSpec end

struct HomogeneousMixing <: NetworkSpec end

# The entity vectors define the mapping between graph vertices (indices)
# and agents: vertex `i` is `women_entities[i]` / `men_entities[i]`.
struct SocialNetwork
    men::Graphs.SimpleGraph{Int}
    women::Graphs.SimpleGraph{Int}
    men_entities::Vector{Ark.Entity}
    women_entities::Vector{Ark.Entity}
end

# NetLogo `nw:generate-*`. The population size `n` is not part of the
# specification, it is taken from `ModelProperties.agents_per_gender`.
generate(s::RandomNetwork, n::Int, rng) = Graphs.erdos_renyi(n, s.p; rng)

function generate(s::WattsStrogatz, n::Int, rng)
    k = _watts_strogatz_k(s.neighbors_per_side, n)
    k > 0 || return Graphs.SimpleGraph(n)
    return Graphs.watts_strogatz(n, k, s.rewiring; rng)
end

generate(s::PreferentialAttachment, n::Int, rng) = Graphs.barabasi_albert(n, s.m; rng)
generate(::NoNetwork, n::Int, rng) = Graphs.SimpleGraph(n)
generate(::HomogeneousMixing, n::Int, rng) = Graphs.SimpleGraph(n)

# `Graphs.watts_strogatz` requires an even k with 0 < k < n.
function _watts_strogatz_k(neighbors_per_side::Int, n::Int)
    k = min(2 * neighbors_per_side, n - 1)
    return iseven(k) ? k : k - 1
end

# NetLogo `generate-network`: each agent links to `m` others that are
# sampled with weight `1 / |x_self - x_other - N(0, 0.001)|`.
function generate_similarity(s::SimilarityNetwork, values::AbstractVector{Float64}, rng)
    n = length(values)
    graph = Graphs.SimpleGraph(n)
    for i in 1:n
        weights = [
            j == i ? 0.0 :
            1 / max(abs(values[i] - values[j] + 0.001 * randn(rng)), eps())
            for j in 1:n
        ]
        for j in sample_nodes(weights, s.m, rng)
            Graphs.add_edge!(graph, i, j)
        end
    end
    return graph
end

# NetLogo `generate-homophilic-network`: similarity in conformism, wage and
# preference (the noise only enters the conformism difference).
function generate_homophily(s::HomophilyNetwork, conformism, wage, preference, rng)
    n = length(conformism)
    graph = Graphs.SimpleGraph(n)
    for i in 1:n
        weights = [
            j == i ? 0.0 :
            1 / max(
                abs(conformism[i] - conformism[j] + 0.001 * randn(rng)) +
                abs(wage[i] - wage[j]) +
                abs(preference[i] - preference[j]),
                eps(),
            )
            for j in 1:n
        ]
        for j in sample_nodes(weights, s.m, rng)
            Graphs.add_edge!(graph, i, j)
        end
    end
    return graph
end

# Weighted sampling without replacement (Efraimidis & Spirakis 2006),
# equivalent to NetLogo's `rnd:weighted-n-of`.
function sample_nodes(weights::AbstractVector{Float64}, m::Int, rng)
    candidates = findall(>(0.0), weights)
    m = min(m, length(candidates))
    m > 0 || return Int[]
    keys = [rand(rng)^(1 / weights[j]) for j in candidates]
    return candidates[partialsortperm(keys, 1:m, rev = true)]
end
