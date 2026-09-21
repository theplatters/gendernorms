# Labour stage of the household bargaining loop. Port of NetLogo
# `choose-bundle`, ODD section Labour best response; the continuous-solver
# deviation from the NetLogo hill-climb is recorded in `MDR-0002`. The
# household components are extracted in `choose_bundles` with `Ark.Query`
# and the transient `AgentPayoffParams` are built there at the solver call
# (see `ADR-0007`).

"""
    mutual_best_response(hw_init::Float64, hm_init::Float64, theta::Float64, pw::AgentPayoffParams, pm::AgentPayoffParams, config::UtilityConfig; eps = 1.0e-3, max_sweeps = 100)

Alternating continuous best responses of the two partners of one household
for a fixed transfer `theta`, starting from the working times `hw_init` and
`hm_init`. Port of NetLogo `choose-bundle` (ODD section Labour best
response) with the seeded continuous solver of `MDR-0002`: each best response
starts from the current hours and keeps them when no feasible sample exists.
The `AgentPayoffParams` `pw` and `pm` are the transient bundles of the woman
and the man, built by `set_theta!` at the call site (see `ADR-0007`).
Returns the converged `(hw, hm)` working-time pair.
"""
function mutual_best_response(
  hw_init::Float64, hm_init::Float64, theta::Float64,
  pw::AgentPayoffParams, pm::AgentPayoffParams, config::UtilityConfig;
  eps=1.0e-3, max_sweeps=100
)
  hw = clamp(hw_init, 0.0, 1.0)
  hm = clamp(hm_init, 0.0, 1.0)
  for _ in 1:max_sweeps
    # Each captured partner hour is bound immutably per iteration: a capture
    # reassigned later in the loop would be boxed, turning every utility
    # evaluation of the best-response search into an allocating dynamic call (see `MDR-0002`).
    hw_new = let partner_h = hm
      best_response_1d(h -> individual_utility(h, partner_h, theta, pw, config), hw)
    end
    isfinite(hw_new) || (hw_new = hw)
    hm_new = let partner_h = hw_new
      best_response_1d(h -> individual_utility(h, partner_h, theta, pm, config), hm)
    end
    isfinite(hm_new) || (hm_new = hm)
    change = abs(hw_new - hw) + abs(hm_new - hm)
    hw = clamp(hw_new, 0, 1)
    hm = clamp(hm_new, 0, 1)
    change <= eps && break
  end
  return (hw, hm)
end

"""
    choose_bundles(world, config::UtilityConfig, network)

Household loop of the labour stage. `Ark.Query` extracts the components of
every woman (`Wage`, `WorkingTime`, `TransferToWoman`, `Conformism`,
`PreferencePrivate`, `Spouse`), the spouse's `Wage`, `WorkingTime`,
`Conformism`, and `PreferencePrivate` are read, the perceived norms of both
partners are computed with `norm_means`, and the two transient
`AgentPayoffParams` are built at the `mutual_best_response` call (see
`ADR-0007`). Every household is evaluated at its current transfer
(`TransferToWoman.current`); the transfer stage (`set-theta` /
`calculate-payoff`) is not ported yet and will reuse the bundles across
theta evaluations. `network` is the concrete `NetworkSpec` that selects the
`ModelProperties{T}` resource (see `ADR-0005`). Returns the `(hw, hm)`
labour pair of every household in query order.
"""
function choose_bundles(world, config::UtilityConfig, network)
  network_type = typeof(network)
  net = Ark.get_resource(world, SocialNetwork)
  properties = Ark.get_resource(world, ModelProperties{network_type})
  globals = properties.network isa HomogeneousMixing ? norm_global_means(world, net) : nothing
  component_types = (Wage, WorkingTime, TransferToWoman, Conformism, PreferencePrivate, Spouse)
  results = Tuple{Float64, Float64}[]
  for (entities, wages, times, transfers, conformisms, preferences, spouses) in
      Ark.Query(world, component_types; with = (Female,))
    @inbounds for f in eachindex(entities)
      woman = entities[f]
      man = spouses[f].entity
      man_wage, man_time, man_conformism, man_preference =
        Ark.get_components(world, man, (Wage, WorkingTime, Conformism, PreferencePrivate))
      woman_vertex = findfirst(==(woman), net.women_entities)
      woman_vertex === nothing && throw(ArgumentError("woman is not in the women entity vector"))
      man_vertex = findfirst(==(man), net.men_entities)
      man_vertex === nothing && throw(ArgumentError("man is not in the men entity vector"))
      woman_norms = norm_means(world, net, woman_vertex, true, globals)
      man_norms = norm_means(world, net, man_vertex, false, globals)
      pw = AgentPayoffParams(
        wage_self = wages[f].current,
        wage_spouse = man_wage.current,
        alpha = preferences[f].current,
        conformism = conformisms[f].amount,
        N_h = woman_norms.division_of_labor,
        N_theta = woman_norms.transfer,
        N_h_spouse = woman_norms.division_of_labor_spouse,
        is_woman = true
      )
      pm = AgentPayoffParams(
        wage_self = man_wage.current,
        wage_spouse = wages[f].current,
        alpha = man_preference.current,
        conformism = man_conformism.amount,
        N_h = man_norms.division_of_labor,
        N_theta = man_norms.transfer,
        N_h_spouse = man_norms.division_of_labor_spouse,
        is_woman = false
      )
      hw_init = times[f].current
      hm_init = man_time.current
      theta = transfers[f].current
      push!(results, mutual_best_response(hw_init, hm_init, theta, pw, pm, config))
    end
  end
  return results
end
