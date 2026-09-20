# Solver part of NetLogo `choose-bundle`, ODD section Labour best response.
# The continuous best-response deviation from the NetLogo hill-climb is
# recorded in `MDR-0002`; the `AgentPayoffParams` bundles are transient
# utility-call inputs per `ADR-0006`.

"""
    mutual_best_response(world, woman, man, theta::Float64, config::UtilityConfig, network)

Alternating continuous best responses of the two partners of one household
for a fixed transfer `theta`, starting from their current working times.
Port of NetLogo `choose-bundle` (ODD section Labour best response) with the
continuous solver of `MDR-0002`. Per `ADR-0006`, the `AgentPayoffParams` of
both partners are built locally with `agent_payoff_params` immediately
before they are passed to `individual_utility`; `network` is the concrete
`NetworkSpec` that selects the `ModelProperties{T}` resource (see
`ADR-0005`). Returns the converged `(hw, hm)` working-time pair.
"""
function mutual_best_response(
  world, woman, man, theta::Float64, config::UtilityConfig, network;
  eps=1.0e-3, max_sweeps=100
)
  woman_working_time, = Ark.get_components(world, woman, (WorkingTime,))
  man_working_time, = Ark.get_components(world, man, (WorkingTime,))
  hw = clamp(woman_working_time.current, 0.0, 1.0)
  hm = clamp(man_working_time.current, 0.0, 1.0)
  pw = agent_payoff_params(world, woman, network)
  pm = agent_payoff_params(world, man, network)
  for _ in 1:max_sweeps
    hw_new = best_response_1d(h -> individual_utility(h, hm, theta, pw, config))
    hm_new = best_response_1d(h -> individual_utility(h, hw_new, theta, pm, config))
    change = abs(hw_new - hw) + abs(hm_new - hm)
    hw = clamp(hw_new, 0, 1)
    hm = clamp(hm_new, 0, 1)
    change <= eps && break
  end
  return (hw, hm)
end
