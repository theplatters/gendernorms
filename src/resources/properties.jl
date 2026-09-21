# Ark 0.5.1 keys resources by exact concrete type, so `ModelProperties` is
# a non-parametric resource; the world is the single carrier of the network
# specification and access points fetch it with
# `Ark.get_resource(world, ModelProperties)` without a specification argument
# (see `ADR-0010`).
Base.@kwdef struct ModelProperties
  agents_per_gender::Int64 = 400
  std_dev::Float64 = 0.2
  initial_transfer::Float64 = 0.0
  network::NetworkSpec = WattsStrogatz()
end

Base.@kwdef struct PaidTime
  men::Float64 = 0.77
  woman::Float64 = 0.36
end

Base.@kwdef struct MeanWage
  men::Float64 = 1.0
  woman::Float64 = 0.9
end

Base.@kwdef struct MeanPreference
  men::Float64 = 0.45
  woman::Float64 = 0.48
end

Base.@kwdef struct InitialConformism
  men::Float64 = 10.0
  woman::Float64 = 10.0
end


Base.@kwdef struct ProbeCouple # *-in-question, specific-couple override
  wage_female::Float64 = 2.0
  wage_male::Float64 = 2.0
  pref_female::Float64 = 0.5
  pref_male::Float64 = 0.5
  conformism_male::Float64 = 1.0
  conformism_female::Float64 = 1.0
end

# -- mutable run state (replaces globals) --
mutable struct GlobalStats
  mean_men::Float64
  mean_women::Float64
  mean_transfer::Float64
  hist_men::Vector{Float64}
  hist_women::Vector{Float64}
  wage_gap::Float64
  run_time::Float64
end
