# Household bargaining loop, both stages. Labour stage: `mutual_best_response`
# (port of NetLogo `choose-bundle`, ODD section Labour best response, see
# `MDR-0002`). Transfer stage: `set_theta!` (world loop, port of NetLogo
# `set-theta`) plus the pure helpers `bargain_transfer`, `equilibrium_payoff`,
# `outside_options`, and `nash_product` (ports of NetLogo `set-theta` and
# `calculate-payoff`, ODD section Transfer bargaining); household components
# are extracted with `Ark.Query` (see `ADR-0007`); production uses the bounded
# feasibility-guided search of `MDR-0016` / `ADR-0021`. The staged discovery
# search
# of `MDR-0014` is retained for explicit validation. Both share the evaluation
# cache `TransferObjectiveValue` and task-owned `TransferSearchScratch` of
# `ADR-0017` and `ADR-0019`, superseding the per-call cache of `ADR-0016`.
# The certification helpers
# `_objective_prunable`, `_payoff_upper_bound`, `_objective_interval_prunable`,
# and `_payoff_interval_bound` of the payoff-only transfer objective are
# optimization-only (see `ADR-0015`, `ADR-0017`, and `ADR-0019`), not ported
# NetLogo behavior.

"""
    mutual_best_response(hw_init::Float64, hm_init::Float64, theta::Float64, pw::AgentPayoffParams, pm::AgentPayoffParams, config::UtilityConfig; eps = 1.0e-3, max_sweeps = 100)

Alternating continuous best responses of the two partners of one household
for a fixed transfer `theta`, starting from the working times `hw_init` and
`hm_init`. Port of NetLogo `choose-bundle` (ODD section Labour best
response) with the seeded continuous solver of `MDR-0002`: each best response
starts from the current hours and keeps them when no feasible sample exists.
The `AgentPayoffParams` `pw` and `pm` are the transient bundles of the woman
and the man, built by `set_theta!` at the call site (see `ADR-0007`). Each
best response runs over a prepared own-hours objective
`BestResponseObjective` (the `individual_utility` of that partner with the
spouse hours of the iteration hoisted in; see `MDR-0014` and `ADR-0018`),
so the alternating loop allocates nothing and carries no closures.
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
    hw_new = best_response_1d(BestResponseObjective(theta, hm, pw, config), hw)
    isfinite(hw_new) || (hw_new = hw)
    hm_new = best_response_1d(BestResponseObjective(theta, hw_new, pm, config), hm)
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
`calculate-payoff`)); the production transfer search is recorded in
`MDR-0016`. Returns `(uw_out, um_out)`.
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
    _transfer_gains(theta::Float64, hw::Float64, hm::Float64, uw_out::Float64, um_out::Float64, pw::AgentPayoffParams, pm::AgentPayoffParams, config::UtilityConfig)

The two utility gains of `nash_product` (ODD section Transfer bargaining
(`set-theta`, `calculate-payoff`)) at transfer `theta` and working times
`hw` and `hm`: `gain_w = individual_utility(hw, hm, theta, pw, config) -
uw_out` for the woman `pw` and the mirrored `gain_m` for the man `pm`,
computed in that order with the same expressions as `nash_product` itself.
Factored out so one evaluation computes the gains exactly once for both
the Nash payoff and the guidance values of the transfer search (see
`MDR-0016` and `ADR-0021`); values are bitwise identical to computing
them inside `nash_product`. Returns `(gain_w, gain_m)`.
"""
function _transfer_gains(
  theta::Float64, hw::Float64, hm::Float64,
  uw_out::Float64, um_out::Float64,
  pw::AgentPayoffParams, pm::AgentPayoffParams, config::UtilityConfig
)
  gain_w = individual_utility(hw, hm, theta, pw, config) - uw_out
  gain_m = individual_utility(hm, hw, theta, pm, config) - um_out
  return gain_w, gain_m
end

"""
    _nash_from_gains(gain_w::Float64, gain_m::Float64)

Nash product of the two utility gains `gain_w` and `gain_m` (see
`nash_product` and `_transfer_gains`): the product when both gains are
finite and non-negative, otherwise `-Inf` (replacing the `-1` sentinel);
see `MDR-0014`. Returns a `Float64`.
"""
function _nash_from_gains(gain_w::Float64, gain_m::Float64)::Float64
  if isfinite(gain_w) && isfinite(gain_m) && gain_w >= 0.0 && gain_m >= 0.0
    return gain_w * gain_m
  end
  return -Inf
end

"""
    nash_product(theta::Float64, hw::Float64, hm::Float64, uw_out::Float64, um_out::Float64, pw::AgentPayoffParams, pm::AgentPayoffParams, config::UtilityConfig)

Nash product of NetLogo `calculate-payoff` (ODD section Transfer bargaining
(`set-theta`, `calculate-payoff`)) at transfer `theta` and working times `hw`
and `hm`: the two utility gains over the outside options `uw_out` and
`um_out`, multiplied when both gains are finite and non-negative, otherwise
`-Inf` (replacing the `-1` sentinel); see `MDR-0014`. Delegates to
`_transfer_gains` and `_nash_from_gains` (same expressions, same order,
bitwise identical). Returns a `Float64`.
"""
function nash_product(
  theta::Float64, hw::Float64, hm::Float64,
  uw_out::Float64, um_out::Float64,
  pw::AgentPayoffParams, pm::AgentPayoffParams, config::UtilityConfig
)::Float64
  gain_w, gain_m = _transfer_gains(theta, hw, hm, uw_out, um_out, pw, pm, config)
  return _nash_from_gains(gain_w, gain_m)
end

"""
    equilibrium_payoff(theta::Float64, hw_start::Float64, hm_start::Float64, uw_out::Float64, um_out::Float64, pw::AgentPayoffParams, pm::AgentPayoffParams, config::UtilityConfig)

Labour equilibrium and Nash product at transfer `theta`, warm-started from
`hw_start` and `hm_start`. One evaluation of NetLogo `set-theta` with
`calculate-payoff` (ODD section Transfer bargaining (`set-theta`,
`calculate-payoff`)); the explicit warm-start arguments carry no closure
state (see `MDR-0014`). Returns `(payoff, hw, hm)`.
"""
function equilibrium_payoff(
  theta::Float64, hw_start::Float64, hm_start::Float64,
  uw_out::Float64, um_out::Float64,
  pw::AgentPayoffParams, pm::AgentPayoffParams, config::UtilityConfig
)
  hw, hm = mutual_best_response(hw_start, hm_start, theta, pw, pm, config)
  return nash_product(theta, hw, hm, uw_out, um_out, pw, pm, config), hw, hm
end

# Solver parameters of the transfer searches (see `MDR-0014` and
# `MDR-0016`): numerical
# search parameters, not model parameters. Coarse domain grid spacing of
# the offline discovery search only (`MDR-0014`), the resolution of the reference
# `delta-theta` grid outside the fine anchor windows (the
# `TRANSFER_TOL` of `MDR-0005` folds in here).
const TRANSFER_COARSE_STEP = 1.0e-3

# Fine anchor-window grid spacing of the staged transfer search (see
# `MDR-0014`): the resolution within `TRANSFER_FINE_STEPS *
# TRANSFER_FINE_STEP` = 0.002 of each anchor.
const TRANSFER_FINE_STEP = 1.0e-4

# Half-size of the fine anchor windows of the staged transfer search
# in fine steps: `TRANSFER_FINE_STEPS * TRANSFER_FINE_STEP` = 0.002 on
# each side of each anchor (see `MDR-0014`).
const TRANSFER_FINE_STEPS = 20

# Absolute argument tolerance of the bounded Brent refinement brackets of
# the staged transfer search, finer than the fine grid (see `MDR-0014`).
const TRANSFER_REFINE_TOL = 1.0e-5

# Fixed exploration probes on both sides of each production anchor, instead
# of a full-domain scan: the near-anchor ladder (0.0001, 0.001, 0.003) covers
# the demonstrated near-zero bands and the remote ladder (0.03, 0.1, 0.3)
# covers coarse remote coverage (see `MDR-0016`). Failures never establish
# global infeasibility (NetLogo `set-theta`, ODD section Transfer bargaining).
const TRANSFER_EXPLORE_OFFSETS = (0.0001, 0.001, 0.003, 0.03, 0.1, 0.3)

# Anchor-overlap threshold of the production ladder (see `MDR-0016`): when
# `abs(theta0) <= TRANSFER_ANCHOR_OVERLAP` the `0.0` and `theta0` anchor
# ladders coincide and only one ladder is enumerated.
const TRANSFER_ANCHOR_OVERLAP = 0.002

# Minimum normalized guidance of a refined production peak (see `MDR-0016`):
# weak maxima below this floor carry no almost-feasible signal and are left
# as unrefined candidates.
const TRANSFER_GUIDANCE_MIN = -2.0e-5

# Offset of the adaptive production probe (see `MDR-0016`): sampled on one
# side of one anchor only when guidance at `+/- 0.001` is at least
# `TRANSFER_GUIDANCE_MIN` and strictly exceeds guidance at `+/- 0.0001`,
# restoring the household-100-style hidden band's sampled-neighbour bracket
# without a dense ladder.
const TRANSFER_ADAPTIVE_OFFSET = 0.0003

# Production refinement budgets of `MDR-0016` / `ADR-0021`: at most one
# guidance peak and one strictly improving finite-payoff candidate, with at
# most `TRANSFER_REFINE_MAX_ITER` iteration probes each. Seeds and bracket
# endpoints are already cached.
const TRANSFER_GUIDANCE_REFINEMENTS = 1
const TRANSFER_MAX_REFINEMENTS = 1
const TRANSFER_REFINE_MAX_ITER = 6

# Worst-case distinct objective records, including the seeded status quo:
# four anchors, the exploration ladder on both signs of up to two anchors,
# the adaptive probes of both signs of up to two anchors, then the iteration
# probes of both refinements (their seeds are cached Stage A points).
# Outside/status solves are separate.
const TRANSFER_SEARCH_MAX_EVALS = 4 +
    4 * length(TRANSFER_EXPLORE_OFFSETS) + 4 +
    (TRANSFER_GUIDANCE_REFINEMENTS + TRANSFER_MAX_REFINEMENTS) * TRANSFER_REFINE_MAX_ITER

# Total relative margin of the certified `-Inf` transfer-objective
# certificate (see `ADR-0015`): the Float64 envelope bound is inflated
# by this factor before it is compared against an outside option. The
# margin covers the rounding of the computed consumption `x`, leisure
# `Q`, and norm exponent `z` against their analytic bounds (a few ulps
# of the `x <= q*v`, `Q <= 2-v`, and `-norm >= z` comparisons), the
# documented `<= 1` ulp error each of `^`, `sqrt`, and `exp` in the
# runtime math library, and their combination in `material * exp`:
# tens of ulps (about 5.0e-15) in total. Per spec, only the CES outer
# power `S^(1/beta)` amplifies rounding: its condition number in the
# rounded inner sum `S` is `1/beta`, so the gap between the computed
# utility and the computed envelope grows by at most
# `(1/beta) * n_ops * eps` with `eps = 2^-53` and `n_ops = 10` the
# combined inner-sum error budget of the two evaluations (see
# `CES_CERT_MIN_BETA`); the other specs have exponents `<= 1` and only
# contract rounding. CES therefore certifies only inside the safe band
# `beta >= CES_CERT_MIN_BETA`, where the amplification is at most
# about 1.0e-12 and the whole in-band rounding budget stays below
# 1.0e-12, leaving more than three orders of magnitude of headroom
# against 1.0e-9 (about 4500 ulps); below the band the certificate
# fails open (about 1.0e-4 of amplification at `beta = 1.0e-12` would
# dwarf this margin). Every intermediate outside the normal range
# fails open instead: the CES `beta >= 1` root branch additionally
# guards its inner sum `S` (a subnormal `S` would map up into the
# normal material range; for `beta < 1` it maps below the `floatmin`
# floor of the bound), see `_payoff_upper_bound`, `_envelope_peak`, and
# `_material_envelope(::CES, ...)`.
const OBJECTIVE_CERT_MARGIN = 1.0e-9

"""
    _payoff_upper_bound(theta::Float64, p::AgentPayoffParams, config::UtilityConfig)

Certified Float64 upper bound on the computed `individual_utility` of
agent `p` at transfer `theta` over every feasible working-time pair
`h_self`, `h_spouse` in `[0, 1]`, or `NaN` when the certificate fails
open. The bound is `M * exp(-z)` (compare `individual_utility`),
inflated by `OBJECTIVE_CERT_MARGIN` at the comparison site
`_objective_prunable`: `M` is the material envelope
`_material_envelope` over `v` with `x <= q * v` and `Q <= 2 - v`, where
the payer (`relevant_transfer >= 0`) has `q = wage_self * (1 -
abs(theta))`, `v = h_self`, `d = 1`, and the recipient has
`q = max(wage_self, abs(theta) * wage_spouse)`, `v = h_self +
h_spouse`, `d = 2`; `z = conformism * w_transfer * (theta -
N_theta)^2` drops the two non-negative norm squares of `individual_utility`
(the `N_h` and `N_h_spouse` terms) and therefore lower-bounds the norm
exponent whenever `conformism` and the weights are non-negative. The
bound holds for the computed Float64 result of `individual_utility`,
not only for the real formula (`OBJECTIVE_CERT_MARGIN`). Returns
`0.0` exactly when every feasible `individual_utility` is exactly
`-Inf` by its `x <= 0` guard: this happens when `q == 0.0`, because
IEEE rounding is monotone and the computed consumption is then `<= 0.0`
at any hours. Fails open (`NaN`) on any non-finite or out-of-range input (`theta` outside `[-1, 1]`,
negative wages, weights, or conformism, `alpha` outside `[0, 1]`,
`beta` outside the certified band `beta >= CES_CERT_MIN_BETA` for
CES), and on non-finite or subnormal envelope intermediates (in the
CES root case `beta >= 1`, a subnormal inner sum). Used only by
`_objective_prunable` inside the payoff-only transfer objective, never
on the committed-hours path (see `ADR-0015`). Not a ported NetLogo
behavior.
"""
function _payoff_upper_bound(
    theta::Float64, p::AgentPayoffParams, config::UtilityConfig
)::Float64
    isfinite(theta) || return NaN
    (-1.0 <= theta <= 1.0) || return NaN
    (isfinite(p.wage_self) && p.wage_self >= 0.0) || return NaN
    (isfinite(p.wage_spouse) && p.wage_spouse >= 0.0) || return NaN
    (isfinite(p.alpha) && 0.0 <= p.alpha <= 1.0) || return NaN
    (isfinite(p.conformism) && p.conformism >= 0.0) || return NaN
    (isfinite(p.N_h) && isfinite(p.N_theta) && isfinite(p.N_h_spouse)) || return NaN
    (isfinite(config.w_self) && config.w_self >= 0.0) || return NaN
    (isfinite(config.w_transfer) && config.w_transfer >= 0.0) || return NaN
    (isfinite(config.w_partner) && config.w_partner >= 0.0) || return NaN
    func = config.func
    if func isa CES
        (isfinite(func.beta) && func.beta >= CES_CERT_MIN_BETA) || return NaN
    end
    relevant_transfer = p.is_woman ? -theta : theta
    recipient = relevant_transfer < 0.0
    r = abs(theta)
    local q::Float64
    local d::Float64
    if recipient
        q = max(p.wage_self, r * p.wage_spouse)
        d = 2.0
    else
        q = p.wage_self * (1.0 - r)
        d = 1.0
    end
    iszero(q) && return 0.0
    (isfinite(q) && q >= floatmin(Float64)) || return NaN
    m = _material_envelope(func, q, d, p.alpha, recipient)
    (isfinite(m) && m >= floatmin(Float64)) || return NaN
    dz = theta - p.N_theta
    z = p.conformism * (config.w_transfer * (dz * dz))
    isfinite(z) || return NaN
    e = exp(-z)
    (isfinite(e) && e >= floatmin(Float64)) || return NaN
    bound = m * e
    (isfinite(bound) && bound >= floatmin(Float64)) || return NaN
    return bound
end

"""
    _objective_prunable(theta::Float64, uw_out::Float64, um_out::Float64, pw::AgentPayoffParams, pm::AgentPayoffParams, config::UtilityConfig)

Certified `-Inf` decision of the payoff-only transfer objective (see
`ADR-0015`): `true` only when the sound upper bound
`_payoff_upper_bound` proves that the computed utility of at least one
partner at transfer `theta` is strictly below that partner's outside
option (`uw_out` for the woman `pw`, `um_out` for the man `pm`) at
every feasible working-time pair, so `nash_product` would return
exactly `-Inf` and the objective may return `-Inf` without solving the
labour equilibrium. One partner suffices because `nash_product` needs
both gains non-negative. The comparison is strict (a zero gain is
feasible and yields the finite payoff `0.0`) and inflated by
`OBJECTIVE_CERT_MARGIN`, so a pruned point's true computed payoff is
always exactly the returned `-Inf`. Fails open (`false`) whenever a
bound is `NaN` or an outside option is non-finite. Used only inside
`bargain_transfer`'s payoff-only objective, never on the committed-hours
path and never inside `outside_options`, `nash_product`,
`equilibrium_payoff`, or `mutual_best_response`. Not a ported NetLogo
behavior.
"""
function _objective_prunable(
    theta::Float64, uw_out::Float64, um_out::Float64,
    pw::AgentPayoffParams, pm::AgentPayoffParams, config::UtilityConfig
)::Bool
    (isfinite(uw_out) && isfinite(um_out)) || return false
    bound_w = _payoff_upper_bound(theta, pw, config)
    if isfinite(bound_w) && bound_w * (1.0 + OBJECTIVE_CERT_MARGIN) < uw_out
        return true
    end
    bound_m = _payoff_upper_bound(theta, pm, config)
    return isfinite(bound_m) && bound_m * (1.0 + OBJECTIVE_CERT_MARGIN) < um_out
end

"""
    _payoff_interval_bound(lo::Float64, hi::Float64, recipient::Bool, p::AgentPayoffParams, config::UtilityConfig)

Certified Float64 upper bound on the computed `individual_utility` of
agent `p` at every transfer of one nonzero-sign slab `[lo, hi]` over
every feasible working-time pair, or `NaN` when the certificate fails
open (see `ADR-0017`). The slab must be one-signed and nonzero:
`hi <= 0.0` with `lo < 0.0`, or `lo >= 0.0` with `hi > 0.0`; the zero
point itself is a payer point for both partners under the strict
`relevant_transfer < 0` test of `individual_utility` and is certified
through the pointwise `_objective_prunable` instead. `recipient` fixes
the role of `p` on the whole slab and must match the role
`individual_utility` takes there (`true` for the woman on a positive
slab and the man on a negative slab). The bound is `B_I = M *
exp(-z_min)` (inflated by `OBJECTIVE_CERT_MARGIN` at the comparison
site `_objective_interval_prunable`), separated so that consumption and
norm effects cannot oppose: `M` is the material envelope
`_material_envelope` at the slackest consumption of the slab, the payer
(`d == 1`, `v == h_self`) at `q = wage_self * (1 - a)` and the
recipient (`d == 2`, `v == h_self + h_spouse`) at `q = max(wage_self,
b * wage_spouse)`, where `a <= |theta| <= b` is the slab's range of
absolute transfers (`a = min(abs(lo), abs(hi))`, `b = max(abs(lo),
abs(hi))`); `z_min` is the smallest norm penalty of the slab, at
`closest = clamp(N_theta, lo, hi)`: `z_min = conformism * w_transfer *
(closest - N_theta)^2` in the operation order of
`individual_utility`'s retained term. Guards, margin arithmetic, the
CES `beta >= CES_CERT_MIN_BETA` band, the zero-wage `q == 0` rule
(exact `x <= 0 -> -Inf` by IEEE monotonicity), and the fail-open
discipline are those of `_payoff_upper_bound` (see `ADR-0015`); the
bound holds for the computed Float64 result, not only for the real
formula. Additionally the cheap `_payoff_upper_bound` guards are
verified at the TIGHTEST point of the slab as well (smallest
consumption `q`, largest norm penalty `z` with its `exp` above `2 *
floatmin`), and `_interval_normal_ok` verifies the material side
lazily, so the pointwise bound is finite at every covered transfer:
wherever this bound certifies, the pointwise `_objective_prunable`
certifies too and would have returned the same `-Inf` sentinel, so the
interval prefilter never removes a solve and never changes a cached
evaluation (`ADR-0017`). For the exact zero-consumption rule the
parity holds through that identical rule alone (the pointwise
`_payoff_upper_bound` returns the same exact `0.0` bound at every
covered transfer), so no material guard is consulted there (see
`_interval_normal_ok`). Extreme slabs (a subnormal or underflowing
`exp` at the tight corner, a subnormal consumption or subnormal
material envelope somewhere in the interval, or a mixed zero/nonzero
consumption range) fail open here even when the slack bound is sound.
Used only by `_objective_interval_prunable` as a Stage A prefilter of
`bargain_transfer`, never on the committed-hours path (see
`ADR-0017`). Not a ported NetLogo behavior.
"""
function _payoff_interval_bound(
    lo::Float64, hi::Float64, recipient::Bool,
    p::AgentPayoffParams, config::UtilityConfig
)::Float64
    (isfinite(lo) && isfinite(hi) && lo <= hi) || return NaN
    (hi <= 0.0 || lo >= 0.0) || return NaN
    (lo < 0.0 || hi > 0.0) || return NaN
    (isfinite(p.wage_self) && p.wage_self >= 0.0) || return NaN
    (isfinite(p.wage_spouse) && p.wage_spouse >= 0.0) || return NaN
    (isfinite(p.alpha) && 0.0 <= p.alpha <= 1.0) || return NaN
    (isfinite(p.conformism) && p.conformism >= 0.0) || return NaN
    (isfinite(p.N_h) && isfinite(p.N_theta) && isfinite(p.N_h_spouse)) || return NaN
    (isfinite(config.w_self) && config.w_self >= 0.0) || return NaN
    (isfinite(config.w_transfer) && config.w_transfer >= 0.0) || return NaN
    (isfinite(config.w_partner) && config.w_partner >= 0.0) || return NaN
    func = config.func
    if func isa CES
        (isfinite(func.beta) && func.beta >= CES_CERT_MIN_BETA) || return NaN
    end
    r_min = min(abs(lo), abs(hi))
    r_max = max(abs(lo), abs(hi))
    local q_slack::Float64
    local q_tight::Float64
    local d::Float64
    if recipient
        q_slack = max(p.wage_self, r_max * p.wage_spouse)
        q_tight = max(p.wage_self, r_min * p.wage_spouse)
        d = 2.0
    else
        q_slack = p.wage_self * (1.0 - r_min)
        q_tight = p.wage_self * (1.0 - r_max)
        d = 1.0
    end
    # Zero-wage rule: zero slack consumption means zero consumption at
    # every transfer of the slab, so the computed utility is exactly
    # `-Inf` everywhere by its `x <= 0` guard (IEEE monotonicity). A
    # mixed zero/nonzero range holds transfers with subnormal positive
    # consumption, where the pointwise certificate fails open; fail
    # open too.
    iszero(q_slack) && return 0.0
    (isfinite(q_slack) && q_slack >= floatmin(Float64)) || return NaN
    (isfinite(q_tight) && q_tight >= floatmin(Float64)) || return NaN
    m = _material_envelope(func, q_slack, d, p.alpha, recipient)
    (isfinite(m) && m >= floatmin(Float64)) || return NaN
    closest = clamp(p.N_theta, lo, hi)
    dz = closest - p.N_theta
    z_min = p.conformism * (config.w_transfer * (dz * dz))
    isfinite(z_min) || return NaN
    e_min = exp(-z_min)
    (isfinite(e_min) && e_min >= floatmin(Float64)) || return NaN
    bound = m * e_min
    (isfinite(bound) && bound >= floatmin(Float64)) || return NaN
    # Cheap pointwise-parity guard: the largest norm penalty of the
    # slab, at the endpoint farthest from `N_theta`, must keep the
    # pointwise `exp` normal there too (see `_interval_normal_ok` for
    # the material side and the docstring).
    farthest = abs(lo - p.N_theta) >= abs(hi - p.N_theta) ? lo : hi
    dz_far = farthest - p.N_theta
    z_max = p.conformism * (config.w_transfer * (dz_far * dz_far))
    isfinite(z_max) || return NaN
    e_max = exp(-z_max)
    (isfinite(e_max) && e_max >= 2.0 * floatmin(Float64)) || return NaN
    return bound
end

"""
    _interval_normal_ok(lo::Float64, hi::Float64, recipient::Bool, p::AgentPayoffParams, config::UtilityConfig)

Material-side pointwise-parity guard of `_payoff_interval_bound` (see
`ADR-0017`): `true` only when the material envelope at the slab's
smallest consumption is finite and normal (`>= 2 * floatmin`, a
factor-of-two floor against rounding races at the `floatmin`
boundary), and its product with the `exp` of the largest norm penalty
of the slab stays at or above that floor. Material-envelope finiteness
is monotone in the consumption, and the norm factor is largest at the
endpoint farthest from `N_theta`, so the pointwise bound of every
covered transfer is then finite and normal as well. The one exception
is the exact zero-consumption rule: when the whole slab's consumption
range is exactly zero (`iszero(q_slack)`, the same rule as the
`iszero(q_slack)` zero-wage rule of `_payoff_interval_bound` and the
`iszero(q) && return 0.0` rule of the pointwise `_payoff_upper_bound`),
the pointwise certificate certifies the same `-Inf` through that
identical exact rule at every covered transfer (spec-independently,
never consulting the material envelope), so the parity property holds
and `true` is returned without a normal material envelope. A mixed
zero/nonzero range (`q_slack > 0` with `iszero(q_tight)`) does not
qualify and falls through to the fail-open guard below. Evaluated
lazily, only after the slack bound of `_payoff_interval_bound` has
passed its comparison, so the common failing decision never pays for
it. Fail open (`false`) on any non-finite intermediate (see the guards
of `_payoff_upper_bound`). Not a ported NetLogo behavior.
"""
function _interval_normal_ok(
    lo::Float64, hi::Float64, recipient::Bool,
    p::AgentPayoffParams, config::UtilityConfig
)::Bool
    (isfinite(lo) && isfinite(hi) && lo <= hi) || return false
    (hi <= 0.0 || lo >= 0.0) || return false
    (lo < 0.0 || hi > 0.0) || return false
    (isfinite(p.wage_self) && p.wage_self >= 0.0) || return false
    (isfinite(p.wage_spouse) && p.wage_spouse >= 0.0) || return false
    (isfinite(p.alpha) && 0.0 <= p.alpha <= 1.0) || return false
    (isfinite(p.conformism) && p.conformism >= 0.0) || return false
    (isfinite(p.N_theta) && isfinite(config.w_transfer) && config.w_transfer >= 0.0) || return false
    func = config.func
    if func isa CES
        (isfinite(func.beta) && func.beta >= CES_CERT_MIN_BETA) || return false
    end
    r_min = min(abs(lo), abs(hi))
    r_max = max(abs(lo), abs(hi))
    local q_slack::Float64
    local q_tight::Float64
    local d::Float64
    if recipient
        q_slack = max(p.wage_self, r_max * p.wage_spouse)
        q_tight = max(p.wage_self, r_min * p.wage_spouse)
        d = 2.0
    else
        q_slack = p.wage_self * (1.0 - r_min)
        q_tight = p.wage_self * (1.0 - r_max)
        d = 1.0
    end
    # Exact zero-consumption parity rule: the same rule as the
    # `iszero(q_slack)` zero-wage rule of `_payoff_interval_bound` and
    # the `iszero(q) && return 0.0` rule of the pointwise
    # `_payoff_upper_bound`. A pure-zero consumption range over the
    # whole slab (`iszero(q_slack)`, which forces `iszero(q_tight)`)
    # makes the computed utility exactly `-Inf` at every transfer by
    # `individual_utility`'s `x <= 0` guard (IEEE rounding is monotone),
    # and the pointwise certificate certifies the same `-Inf` through
    # the identical exact rule at every covered transfer without ever
    # consulting the material envelope, so the pointwise-parity
    # property holds spec-independently here and no normal material
    # envelope is needed. A MIXED zero/nonzero range (`q_slack > 0`
    # with `iszero(q_tight)`) falls through to the guard below and
    # fails open: the pointwise certificate certifies only the
    # exactly-zero transfers there, not the whole slab, so parity
    # genuinely fails (and `_payoff_interval_bound` already returns
    # `NaN` for it).
    iszero(q_slack) && return true
    (isfinite(q_tight) && q_tight >= floatmin(Float64)) || return false
    m_tight = _material_envelope(func, q_tight, d, p.alpha, recipient)
    (isfinite(m_tight) && m_tight >= 2.0 * floatmin(Float64)) || return false
    farthest = abs(lo - p.N_theta) >= abs(hi - p.N_theta) ? lo : hi
    dz_far = farthest - p.N_theta
    z_max = p.conformism * (config.w_transfer * (dz_far * dz_far))
    isfinite(z_max) || return false
    e_max = exp(-z_max)
    (isfinite(e_max) && e_max >= 2.0 * floatmin(Float64)) || return false
    return m_tight * e_max >= 2.0 * floatmin(Float64)
end

"""
    _objective_interval_prunable(lo::Float64, hi::Float64, uw_out::Float64, um_out::Float64, pw::AgentPayoffParams, pm::AgentPayoffParams, config::UtilityConfig)

Sound interval-exclusion certificate of the payoff-only transfer
objective (see `ADR-0017`): `true` only when EVERY transfer of the
closed interval `[lo, hi]` has computed Nash payoff exactly `-Inf`.
Fails open (`false`) on any doubt. `[lo, hi]` is split at zero: the
zero point (both signed zeros) is a payer point for both partners under
the strict `relevant_transfer < 0` test of `individual_utility`, so it
is excluded only when the pointwise `_objective_prunable` would exclude
it, never through the interval path alone. Each nonzero-sign slab is
certified per partner through `_payoff_interval_bound` with the
`OBJECTIVE_CERT_MARGIN` comparison strict against the partner's outside
option (`uw_out` for the woman `pw`, `um_out` for the man `pm`); the
payer is tested first and the recipient envelope is skipped when the
payer certifies. One partner suffices because `nash_product` needs both
gains non-negative. A gain of exactly zero (including signed zeros)
yields the finite payoff `0.0`, so equality with an outside option
never excludes; a `NaN` gain is never a permission to certify on an
unproved bound. Fails open on non-finite or out-of-range inputs
(`lo > hi`, outside `[-1, 1]`), non-finite outside options, and every
fail-open bound (see `ADR-0015` discipline: normal-range and
intermediate guards, CES `beta >= CES_CERT_MIN_BETA` safe band,
zero-wage rules, unknown-`UtilitySpec` fallback). The certificate is
sound per point: wherever it returns `true`, the pointwise
`_objective_prunable` is `true` as well, so a slab-prefiltered sample
keeps its exact cached `-Inf` sentinel and the solve count is
unchanged. Pointwise parity is established either through the
tight-corner guards plus the material-side `_interval_normal_ok`, or
through the exact zero-consumption rule alone: when a partner's
consumption range over the whole slab is exactly zero
(`iszero(q_slack)`), the pointwise `_payoff_upper_bound` returns the
same exact `0.0` bound through its own `iszero(q) && return 0.0` rule
at every covered transfer (never consulting the material envelope), so
the identical strict `0.0 < outside` comparison certifies on both
sides, spec-independently (see `_interval_normal_ok`); mixed
zero/nonzero consumption ranges fail open on both paths. To that end
the comparison is inflated by the
`OBJECTIVE_CERT_MARGIN` twice: once for the Float64 bound error of
`ADR-0015`, once to absorb the rounding slack between the slab bound
and the pointwise bound at a covered transfer (a few ulps of the
per-spec envelope), so the pointwise strict comparison certifies
everywhere the interval one does. Used only as a Stage A prefilter of
objective calls inside `bargain_transfer`'s payoff-only objective,
never on the committed-hours path. Not a ported NetLogo behavior.
"""
function _objective_interval_prunable(
    lo::Float64, hi::Float64, uw_out::Float64, um_out::Float64,
    pw::AgentPayoffParams, pm::AgentPayoffParams, config::UtilityConfig
)::Bool
    (isfinite(lo) && isfinite(hi) && lo <= hi) || return false
    (-1.0 <= lo && hi <= 1.0) || return false
    (isfinite(uw_out) && isfinite(um_out)) || return false
    margin2 = (1.0 + OBJECTIVE_CERT_MARGIN) * (1.0 + OBJECTIVE_CERT_MARGIN)
    if lo <= 0.0 && 0.0 <= hi
        _objective_prunable(0.0, uw_out, um_out, pw, pm, config) || return false
    end
    if lo < 0.0
        # Negative slab: the woman pays, the man receives. The payer is
        # tested first and the recipient envelope is skipped when the
        # payer certifies; the material-side parity guard runs only on
        # a bound that already passed its comparison.
        hi_neg = hi < 0.0 ? hi : 0.0
        bound = _payoff_interval_bound(lo, hi_neg, false, pw, config)
        certified = isfinite(bound) && bound * margin2 < uw_out &&
            _interval_normal_ok(lo, hi_neg, false, pw, config)
        if !certified
            bound = _payoff_interval_bound(lo, hi_neg, true, pm, config)
            certified = isfinite(bound) && bound * margin2 < um_out &&
                _interval_normal_ok(lo, hi_neg, true, pm, config)
        end
        certified || return false
    end
    if hi > 0.0
        # Positive slab: the man pays, the woman receives.
        lo_pos = lo > 0.0 ? lo : 0.0
        bound = _payoff_interval_bound(lo_pos, hi, false, pm, config)
        certified = isfinite(bound) && bound * margin2 < um_out &&
            _interval_normal_ok(lo_pos, hi, false, pm, config)
        if !certified
            bound = _payoff_interval_bound(lo_pos, hi, true, pw, config)
            certified = isfinite(bound) && bound * margin2 < uw_out &&
                _interval_normal_ok(lo_pos, hi, true, pw, config)
        end
        certified || return false
    end
    return true
end

"""
    TransferObjectiveValue

One evaluation of the transfer objective of `bargain_transfer` (see
`MDR-0014` and `ADR-0019`): the utility gains `gain_w` (woman) and
`gain_m` (man) over the outside options, the Nash product `payoff`, and
the labour-equilibrium hours `hw` and `hm` at the evaluated transfer.
The payoff is always the unchanged `nash_product` value of the
`equilibrium_payoff` chain (`MDR-0014`); the gains are recomputed with
`individual_utility` at the solved hours and never used to derive the
payoff. A transfer skipped by the certified `-Inf` objective
(`_objective_prunable`) is recorded with `payoff == -Inf` (soundly equal
to the true objective there) and `NaN` gains and hours; it can never be
committed (see `MDR-0014`). Separate `guidance_w` and `guidance_m` store
solved gains or, for local certified probes, bound gains computed in that
same evaluation (`MDR-0016`, `ADR-0021`). They never rank or commit a point.
"""
struct TransferObjectiveValue
    gain_w::Float64
    gain_m::Float64
    payoff::Float64
    hw::Float64
    hm::Float64
    guidance_w::Float64
    guidance_m::Float64
end

"""
    TransferObjectiveValue(gain_w, gain_m, payoff, hw, hm)

Construct a solved objective record whose guidance equals its utility gains.
Certified local probes instead supply separate bound gains (`ADR-0021`).
"""
TransferObjectiveValue(gain_w, gain_m, payoff, hw, hm) =
    TransferObjectiveValue(gain_w, gain_m, payoff, hw, hm, gain_w, gain_m)

# Production storage hints retained from `ADR-0020` under `ADR-0021`:
# at most `TRANSFER_SEARCH_MAX_EVALS` raw entries including the seed and
# the same number of cache records (the typical production call needs 15).
# The offline discovery search grows the same buffers normally.
const TRANSFER_SAMPLE_CAPACITY = 32
const TRANSFER_CACHE_CAPACITY = 32

"""
    TransferSearchScratch

Task-owned reusable storage of one transfer search (see
`ADR-0017`, `ADR-0019`, and `ADR-0020`): the evaluation cache `cache` of
`TransferObjectiveValue` keyed by the exact transfer (evaluated
transfers only), the sampled sequence `samples` of `(transfer,
payoff)` pairs in enumeration order (every Stage A transfer, pruned or
not, including the exact `-Inf` payoffs of slab-covered samples), the
weak-local-maximum index vector `maxima` of Stage B, and the certified
`-Inf` slab list `slabs` of the interval prefilter. One scratch is
constructed per `Threads.@threads :greedy` chunk body of `set_theta!`
(the `spouse_seen` precedent of `ADR-0015`) and reused across the
households of that chunk through `_reset_scratch!`; it is never indexed
by `Threads.threadid()` and never shared across tasks, so results stay
independent of scheduling and thread count. A scratch never retains a
household's parameters or evaluation closure. The standalone
`bargain_transfer` entry point constructs one per call. Production uses
small capacity hints; the explicit discovery mode grows them as needed.
"""
struct TransferSearchScratch
    cache::Dict{Float64,TransferObjectiveValue}
    samples::Vector{Tuple{Float64,Float64}}
    maxima::Vector{Int}
    slabs::Vector{Tuple{Float64,Float64}}
end

"""
    TransferSearchScratch(cache::Dict{Float64,TransferObjectiveValue})

Wrap a caller-owned evaluation cache into a `TransferSearchScratch`
with fresh side vectors (the entry point of the cache-probing tests of
`test/test_transfer_search.jl`, which own and inspect the cache).
"""
function TransferSearchScratch(cache::Dict{Float64,TransferObjectiveValue})
    return TransferSearchScratch(cache, Tuple{Float64,Float64}[], Int[], Tuple{Float64,Float64}[])
end

"""
    TransferSearchScratch()

Fresh `TransferSearchScratch` with capacity-hinted storage: the cache
is `sizehint!`ed to `TRANSFER_CACHE_CAPACITY` and the sampled sequence
to `TRANSFER_SAMPLE_CAPACITY`, so the common search never grows
either. Emptying keeps the allocated capacity, so a reused scratch
only grows when a household needs an exceptional evaluation count (see
`ADR-0017` and `ADR-0019`).
"""
function TransferSearchScratch()
    cache = sizehint!(Dict{Float64,TransferObjectiveValue}(), TRANSFER_CACHE_CAPACITY)
    samples = sizehint!(Tuple{Float64,Float64}[], TRANSFER_SAMPLE_CAPACITY)
    return TransferSearchScratch(cache, samples, Int[], Tuple{Float64,Float64}[])
end

"""
    _reset_scratch!(scratch::TransferSearchScratch)

Prepare one `TransferSearchScratch` for the next household: empty the
evaluation cache and the side vectors (keeping their allocated
capacity) and re-apply the capacity hint without shrinking. Drops every
cached evaluation of the previous household; nothing of it survives
into the next search (see `ADR-0017`).
"""
function _reset_scratch!(scratch::TransferSearchScratch)
    empty!(scratch.cache)
    sizehint!(scratch.cache, TRANSFER_CACHE_CAPACITY; shrink=false)
    empty!(scratch.samples)
    empty!(scratch.maxima)
    empty!(scratch.slabs)
    return nothing
end

"""
    _transfer_eval!(cache::Dict{Float64,TransferObjectiveValue}, evaluate!::F, theta::Float64) where {F}

Cached evaluation of the staged transfer search (see `MDR-0014` and
`ADR-0019`): return the cached `TransferObjectiveValue` at the exact
transfer `theta` when present, otherwise evaluate it with `evaluate!`
and record it in `cache`. The cache belongs to one `bargain_transfer`
call, so every sampled, refined, and committed transfer is evaluated at
most once. Returns the `TransferObjectiveValue`.
"""
function _transfer_eval!(
    cache::Dict{Float64,TransferObjectiveValue}, evaluate!::F, theta::Float64
)::TransferObjectiveValue where {F}
    cached = get(cache, theta, nothing)
    cached === nothing || return cached
    entry = evaluate!(theta)
    cache[theta] = entry
    return entry
end

"""
    _transfer_covered(slabs::Vector{Tuple{Float64,Float64}}, theta::Float64) -> Bool

Certified-slab membership test of the Stage A prefilter of
`_transfer_search!` (see `ADR-0017`): `true` when `theta` lies in one
of the closed intervals of `slabs`, each certified by
`_objective_interval_prunable` to hold only transfers with computed
Nash payoff exactly `-Inf`. The zero point is never inside a slab (the
partition splits at zero), so it always falls through to the pointwise
path.
"""
function _transfer_covered(slabs::Vector{Tuple{Float64,Float64}}, theta::Float64)::Bool
    for (lo, hi) in slabs
        lo <= theta <= hi && return true
    end
    return false
end

"""
    _transfer_sample!(cache::Dict{Float64,TransferObjectiveValue}, samples::Vector{Tuple{Float64,Float64}}, slabs::Vector{Tuple{Float64,Float64}}, evaluate!::F, theta::Float64) where {F}

Cached Stage A sample evaluation of `_transfer_search!` (see
`MDR-0014` and `ADR-0019`): the cached `TransferObjectiveValue` at the
exact transfer `theta` when present, otherwise one `evaluate!` call,
prefiltered by the certified slabs `slabs` (a covered transfer is
recorded with the exact `-Inf` payoff the pointwise certificate would
return and `evaluate!` is never called). Every Stage A transfer, pruned
or not, is appended to the sampled sequence `samples` as a `(transfer,
payoff)` pair (duplicate enumeration entries are collapsed when the
sequence is sorted; deleting an infeasible neighbour would enlarge a
finite maximum's Brent bracket and change probes and results), but only
evaluated entries enter the cache: slab-covered samples are uniform
`-Inf` sentinels that no later stage reads from the cache (a Stage B
probe at one re-certifies through `evaluate!` to the identical `-Inf`).
Returns the `TransferObjectiveValue`.
"""
function _transfer_sample!(
    cache::Dict{Float64,TransferObjectiveValue}, samples::Vector{Tuple{Float64,Float64}},
    slabs::Vector{Tuple{Float64,Float64}}, evaluate!::F, theta::Float64
)::TransferObjectiveValue where {F}
    if haskey(cache, theta)
        push!(samples, (theta, cache[theta].payoff))
        return cache[theta]
    end
    if _transfer_covered(slabs, theta)
        push!(samples, (theta, -Inf))
        return TransferObjectiveValue(NaN, NaN, -Inf, NaN, NaN)
    end
    entry = evaluate!(theta)
    cache[theta] = entry
    push!(samples, (theta, entry.payoff))
    return entry
end

# Stop splitting a slab candidate below this many grid samples (see
# `ADR-0017`): one `_objective_interval_prunable` decision costs about
# one to two pointwise `_objective_prunable` decisions (one envelope
# per partner on the failing path, the payer first), and a split adds
# two such decisions per level while its samples fall back to pointwise
# evaluation at the leaves; measured on the `ws_500` workload, the
# probe overhead dominates below about 32 samples per leaf while the
# certifiable tail slabs are found at coarse bisection levels either
# way, so the floor is set at the measured break-even.
const TRANSFER_SLAB_MIN_SAMPLES = 32

"""
    _transfer_cover_slabs!(slabs::Vector{Tuple{Float64,Float64}}, lo::Float64, hi::Float64, spacing::Float64, slab_prunable)

Adaptive bisection partitioning one Stage A grid run of extent
`[lo, hi]` and grid spacing `spacing` into certified `-Inf` slabs (see
`ADR-0017`). The range is split at zero first (the zero point is a
payer point for both partners and is left to the pointwise path);
ranges already covered by a recorded slab are skipped; ranges holding
fewer than `TRANSFER_SLAB_MIN_SAMPLES` grid samples are left to
pointwise evaluation; the remaining range is certified whole when the
interval certificate `slab_prunable(lo, hi)` holds and bisected
otherwise. Certified closed intervals are appended to `slabs`. Nothing
is evaluated here: the slabs only prefilter the objective calls of the
Stage A enumeration loops.
"""
function _transfer_cover_slabs!(
    slabs::Vector{Tuple{Float64,Float64}}, lo::Float64, hi::Float64,
    spacing::Float64, slab_prunable
)
    lo < hi || return nothing
    if lo < 0.0 < hi
        _transfer_cover_slabs!(slabs, lo, prevfloat(0.0), spacing, slab_prunable)
        _transfer_cover_slabs!(slabs, nextfloat(0.0), hi, spacing, slab_prunable)
        return nothing
    end
    for (slab_lo, slab_hi) in slabs
        (slab_lo <= lo && hi <= slab_hi) && return nothing
    end
    (hi - lo) <= (TRANSFER_SLAB_MIN_SAMPLES - 1) * spacing && return nothing
    if slab_prunable(lo, hi)::Bool
        push!(slabs, (lo, hi))
        return nothing
    end
    mid = lo + 0.5 * (hi - lo)
    (mid <= lo || mid >= hi) && return nothing
    _transfer_cover_slabs!(slabs, lo, mid, spacing, slab_prunable)
    _transfer_cover_slabs!(slabs, mid, hi, spacing, slab_prunable)
    return nothing
end

"""
    _transfer_prepare_slabs!(slabs::Vector{Tuple{Float64,Float64}}, slab_prunable, theta0::Float64)

Certified-slab partition of every Stage A grid run of `_transfer_search!`
(see `ADR-0017` and `MDR-0014`): the fine anchor windows of `0.0` and
`theta0` at spacing `TRANSFER_FINE_STEP` and the coarse grid at spacing
`TRANSFER_COARSE_STEP`, each with the adaptive bisection of
`_transfer_cover_slabs!`. Does nothing when `slab_prunable` is `nothing`
(the cache-probing test entry point without a household). Returns
nothing.
"""
function _transfer_prepare_slabs!(slabs::Vector{Tuple{Float64,Float64}}, slab_prunable, theta0::Float64)
    slab_prunable === nothing && return nothing
    for anchor in (0.0, theta0)
        lo = max(anchor - TRANSFER_FINE_STEPS * TRANSFER_FINE_STEP, -1.0)
        hi = min(anchor + TRANSFER_FINE_STEPS * TRANSFER_FINE_STEP, 1.0)
        _transfer_cover_slabs!(slabs, lo, hi, TRANSFER_FINE_STEP, slab_prunable)
    end
    _transfer_cover_slabs!(slabs, -1.0, 1.0, TRANSFER_COARSE_STEP, slab_prunable)
    return nothing
end

"""
    _transfer_better(theta::Float64, payoff::Float64, best_theta::Float64, best_payoff::Float64, theta0::Float64) -> Bool

Candidate comparison of the staged transfer search (see `MDR-0014`):
`true` exactly when `(theta, payoff)` beats `(best_theta, best_payoff)`.
The order is the largest payoff first; an exact payoff tie is broken by
the smallest `abs(theta - theta0)`, then the smallest `theta`. The first
candidate is compared against the empty best `(NaN, -Inf)` and wins
because every finite payoff beats `-Inf`. The comparison is total over
distinct transfers, so the result does not depend on cache iteration
order.
"""
function _transfer_better(
    theta::Float64, payoff::Float64, best_theta::Float64, best_payoff::Float64, theta0::Float64
)::Bool
    payoff != best_payoff && return payoff > best_payoff
    distance = abs(theta - theta0)
    best_distance = abs(best_theta - theta0)
    distance != best_distance && return distance < best_distance
    return theta < best_theta
end

"""
    _transfer_search!(scratch::TransferSearchScratch, slab_prunable, evaluate!::F, theta0::Float64, tol::Float64) -> Float64 where {F}

Staged feasibility-discovery transfer search of `bargain_transfer` (see
`MDR-0014` and `ADR-0019`), driven entirely through the task-owned
scratch `scratch` and the evaluation function `evaluate!`, which
returns one `TransferObjectiveValue` per transfer. Stage A evaluates
the tiered set of `MDR-0014` in deterministic order (anchors `-1.0`,
`0.0`, `theta0`, `+1.0`; then the fine anchor windows `anchor + k *
TRANSFER_FINE_STEP` and `anchor - k * TRANSFER_FINE_STEP` for `k =
1:TRANSFER_FINE_STEPS` around `0.0` and `theta0`, clipped to `[-1,
1]`; then the coarse grid `-1.0:TRANSFER_COARSE_STEP:1.0` ascending),
deduplicated through the cache and the sort-time collapse of the
sampled sequence. The sampled transfers are appended to
`scratch.samples` in enumeration order as `(transfer, payoff)` pairs,
pruned or not, so the sampled sequence is complete; Stage B sorts it
once and collapses duplicate transfers (`isequal` semantics, signed
zeros stay distinct). The optional interval prefilter `slab_prunable`
(a `nothing`, or a function `(lo, hi) -> Bool` wrapping
`_objective_interval_prunable` for the household) partitions the Stage
A grid runs into certified `-Inf` slabs before the enumeration
(adaptive bisection, `_transfer_prepare_slabs!`); a covered sample is
recorded with its exact `-Inf` payoff in the sampled sequence without
an `evaluate!` call and without a cache entry (its key stays in the
sampled sequence; deleting an infeasible neighbour would enlarge a
finite maximum's Brent bracket and change probes and results). The
status-quo entry stays independently seeded, and the pointwise
`_objective_prunable` inside `evaluate!` covers the uncovered samples
and every Stage B probe. Stage B marks every sampled point whose
payoff is finite and `>=` both neighbours' payoffs a weak local
maximum (a domain boundary compares its one neighbour, an isolated
finite point qualifies), refines one member per plateau of adjacent
equal-payoff weak maxima (the member with the smallest `abs(theta -
theta0)`, then smallest `theta`; every plateau member stays a
candidate) with a bounded `maximize_1d` run of argument tolerance
`tol` on the bracket of its previous and next distinct sampled
transfers, clamped to `[-1, 1]` (one-sided at the domain boundaries),
and returns the best cached candidate under the tie rule of
`_transfer_better`: every cached evaluation with finite payoff,
sampled points and refinement results alike. Every evaluation inside
the refinement brackets goes through `_transfer_eval!`, so the
refinement result is a cached candidate by construction. Returns the
best transfer, or `NaN` when no cached payoff is finite. The caller
seeds the cache at `theta0` with the status-quo evaluation before
calling (see `MDR-0014`).
"""
function _transfer_search!(
    scratch::TransferSearchScratch, slab_prunable, evaluate!::F,
    theta0::Float64, tol::Float64
)::Float64 where {F}
    cache = scratch.cache
    samples = scratch.samples
    maxima = scratch.maxima
    slabs = scratch.slabs
    # The sampled sequence starts from every pre-seeded key (the
    # status quo) and keeps every Stage A sample of this call.
    empty!(samples)
    for (theta, entry) in cache
        push!(samples, (theta, entry.payoff))
    end
    empty!(maxima)
    empty!(slabs)
    _transfer_prepare_slabs!(slabs, slab_prunable, theta0)
    # Stage A: the tiered evaluation set of `MDR-0014`, anchors first,
    # then the fine anchor windows, then the coarse grid; the cache and
    # the sort-time collapse deduplicate overlaps (theta0 often
    # coincides with an anchor or a grid point).
    _transfer_sample!(cache, samples, slabs, evaluate!, -1.0)
    _transfer_sample!(cache, samples, slabs, evaluate!, 0.0)
    _transfer_sample!(cache, samples, slabs, evaluate!, theta0)
    _transfer_sample!(cache, samples, slabs, evaluate!, 1.0)
    for anchor in (0.0, theta0)
        for k in 1:TRANSFER_FINE_STEPS
            _transfer_sample!(
                cache, samples, slabs, evaluate!, clamp(anchor + k * TRANSFER_FINE_STEP, -1.0, 1.0)
            )
            _transfer_sample!(
                cache, samples, slabs, evaluate!, clamp(anchor - k * TRANSFER_FINE_STEP, -1.0, 1.0)
            )
        end
    end
    for theta in -1.0:TRANSFER_COARSE_STEP:1.0
        _transfer_sample!(cache, samples, slabs, evaluate!, theta)
    end
    # Stage B: sort the sampled sequence once and collapse duplicate
    # transfers (exact `isequal` semantics: `-0.0` and `+0.0` stay
    # distinct), then weak local maxima of the sampled payoffs, one
    # bounded refinement per equal-payoff plateau (see `MDR-0014`).
    sort!(samples)
    nraw = length(samples)
    n = 0
    for i in 1:nraw
        if n == 0 || !isequal(samples[n][1], samples[i][1])
            n += 1
            samples[n] = samples[i]
        end
    end
    resize!(samples, n)
    for i in 1:n
        payoff = samples[i][2]
        isfinite(payoff) || continue
        i == 1 || payoff >= samples[i - 1][2] || continue
        i == n || payoff >= samples[i + 1][2] || continue
        push!(maxima, i)
    end
    objective(theta) = _transfer_eval!(cache, evaluate!, theta).payoff
    plateau_start = 1
    while plateau_start <= length(maxima)
        plateau_end = plateau_start
        while plateau_end < length(maxima) &&
            maxima[plateau_end + 1] == maxima[plateau_end] + 1 &&
            samples[maxima[plateau_end + 1]][2] == samples[maxima[plateau_start]][2]
            plateau_end += 1
        end
        # The plateau member closest to the status quo refines; equal
        # payoffs make `_transfer_better` apply the distance-then-theta
        # rule of `MDR-0014`.
        refined = maxima[plateau_start]
        for mi in (plateau_start + 1):plateau_end
            m = maxima[mi]
            if _transfer_better(
                samples[m][1], samples[m][2],
                samples[refined][1], samples[refined][2], theta0,
            )
                refined = m
            end
        end
        lo = clamp(refined == 1 ? samples[refined][1] : samples[refined - 1][1], -1.0, 1.0)
        hi = clamp(refined == n ? samples[refined][1] : samples[refined + 1][1], -1.0, 1.0)
        maximize_1d(objective, lo, hi, tol)
        plateau_start = plateau_end + 1
    end
    # Candidate selection over every cached finite payoff with the tie
    # rule of `MDR-0014` (the empty best `(NaN, -Inf)` loses to the
    # first finite candidate).
    best_theta = NaN
    best_payoff = -Inf
    for theta in keys(cache)
        entry = cache[theta]
        isfinite(entry.payoff) || continue
        if _transfer_better(theta, entry.payoff, best_theta, best_payoff, theta0)
            best_theta = theta
            best_payoff = entry.payoff
        end
    end
    return best_theta
end

"""
    _transfer_search!(cache::Dict{Float64,TransferObjectiveValue}, evaluate!::F, theta0::Float64, tol::Float64) -> Float64 where {F}

Caller-owned-cache entry point of `_transfer_search!` for the
cache-probing search-contract tests (`test/test_transfer_search.jl`,
`test/test_bargaining_equivalence.jl`): wraps `cache` in a transient
`TransferSearchScratch` and runs the same staged search without an
interval prefilter (no household parameters are available here), so
every sample goes through `evaluate!` exactly as before `ADR-0017`.
Returns the best transfer (see `_transfer_search!`).
"""
function _transfer_search!(
    cache::Dict{Float64,TransferObjectiveValue}, evaluate!::F,
    theta0::Float64, tol::Float64
)::Float64 where {F}
    scratch = TransferSearchScratch(cache)
    return _transfer_search!(scratch, nothing, evaluate!, theta0, tol)
end

"""
    _transfer_local_search!(scratch::TransferSearchScratch, evaluate!::F, theta0::Float64, tol::Float64) -> Float64 where {F}

Feasibility-guided production search of `MDR-0016` / `ADR-0021`
(NetLogo `set-theta`, ODD section Transfer bargaining). The caller seeds
`scratch.cache` only at `theta0` with the status-quo evaluation. Stage A
samples the four anchors, then the fixed `TRANSFER_EXPLORE_OFFSETS` ladder
on both sides of the anchor `0.0` (both anchors when `abs(theta0) >
TRANSFER_ANCHOR_OVERLAP`, otherwise one ladder only), then the adaptive
`TRANSFER_ADAPTIVE_OFFSET` probe on exactly those sides where guidance at
`+/- 0.001` is `>= TRANSFER_GUIDANCE_MIN` and strictly exceeds guidance at
`+/- 0.0001`; all clipped to the domain and deduplicated through the cache.
No interval slabs or full-domain grid are constructed. Every requested
evaluation is cached exactly once.

Guidance is the minimum of `guidance_w / scale_w` and `guidance_m /
scale_m` (non-finite values worst): true stored gains at solved probes and
certified bound gains at pruned probes (`MDR-0016`). Stage B sorts the
sampled transfers, collapses equal-guidance weak-maximum plateaus nearest
to status (the exact both-zero-gain zero point never refines but stays a
candidate), and refines the top `TRANSFER_GUIDANCE_REFINEMENTS` peaks with
seeded Brent over their sampled-neighbour brackets on the guidance. Stage C
runs only when a cached finite payoff strictly beats the status quo, and
refines the top `TRANSFER_MAX_REFINEMENTS` strictly improving candidates
with seeded Brent on the true payoff over their sampled-neighbour brackets;
no-band households cost zero Stage C probes. Each refinement has at most
`TRANSFER_REFINE_MAX_ITER` iteration probes. Keep every finite cached
sample and refinement probe as a candidate, including unrefined peaks.
There are at most `TRANSFER_SEARCH_MAX_EVALS` distinct objective records
including the seed; budget exhaustion never creates a fabricated infeasible
value.

Returns the best cached transfer, or `NaN` if none has finite payoff: the
best candidate found within the record budget, not a global optimum.
Remote bands between probes can be missed; failed local probes do not
certify global infeasibility. The caller applies the strict commit rule.
"""
function _transfer_local_search!(
    scratch::TransferSearchScratch, evaluate!::F, theta0::Float64, tol::Float64;
    scale_w::Float64=1.0, scale_m::Float64=1.0
)::Float64 where {F}
    cache = scratch.cache
    samples = scratch.samples
    maxima = scratch.maxima
    slabs = scratch.slabs
    status_payoff = cache[theta0].payoff
    function sample(theta::Float64)
        cached = get(cache, theta, nothing)
        cached === nothing || return cached
        entry = evaluate!(theta)
        cache[theta] = entry
        push!(samples, (theta, entry.payoff))
        return entry
    end
    guidance(theta) = begin
        entry = _transfer_eval!(cache, evaluate!, theta)
        value = min(entry.guidance_w / scale_w, entry.guidance_m / scale_m)
        isfinite(value) ? value : -Inf
    end
    empty!(samples)
    push!(samples, (theta0, status_payoff))
    empty!(maxima)
    empty!(slabs)
    for theta in (-1.0, 0.0, theta0, 1.0)
        sample(theta)
    end
    anchors = abs(theta0) <= TRANSFER_ANCHOR_OVERLAP ? (0.0,) : (0.0, theta0)
    for anchor in anchors, offset in TRANSFER_EXPLORE_OFFSETS
        sample(clamp(anchor + offset, -1.0, 1.0))
        sample(clamp(anchor - offset, -1.0, 1.0))
    end
    for anchor in anchors, sign in (1.0, -1.0)
        outer = clamp(anchor + sign * 0.001, -1.0, 1.0)
        inner = clamp(anchor + sign * 0.0001, -1.0, 1.0)
        if guidance(outer) >= TRANSFER_GUIDANCE_MIN && guidance(outer) > guidance(inner)
            sample(clamp(anchor + sign * TRANSFER_ADAPTIVE_OFFSET, -1.0, 1.0))
        end
    end
    sort!(samples)
    n = 0
    for i in eachindex(samples)
        if n == 0 || !isequal(samples[n][1], samples[i][1])
            n += 1
            samples[n] = samples[i]
        end
    end
    resize!(samples, n)
    # Guidance changes probe placement only, never the cached Nash payoff.
    for i in 1:n
        samples[i] = (samples[i][1], guidance(samples[i][1]))
    end
    for i in 1:n
        payoff = samples[i][2]
        isfinite(payoff) || continue
        payoff >= TRANSFER_GUIDANCE_MIN || continue
        entry = cache[samples[i][1]]
        samples[i][1] === 0.0 && entry.guidance_w == 0.0 && entry.guidance_m == 0.0 && continue
        left = i == 1 || !isfinite(samples[i - 1][2]) ? -Inf : samples[i - 1][2]
        right = i == n || !isfinite(samples[i + 1][2]) ? -Inf : samples[i + 1][2]
        payoff >= left && payoff >= right && push!(maxima, i)
    end
    # Collapse plateaus in place before ranking. Every original sample stays
    # in the cache even when its peak receives no refinement budget.
    plateau_start = 1
    representatives = 0
    while plateau_start <= length(maxima)
        plateau_end = plateau_start
        while plateau_end < length(maxima) &&
            maxima[plateau_end + 1] == maxima[plateau_end] + 1 &&
            samples[maxima[plateau_end + 1]][2] == samples[maxima[plateau_start]][2]
            plateau_end += 1
        end
        refined = maxima[plateau_start]
        for mi in (plateau_start + 1):plateau_end
            m = maxima[mi]
            if _transfer_better(
                samples[m][1], samples[m][2], samples[refined][1], samples[refined][2], theta0
            )
                refined = m
            end
        end
        representatives += 1
        maxima[representatives] = refined
        plateau_start = plateau_end + 1
    end
    resize!(maxima, representatives)
    sort!(maxima; lt=(i, j) -> _transfer_better(
        samples[i][1], samples[i][2], samples[j][1], samples[j][2], theta0
    ))
    for mi in 1:min(length(maxima), TRANSFER_GUIDANCE_REFINEMENTS)
        refined = maxima[mi]
        lo = refined == 1 ? samples[refined][1] : samples[refined - 1][1]
        hi = refined == n ? samples[refined][1] : samples[refined + 1][1]
        lo < hi || continue
        _brent_maximize(guidance, lo, hi, tol, TRANSFER_REFINE_MAX_ITER, samples[refined][1])
    end
    best_theta = NaN
    best_payoff = -Inf
    for (theta, entry) in cache
        isfinite(entry.payoff) || continue
        if _transfer_better(theta, entry.payoff, best_theta, best_payoff, theta0)
            best_theta = theta
            best_payoff = entry.payoff
        end
    end
    best_payoff > status_payoff || return best_theta
    # Stage C includes every Stage B probe. Rebuild neighbour brackets from
    # actual cached records, not invented payoff values at unvisited points.
    empty!(samples)
    for (theta, entry) in cache
        push!(samples, (theta, entry.payoff))
    end
    sort!(samples)
    n = length(samples)
    empty!(maxima)
    for i in 1:n
        isfinite(samples[i][2]) && samples[i][2] > status_payoff && push!(maxima, i)
    end
    sort!(maxima; lt=(i, j) -> _transfer_better(
        samples[i][1], samples[i][2], samples[j][1], samples[j][2], theta0
    ))
    objective(theta) = _transfer_eval!(cache, evaluate!, theta).payoff
    for mi in 1:min(length(maxima), TRANSFER_MAX_REFINEMENTS)
        refined = maxima[mi]
        lo = samples[max(1, refined - 1)][1]
        hi = samples[min(n, refined + 1)][1]
        lo < hi || continue
        _brent_maximize(objective, lo, hi, tol, TRANSFER_REFINE_MAX_ITER, samples[refined][1])
    end
    best_theta = NaN
    best_payoff = -Inf
    for (theta, entry) in cache
        isfinite(entry.payoff) || continue
        if _transfer_better(theta, entry.payoff, best_theta, best_payoff, theta0)
            best_theta = theta
            best_payoff = entry.payoff
        end
    end
    return best_theta
end

"""
    _transfer_local_search!(cache::Dict{Float64,TransferObjectiveValue}, evaluate!::F, theta0::Float64, tol::Float64) -> Float64 where {F}

Caller-owned-cache entry point of `_transfer_local_search!` for production
contract tests. Wrap the cache, seeded only at `theta0`, in temporary
scratch and run the identical bounded local driver. Returns the best
cached transfer (see `MDR-0016`, `ADR-0021`).
"""
function _transfer_local_search!(
    cache::Dict{Float64,TransferObjectiveValue}, evaluate!::F,
    theta0::Float64, tol::Float64
)::Float64 where {F}
    return _transfer_local_search!(TransferSearchScratch(cache), evaluate!, theta0, tol)
end

"""
    bargain_transfer(scratch::TransferSearchScratch, hw_init::Float64, hm_init::Float64, theta_init::Float64, pw::AgentPayoffParams, pm::AgentPayoffParams, config::UtilityConfig; tol::Float64 = TRANSFER_REFINE_TOL, search::Symbol = :local)

Transfer bargain of one household: bounded feasibility-guided search
of the `calculate-payoff` Nash product over `[-1, 1]`
through the task-owned evaluation cache of `TransferObjectiveValue`
(`_transfer_local_search!`, see `MDR-0016` and `ADR-0021`). Port of NetLogo
`set-theta` with NetLogo `calculate-payoff` (ODD section Transfer
bargaining (`set-theta`, `calculate-payoff`)); the objective is
unchanged and the local search is a numerical device replacing
NetLogo's two +/-0.001 hill-climbs. `search=:discovery` explicitly selects
the retained full-domain staged validation search of `MDR-0014`; no automatic
global fallback occurs in production. Other modes are rejected. The `scratch` is
reset by this call (`_reset_scratch!`) and never retains anything of
the household; `set_theta!` reuses one scratch per `Threads.@threads
:greedy` chunk body (see `ADR-0017`). The status quo is evaluated
first and kept unless a candidate beats it strictly (fixes ODD quirk
3, fallback per `MDR-0014`); every candidate labour solve starts from
the status-quo labour equilibrium; `tol` is the absolute argument
tolerance of the bounded Brent refinement brackets (default
`TRANSFER_REFINE_TOL`, see `MDR-0016`); it must be finite and positive.
The outside-option solve is
reused as the status-quo labour equilibrium exactly when
`clamp(theta_init, -1.0, 1.0) === 0.0`, where the two solves have
identical arguments (see `ADR-0015`). When either outside option is
non-finite, every `nash_product` value is `-Inf` (the gains are never
finite), so the search is skipped after the status-quo solve and the
status fallback is returned directly; the payoff-only objective samples
are certified against `-Inf` by the pointwise `_objective_prunable`
before they run a labour equilibrium. Discovery mode also uses the interval
`_objective_interval_prunable` prefilter (see `ADR-0015` and `ADR-0017`);
neither certificate touches the committed-hours path.
Both optimizations are exact and leave the returned values unchanged.
The committed hours are the cached solve of the committed transfer,
never a re-solve through the certificate. The best candidate is the
largest cached payoff with exactly tied payoffs broken by the smallest
`abs(theta - theta0)`, then the smallest `theta` (see `MDR-0014`).
Returns `(theta, hw, hm)`.
"""
function bargain_transfer(
  scratch::TransferSearchScratch,
  hw_init::Float64, hm_init::Float64, theta_init::Float64,
  pw::AgentPayoffParams, pm::AgentPayoffParams, config::UtilityConfig;
  tol::Float64=TRANSFER_REFINE_TOL, search::Symbol=:local
)
  search in (:local, :discovery) || throw(ArgumentError("search must be :local or :discovery"))
  isfinite(tol) && tol > 0.0 || throw(ArgumentError("tol must be finite and positive"))
  _reset_scratch!(scratch)
  theta0 = clamp(theta_init, -1.0, 1.0)
  # The outside-option solve runs first and doubles as the status-quo
  # labour equilibrium when `theta0` is bitwise `+0.0`: both solves then
  # have identical arguments and one run of the deterministic
  # `mutual_best_response` is reused exactly (see `ADR-0015`). The guard
  # is the strict bitwise `theta0 === 0.0`, never `iszero`, so a signed
  # zero `-0.0` keeps its own status-quo solve. The single assignment
  # site matters: `hw_status` and `hm_status` are captured by the
  # evaluation closure below, and an if/else assignment would box them
  # (see `MDR-0002`).
  hw_out, hm_out = mutual_best_response(hw_init, hm_init, 0.0, pw, pm, config)
  uw_out = individual_utility(hw_out, hm_out, 0.0, pw, config)
  um_out = individual_utility(hm_out, hw_out, 0.0, pm, config)
  hw_status, hm_status = theta0 === 0.0 ? (hw_out, hm_out) :
    mutual_best_response(hw_init, hm_init, theta0, pw, pm, config)
  status_payoff = nash_product(theta0, hw_status, hm_status, uw_out, um_out, pw, pm, config)
  # Non-finite outside options make every `nash_product` value exactly
  # `-Inf` (neither gain is ever finite), so no candidate can beat the
  # status quo and the search would fall back anyway; skip it and return
  # the status fallback directly (see `ADR-0015`).
  if !isfinite(uw_out) || !isfinite(um_out)
    return theta0, hw_status, hm_status
  end
  # One candidate evaluation shared by both searches (see `MDR-0016`): the
  # certified `-Inf` decision first, then the warm-started labour solve, its
  # gains computed exactly once (`_transfer_gains`, the same expressions as
  # `nash_product`), and the unchanged Nash payoff derived from those gains
  # (`_nash_from_gains`, bitwise identical to `equilibrium_payoff`). The
  # closure captures only single-assignment bindings, so nothing is boxed
  # (see `MDR-0002`).
  function evaluate_transfer(theta::Float64)::TransferObjectiveValue
    if search === :local
      bound_w = _payoff_upper_bound(theta, pw, config)
      bound_m = _payoff_upper_bound(theta, pm, config)
      if (isfinite(bound_w) && bound_w * (1.0 + OBJECTIVE_CERT_MARGIN) < uw_out) ||
          (isfinite(bound_m) && bound_m * (1.0 + OBJECTIVE_CERT_MARGIN) < um_out)
        return TransferObjectiveValue(
          NaN, NaN, -Inf, NaN, NaN, bound_w - uw_out, bound_m - um_out
        )
      end
    elseif _objective_prunable(theta, uw_out, um_out, pw, pm, config)
      return TransferObjectiveValue(NaN, NaN, -Inf, NaN, NaN)
    end
    hw, hm = mutual_best_response(hw_status, hm_status, theta, pw, pm, config)
    gain_w, gain_m = _transfer_gains(theta, hw, hm, uw_out, um_out, pw, pm, config)
    return TransferObjectiveValue(gain_w, gain_m, _nash_from_gains(gain_w, gain_m), hw, hm)
  end
  # The cache is seeded at `theta0` with the status-quo evaluation
  # itself, so the comparison base and the current-transfer evaluation
  # are the same entry (see `MDR-0016`); the seeding is independent of
  # the interval prefilter, which never touches it.
  cache = scratch.cache
  gain_w0, gain_m0 = _transfer_gains(theta0, hw_status, hm_status, uw_out, um_out, pw, pm, config)
  cache[theta0] = TransferObjectiveValue(gain_w0, gain_m0, status_payoff, hw_status, hm_status)
  # Stage A interval prefilter of objective calls (see `ADR-0017`): the
  # household-bound closure is built here and passed per call, so the
  # scratch never holds a household's parameters or closures.
  best_theta = if search === :local
    _transfer_local_search!(scratch, evaluate_transfer, theta0, tol;
      scale_w=max(abs(uw_out), 1.0), scale_m=max(abs(um_out), 1.0))
  else
    slab_prunable = (lo::Float64, hi::Float64) ->
      _objective_interval_prunable(lo, hi, uw_out, um_out, pw, pm, config)
    _transfer_search!(scratch, slab_prunable, evaluate_transfer, theta0, tol)
  end
  if isfinite(best_theta)
    best = cache[best_theta]
    if best.payoff > status_payoff
      return best_theta, best.hw, best.hm
    end
  end
  return theta0, hw_status, hm_status
end

"""
    bargain_transfer(hw_init::Float64, hm_init::Float64, theta_init::Float64, pw::AgentPayoffParams, pm::AgentPayoffParams, config::UtilityConfig; tol::Float64 = TRANSFER_REFINE_TOL, search::Symbol = :local)

Standalone entry point of `bargain_transfer` (see `MDR-0016` and
`ADR-0021`): the same selected transfer bargain with a fresh
`TransferSearchScratch` constructed per call. Returns `(theta, hw,
hm)`.
"""
function bargain_transfer(
  hw_init::Float64, hm_init::Float64, theta_init::Float64,
  pw::AgentPayoffParams, pm::AgentPayoffParams, config::UtilityConfig;
  tol::Float64=TRANSFER_REFINE_TOL, search::Symbol=:local
)
  return bargain_transfer(
    TransferSearchScratch(), hw_init, hm_init, theta_init, pw, pm, config; tol=tol, search=search
  )
end

"""
    payoff_params(wage_self::Float64, wage_spouse::Float64, alpha::Float64, conformism::Float64, means, is_woman::Bool)

Transient per-agent parameter bundle of NetLogo `set-theta` (ODD section
Transfer bargaining (`set-theta`, `calculate-payoff`)); the perceived norms
`means` supply `N_h` (own working time), `N_theta` (transfer), and
`N_h_spouse` (spouse working time) (see `MDR-0014` and `ADR-0007`). Returns
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
    set_theta!(world, config::UtilityConfig; search::Symbol = :local)

Household loop of the household bargaining: ports NetLogo `set-theta` for
every household (ODD section Transfer bargaining (`set-theta`,
`calculate-payoff`)); the labour stage runs inside `bargain_transfer` (see
`MDR-0016`). Production defaults to the bounded local search; use
`search=:discovery` only for explicit validation trajectories (`ADR-0021`).
Household components are extracted with `Ark.Query` (see
`ADR-0007`); the transfer component mirrors the wife's value on the man (see
`registry/model/entities.md`). The per-household loop runs with
`Threads.@threads :greedy` over the disjoint households in chunks of
`HOUSEHOLD_BARGAIN_CHUNK` items (the greedy scheduler pulls whole chunks) to
amortize its per-item channel pull, each chunk task with its own
`spouse_seen` scratch vector for `norm_means` and its own
`TransferSearchScratch` for the transfer search, reused across the
households of that chunk and never shared across tasks, so the results
are independent of scheduling and thread count (see `ADR-0014`,
`ADR-0015`, and `ADR-0017`). The world is
mutated and nothing is returned.
"""
function set_theta!(world, config::UtilityConfig; search::Symbol=:local)
  search in (:local, :discovery) || throw(ArgumentError("search must be :local or :discovery"))
  net = Ark.get_resource(world, SocialNetwork)
  properties = Ark.get_resource(world, ModelProperties)
  globals = properties.network isa HomogeneousMixing ? norm_global_means(world, net) : nothing
  women_index = Dict(entity => vertex for (vertex, entity) in enumerate(net.women_entities))
  men_index = Dict(entity => vertex for (vertex, entity) in enumerate(net.men_entities))
  # Upper bound for the `spouse_seen` scratch buffer: `norm_means` pushes at
  # most one distinct spouse per same-sex neighbour, so the maximum vertex
  # degree of the two graphs covers every call (see `ADR-0015`).
  spouse_capacity = max(
    maximum(v -> Graphs.degree(net.women, v), Graphs.vertices(net.women); init=0),
    maximum(v -> Graphs.degree(net.men, v), Graphs.vertices(net.men); init=0),
  )
  component_types = (Wage, WorkingTime, TransferToWoman, Conformism, PreferencePrivate, Spouse)
  for (entities, wages, times, transfers, conformisms, preferences, spouses) in
      Ark.Query(world, component_types; with=(Female,))
    Threads.@threads :greedy for chunk in Iterators.partition(eachindex(entities), HOUSEHOLD_BARGAIN_CHUNK)
      # One scratch buffer per chunk task (one greedy iteration): `norm_means`
      # empties it at the start of its neighbour branch, so reuse across the
      # households of the chunk is exact and the buffer stays task-local (see
      # `ADR-0015`). The capacity hint matches the largest neighbour list it
      # will hold, so no call grows it. The `TransferSearchScratch` is the
      # task-owned transfer-search storage of `ADR-0017`, reused across the
      # households of the chunk the same way and reset by every
      # `bargain_transfer` call.
      spouse_seen = Ark.Entity[]
      sizehint!(spouse_seen, spouse_capacity)
      search_scratch = TransferSearchScratch()
      for f in chunk
        woman = entities[f]
        man = spouses[f].entity
        man_wage, man_time, man_transfer, man_conformism, man_preference =
          Ark.get_components(world, man, (Wage, WorkingTime, TransferToWoman, Conformism, PreferencePrivate))
        woman_vertex = get(women_index, woman, 0)
        woman_vertex == 0 && throw(ArgumentError("woman is not in the women entity vector"))
        man_vertex = get(men_index, man, 0)
        man_vertex == 0 && throw(ArgumentError("man is not in the men entity vector"))

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
          search_scratch, times[f].current, man_time.current, transfers[f].current, pw, pm, config;
          search=search
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
