# Household bargaining loop, both stages. Labour stage: `mutual_best_response`
# (port of NetLogo `choose-bundle`, ODD section Labour best response, see
# `MDR-0002`). Transfer stage: `set_theta!` (world loop, port of NetLogo
# `set-theta`) plus the pure helpers `bargain_transfer`, `equilibrium_payoff`,
# `outside_options`, and `nash_product` (ports of NetLogo `set-theta` and
# `calculate-payoff`, ODD section Transfer bargaining); household components
# are extracted with `Ark.Query` (see `ADR-0007`); deviations are recorded in
# `MDR-0005`.

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
    outside_options(hw_init::Float64, hm_init::Float64, pw::AgentPayoffParams, pm::AgentPayoffParams, config::UtilityConfig)

Outside options of one household: the utilities of both partners at the
labour equilibrium with zero transfer. Port of the first lines of NetLogo
`set-theta` (ODD section Transfer bargaining (`set-theta`,
`calculate-payoff`)); the continuous transfer search is recorded in
`MDR-0005`. Returns `(uw_out, um_out)`.
"""
function outside_options(
  hw_init::Float64, hm_init::Float64,
  pw::AgentPayoffParams, pm::AgentPayoffParams, config::UtilityConfig
)
  hw_out, hm_out = mutual_best_response(hw_init, hm_init, 0.0, pw, pm, config)
  uw_out = individual_utility(hw_out, hm_out, 0.0, pw, config)
  um_out = individual_utility(hm_out, hw_out, 0.0, pm, config)
  return uw_out, um_out
end

"""
    nash_product(theta::Float64, hw::Float64, hm::Float64, uw_out::Float64, um_out::Float64, pw::AgentPayoffParams, pm::AgentPayoffParams, config::UtilityConfig)

Nash product of NetLogo `calculate-payoff` (ODD section Transfer bargaining
(`set-theta`, `calculate-payoff`)) at transfer `theta` and working times `hw`
and `hm`: the two utility gains over the outside options `uw_out` and
`um_out`, multiplied when both gains are finite and non-negative, otherwise
`-Inf` (replacing the `-1` sentinel); see `MDR-0005`. Returns a `Float64`.
"""
function nash_product(
  theta::Float64, hw::Float64, hm::Float64,
  uw_out::Float64, um_out::Float64,
  pw::AgentPayoffParams, pm::AgentPayoffParams, config::UtilityConfig
)::Float64
  gain_w = individual_utility(hw, hm, theta, pw, config) - uw_out
  gain_m = individual_utility(hm, hw, theta, pm, config) - um_out
  if isfinite(gain_w) && isfinite(gain_m) && gain_w >= 0.0 && gain_m >= 0.0
    return gain_w * gain_m
  end
  return -Inf
end

"""
    equilibrium_payoff(theta::Float64, hw_start::Float64, hm_start::Float64, uw_out::Float64, um_out::Float64, pw::AgentPayoffParams, pm::AgentPayoffParams, config::UtilityConfig)

Labour equilibrium and Nash product at transfer `theta`, warm-started from
`hw_start` and `hm_start`. One evaluation of NetLogo `set-theta` with
`calculate-payoff` (ODD section Transfer bargaining (`set-theta`,
`calculate-payoff`)); the explicit warm-start arguments carry no closure
state (see `MDR-0005`). Returns `(payoff, hw, hm)`.
"""
function equilibrium_payoff(
  theta::Float64, hw_start::Float64, hm_start::Float64,
  uw_out::Float64, um_out::Float64,
  pw::AgentPayoffParams, pm::AgentPayoffParams, config::UtilityConfig
)
  hw, hm = mutual_best_response(hw_start, hm_start, theta, pw, pm, config)
  return nash_product(theta, hw, hm, uw_out, um_out, pw, pm, config), hw, hm
end

# Absolute argument tolerance of the transfer search: the resolution of the
# reference `delta-theta` grid (see `MDR-0005`).
const TRANSFER_TOL = 1.0e-3

"""
    bargain_transfer(hw_init::Float64, hm_init::Float64, theta_init::Float64, pw::AgentPayoffParams, pm::AgentPayoffParams, config::UtilityConfig; tol::Float64 = TRANSFER_TOL)

Transfer bargain of one household: continuous 1-D maximization of the
`calculate-payoff` Nash product over `[-1, 1]` with the in-repo Brent search
`maximize_1d`. Port of NetLogo `set-theta` with NetLogo `calculate-payoff`
(ODD section Transfer bargaining (`set-theta`, `calculate-payoff`)); see
`MDR-0005`. There is no scan, fixed grid or pocket refinement; the status quo
is evaluated first and kept unless a feasible maximizer beats it (fixes ODD
quirk 3, fallback per `MDR-0005`); every inner solve starts from the
status-quo labour equilibrium; `tol` is the absolute argument tolerance
recorded in `MDR-0005`. Returns `(theta, hw, hm)`.
"""
function bargain_transfer(
  hw_init::Float64, hm_init::Float64, theta_init::Float64,
  pw::AgentPayoffParams, pm::AgentPayoffParams, config::UtilityConfig;
  tol::Float64=TRANSFER_TOL
)
  theta0 = clamp(theta_init, -1.0, 1.0)
  uw_out, um_out = outside_options(hw_init, hm_init, pw, pm, config)
  hw_status, hm_status = mutual_best_response(hw_init, hm_init, theta0, pw, pm, config)
  status_payoff = nash_product(theta0, hw_status, hm_status, uw_out, um_out, pw, pm, config)
  objective(theta) = first(equilibrium_payoff(theta, hw_status, hm_status, uw_out, um_out, pw, pm, config))
  theta_best = maximize_1d(objective, -1.0, 1.0, tol)
  if isfinite(theta_best)
    payoff_best, hw_best, hm_best = equilibrium_payoff(theta_best, hw_status, hm_status, uw_out, um_out, pw, pm, config)
    if isfinite(payoff_best) && payoff_best > status_payoff
      return theta_best, hw_best, hm_best
    end
  end
  return theta0, hw_status, hm_status
end

"""
    payoff_params(wage_self::Float64, wage_spouse::Float64, alpha::Float64, conformism::Float64, means, is_woman::Bool)

Transient per-agent parameter bundle of NetLogo `set-theta` (ODD section
Transfer bargaining (`set-theta`, `calculate-payoff`)); the perceived norms
`means` supply `N_h` (own working time), `N_theta` (transfer), and
`N_h_spouse` (spouse working time) (see `MDR-0005` and `ADR-0007`). Returns
an `AgentPayoffParams`.
"""
function payoff_params(
  wage_self::Float64, wage_spouse::Float64, alpha::Float64,
  conformism::Float64, means, is_woman::Bool
)
  return AgentPayoffParams(
    wage_self=wage_self,
    wage_spouse=wage_spouse,
    alpha=alpha,
    conformism=conformism,
    N_h=means.division_of_labor,
    N_theta=means.transfer,
    N_h_spouse=means.division_of_labor_spouse,
    is_woman=is_woman
  )
end

# Chunk size of the per-household `Threads.@threads :greedy` loop below:
# the greedy scheduler pulls whole chunks instead of one item per unbuffered
# channel pull, amortizing the per-item pull overhead over
# `HOUSEHOLD_BARGAIN_CHUNK` households while keeping the load-balance
# granularity fine for the uneven Brent iterations of `bargain_transfer`
# (see `ADR-0014`).
const HOUSEHOLD_BARGAIN_CHUNK = 4

"""
    set_theta!(world, config::UtilityConfig)

Household loop of the household bargaining: ports NetLogo `set-theta` for
every household (ODD section Transfer bargaining (`set-theta`,
`calculate-payoff`)); the labour stage runs inside `bargain_transfer` (see
`MDR-0005`). Household components are extracted with `Ark.Query` (see
`ADR-0007`); the transfer component mirrors the wife's value on the man (see
`registry/model/entities.md`). The per-household loop runs with
`Threads.@threads :greedy` over the disjoint households in chunks of
`HOUSEHOLD_BARGAIN_CHUNK` items (the greedy scheduler pulls whole chunks) to
amortize its per-item channel pull, each iteration with its own `spouse_seen`
scratch vector for `norm_means`, so the results are independent of
scheduling and thread count (see `ADR-0014`). The world is mutated and
nothing is returned.
"""
function set_theta!(world, config::UtilityConfig)
  net = Ark.get_resource(world, SocialNetwork)
  properties = Ark.get_resource(world, ModelProperties)
  globals = properties.network isa HomogeneousMixing ? norm_global_means(world, net) : nothing
  women_index = Dict(entity => vertex for (vertex, entity) in enumerate(net.women_entities))
  men_index = Dict(entity => vertex for (vertex, entity) in enumerate(net.men_entities))
  component_types = (Wage, WorkingTime, TransferToWoman, Conformism, PreferencePrivate, Spouse)
  for (entities, wages, times, transfers, conformisms, preferences, spouses) in
      Ark.Query(world, component_types; with=(Female,))
    Threads.@threads :greedy for chunk in Iterators.partition(eachindex(entities), HOUSEHOLD_BARGAIN_CHUNK)
      for f in chunk
        woman = entities[f]
        man = spouses[f].entity
        man_wage, man_time, man_transfer, man_conformism, man_preference =
          Ark.get_components(world, man, (Wage, WorkingTime, TransferToWoman, Conformism, PreferencePrivate))
        woman_vertex = get(women_index, woman, 0)
        woman_vertex == 0 && throw(ArgumentError("woman is not in the women entity vector"))
        man_vertex = get(men_index, man, 0)
        man_vertex == 0 && throw(ArgumentError("man is not in the men entity vector"))

        spouse_seen = Ark.Entity[]
        woman_norms = norm_means(world, net, woman_vertex, true, globals, spouse_seen)
        man_norms = norm_means(world, net, man_vertex, false, globals, spouse_seen)

        pw = payoff_params(
          wages[f].current, man_wage.current, preferences[f].current,
          conformisms[f].amount, woman_norms, true
        )
        pm = payoff_params(
          man_wage.current, wages[f].current, man_preference.current,
          man_conformism.amount, man_norms, false
        )

        theta, hw, hm = bargain_transfer(
          times[f].current, man_time.current, transfers[f].current, pw, pm, config
        )
        # the woman is in the query, so the views write in place
        times[f] = WorkingTime(hw, times[f].old)
        transfers[f] = TransferToWoman(theta, transfers[f].old)
        # the man is not in the women's query, so only the entity API exists
        Ark.set_components!(
          world, man, (WorkingTime(hm, man_time.old), TransferToWoman(theta, man_transfer.old))
        )
      end
    end
  end
  return nothing
end
