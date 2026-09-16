abstract type NetworkSpec end

Base.@kwdef struct RandomNetwork <: NetworkSpec
    n::Int
    p::Float64 = 0.01
end

Base.@kwdef struct WattsStrogatz <: NetworkSpec
    n::Int
    neighbors_per_side::Int = 1
    rewiring::Float64 = 0.1
end

Base.@kwdef struct PreferentialAttachment <: NetworkSpec
    n::Int
    m::Int = 1
end

Base.@kwdef struct SimilarityNetwork <: NetworkSpec
    n::Int
    m::Int = 1
    trait::Symbol
end

Base.@kwdef struct HomophilyNetwork <: NetworkSpec
    n::Int
    m::Int = 1
end

struct NoNetwork <: NetworkSpec
    n::Int
end

struct HomogeneousMixing <: NetworkSpec
    n::Int
end

struct SocialNetwork
    men::Graphs.SimpleGraph{Int}
    women::Graphs.SimpleGraph{Int}
end

generate(s::RandomNetwork, rng) = Graphs.erdos_renyi(s.n, s.p; rng)
generate(s::WattsStrogatz, rng) = Graphs.watts_strogatz(s.n, 2 * s.neighbors_per_side, s.rewiring; rng)
generate(s::PreferentialAttachment, rng) = Graphs.barabasi_albert(s.n, s.m; rng)
generate(s::NoNetwork, rng) = Graphs.SimpleGraph(s.n)
generate(s::HomogeneousMixing, rng) = Graphs.SimpleGraph(s.n)
