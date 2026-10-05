# Labour stage of the household bargaining: `mutual_best_response` and
# the 1-D solver `best_response_1d`, ports of the NetLogo `choose-bundle`
# hill-climb step (ODD section Labour best response). Each best response
# starts from the current hours and keeps them when no feasible sample
# exists; eligible utility regimes solve it with the safeguarded
# derivative root solve of `MDR-0017`, and ineligible or failed cases
# run the seeded continuous solver of `MDR-0002` verbatim (see
# `ADR-0022`). Solver constants only, not model parameters. Moved
# unchanged from `src/resources/utility_functions.jl` and
# `src/systems/household_bargaining.jl` by `ADR-0028`.

# Lower end of the CES `beta` band of the derivative best-response
# applicability regime (`MDR-0017`, see `_derivative_applicable` and
# `ADR-0022`): below the floor the solve falls back to the bitwise
# `MDR-0002` seeded search. Same conditioning argument as
# `CES_CERT_MIN_BETA`: the computed utility evaluates `S^(1/beta)` from
# the rounded inner sum `S = alpha * x^beta + (1 - alpha) * Q^beta`,
# whose condition number `1 / beta` amplifies the inner-sum rounding to
# the relative jaggedness `(1 / beta) * n_ops * eps` (`eps = 2^-53`,
# `n_ops = 10` the combined error budget of the two compared objective
# evaluations: two inner powers, two weight multiplies, and one add
# each, each `<= 1` ulp). A certified analytic root of `g` can then sit
# in a computed-utility valley and lose up to that relative amount
# against the legacy Brent sample, violating the computed-utility
# non-degradation of `MDR-0017`. Measured sweep (log grid of `beta` in
# [1.0e-6, 1.0], 4000 random parameter draws per beta over roles,
# wages, transfer, spouse hours, conformism, `alpha`, weights, and
# seeds): the worst relative loss of the derivative result versus the
# legacy result follows about `2.0e-16 / beta`, crossing the `1.0e-11`
# envelope between `beta = 2.0e-5` (1.11e-11) and `2.5e-5` (9.4e-12) and
# measuring 1.5e-13 at `beta = 1.0e-3`. The floor is taken at the
# `CES_CERT_MIN_BETA` decade, where the analytic bound (1.1e-12) and
# the measured worst loss both sit an order of magnitude inside the
# `1.0e-11` non-degradation envelope; at the measured crossing a
# finite-sample worst case would certify with zero margin. The value
# coincides with `CES_CERT_MIN_BETA` at the current budgets but is
# stated separately: the two floors serve different envelopes (the
# `OBJECTIVE_CERT_MARGIN` certificate bound versus the `1.0e-11`
# non-degradation target) and move independently. No upper bound is
# needed: for `beta >= 1` the exponent `1 / beta <= 1` contracts rather
# than amplifies rounding.
const CES_DERIVATIVE_MIN_BETA = 1.0e-3

# Absolute argument tolerance of the seeded best-response search: the NetLogo
# `current-delta` resolution (see `MDR-0002`).
const BEST_RESPONSE_TOL = 1.0e-4
# Half-width of the seeded best-response window around the current hours (see
# `MDR-0002`).
const BEST_RESPONSE_WINDOW = 5.0e-2

"""
    best_response_1d(U::F, h_start::Float64) where {F}

Own working time on `[0, 1]` for one partner, seeded at the current hours
`h_start`: `maximize_1d` of the own-utility closure `U` on `[0, 1]` with
`BEST_RESPONSE_TOL` (the NetLogo `current-delta`) in the window
`BEST_RESPONSE_WINDOW` around the seed. Port of the NetLogo `choose-bundle`
hill-climb step (ODD section Labour best response); the seeded continuous
search replaces the `Optim.Brent` call of the first port (see `MDR-0002`).
Returns the best feasible hours, or `NaN` when no feasible sample exists.
This generic method is also the documented fallback of the specialized
derivative solve of `MDR-0017`, which runs this exact expression on every
ineligible or failed case (see `ADR-0022`).
"""
function best_response_1d(U::F, h_start::Float64) where {F}
    return maximize_1d(U, 0.0, 1.0, h_start, BEST_RESPONSE_WINDOW, BEST_RESPONSE_TOL)
end

# Absolute hours tolerance of the derivative best-response solve of
# `MDR-0017` (see `ADR-0022`): the Newton step and bracket-width
# termination bound of `_derivative_best_response` and the half-width of
# its sign-enclosure probes. A numerical solver constant, not a model
# parameter (`registry/model/parameters.md`).
const DERIVATIVE_RESPONSE_TOL = 1.0e-8

# Iteration cap of the derivative best-response solve of `MDR-0017`:
# at most this many safeguarded Newton/bisection steps in
# `_derivative_best_response` before the solve gives up and runs the
# `MDR-0002` fallback.
const DERIVATIVE_RESPONSE_MAX_ITER = 40

"""
    _derivative_applicable(obj::BestResponseObjective{S}, h_start::Float64)

Applicability gate of the derivative best-response solve of `MDR-0017`
(see `ADR-0022`): `true` only when the objective is one of `Additive`,
`Multiplicative`, `MultiplicativeWeighted`, or `CES` with finite
`CES_DERIVATIVE_MIN_BETA <= beta <= 1` (below the floor the `1 / beta`
amplification of the inner-sum rounding jags the computed utility past
the non-degradation envelope; see `CES_DERIVATIVE_MIN_BETA`),
`h_start` is finite, the spouse hours lie in `[0, 1]`,
`alpha` in `[0, 1]`, every objective field is finite, `wage_self`,
`conformism`, and `norm_weight` are non-negative, and the consumption
coefficients `A` (recipient `wage_self`, payer `wage_self *
one_minus_transfer`) and `B` (recipient `transfer_income`, payer `0`)
are finite and non-negative with `A > 0 || B > 0`. Every other objective
runs the `MDR-0002` fallback. Returns a `Bool`.
"""
function _derivative_applicable(
        obj::BestResponseObjective{S}, h_start::Float64
    )::Bool where {S}
    isfinite(h_start) || return false
    func = obj.func
    eligible = func isa Additive || func isa Multiplicative ||
        func isa MultiplicativeWeighted ||
        (
        func isa CES && isfinite(func.beta) &&
            CES_DERIVATIVE_MIN_BETA <= func.beta <= 1.0
    )
    eligible || return false
    ok = isfinite(obj.alpha) && 0.0 <= obj.alpha <= 1.0 &&
        isfinite(obj.one_minus_alpha) &&
        isfinite(obj.wage_self) && obj.wage_self >= 0.0 &&
        isfinite(obj.transfer_income) && obj.transfer_income >= 0.0 &&
        isfinite(obj.one_minus_transfer) &&
        isfinite(obj.h_spouse) && 0.0 <= obj.h_spouse <= 1.0 &&
        isfinite(obj.norm_transfer) && isfinite(obj.norm_spouse) &&
        isfinite(obj.norm_weight) && obj.norm_weight >= 0.0 &&
        isfinite(obj.norm_hours) &&
        isfinite(obj.conformism) && obj.conformism >= 0.0
    ok || return false
    A = obj.recipient ? obj.wage_self : obj.wage_self * obj.one_minus_transfer
    B = obj.recipient ? obj.transfer_income : 0.0
    (isfinite(A) && A >= 0.0 && isfinite(B) && B >= 0.0) || return false
    return A > 0.0 || B > 0.0
end

"""
    _derivative_response_accept(value::Float64, v_lo::Float64, v_hi::Float64, v_seed::Float64)

Value acceptance of the derivative best-response solve of `MDR-0017`
(see `ADR-0022`): `true` only when the candidate `value` is finite and
positive and reaches every evaluated reference value (the feasible
endpoint values `v_lo` and `v_hi` and the feasible seed value `v_seed`,
`NaN` meaning not evaluated) to within 32 ulps at the comparison scale.
The candidate value and the references are all same-pass `obj(h)` values
of `_best_response_derivatives`. Returns a `Bool`.
"""
function _derivative_response_accept(
        value::Float64, v_lo::Float64, v_hi::Float64, v_seed::Float64
    )::Bool
    (isfinite(value) && value > 0.0) || return false
    for v_ref in (v_lo, v_hi, v_seed)
        if isfinite(v_ref)
            scale = max(abs(value), abs(v_ref))
            value >= v_ref - 32.0 * eps(scale) || return false
        end
    end
    return true
end

"""
    _derivative_seed_certificate(obj::BestResponseObjective{S}, h_start::Float64)

Tier-1 seed certificate of the derivative best response of `MDR-0017`
(see `ADR-0022`): a two-probe sign enclosure at the model's documented
best-response resolution `BEST_RESPONSE_TOL` (the NetLogo
`current-delta`, `MDR-0002`) that certifies the seed itself as within
that resolution of the optimum of its own objective, without evaluating
the objective value or the curvature. It uses only the cheap
`_best_response_gradient_sign` sign probes at `h_start -
BEST_RESPONSE_TOL` and `h_start + BEST_RESPONSE_TOL` (sign-equivalent
residuals of `g`, see `_gradient_sign_residual`; a probe that leaves
the guarded domain returns `NaN` and is skipped). Under the
non-increasing `g` certificate (the `MDR-0017` sign argument) the
enclosure rules are:

- both probes evaluable: certify iff `g(h - tol) >= 0 >= g(h + tol)`
  (a root of `g` lies in `[h - tol, h + tol]`, so `h` is within `tol`
  of the optimum);
- only the right probe evaluable and `h_start <= BEST_RESPONSE_TOL`
  (the feasible interval extends at most `tol` to the left of the
  seed): certify iff `g(h + tol) <= 0` (the optimum lies in
  `[h - tol, h + tol]` against the lower domain end; this is the
  boundary-seed rule, so `h_start == 0` and near-boundary seeds
  certify at ONE probe cost);
- only the left probe evaluable and `h_start >= 1 - BEST_RESPONSE_TOL`:
  certify iff `g(h - tol) >= 0`, the symmetric rule at the upper end;
- neither probe evaluable, or the pattern failing: no certificate and
  the full solve runs.

The seed must be a feasible point of the guarded domain: an infeasible
seed (the unattainable-supremum geometry `x(0) == 0` at `h_start == 0`,
or `Q(1) == 0` at `h_start == 1`) never certifies, since the returned
hours must be feasible and there the optimum is the unattainable
supremum itself. The `h_start <= tol` / `h_start >= 1 - tol` domain
conditions of the one-sided rules are required for soundness: a probe
skipped by a numerical guard far from the domain end must not certify a
seed whose optimum lies outside the window. A flat objective (zero sign
residual at both probes) certifies and keeps the seed, matching the
legacy tie/seed return. Returns a `Bool`.
"""
function _derivative_seed_certificate(
        obj::BestResponseObjective{S}, h_start::Float64
    )::Bool where {S}
    A = obj.recipient ? obj.wage_self : obj.wage_self * obj.one_minus_transfer
    B = obj.recipient ? obj.transfer_income : 0.0
    lo_open = B == 0.0 && A > 0.0
    hi_open = obj.h_spouse == 1.0
    return _seed_certificate_probes(obj, h_start, A, lo_open, hi_open)
end

"""
    _seed_certificate_probes(obj::BestResponseObjective{S}, h_start::Float64, A::Float64, lo_open::Bool, hi_open::Bool)

Rule core of the tier-1 seed certificate of `MDR-0017` (see
`_derivative_seed_certificate` for the rules and their soundness
argument): the two `_gradient_sign_at` sign probes (sign-equivalent
residuals of `g`, see `_gradient_sign_residual`) with the shared
coefficients `A` and `k = conformism * norm_weight`, applied to a seed
in `[0, 1]` that is not at a guard-removed endpoint (both are checked
here). Returns a `Bool`.
"""
function _seed_certificate_probes(
        obj::BestResponseObjective{S}, h_start::Float64, A::Float64,
        lo_open::Bool, hi_open::Bool,
    )::Bool where {S}
    (0.0 <= h_start <= 1.0) || return false
    ((lo_open && h_start == 0.0) || (hi_open && h_start == 1.0)) && return false
    tol = BEST_RESPONSE_TOL
    k = obj.conformism * obj.norm_weight
    gl = _gradient_sign_at(obj, h_start - tol, A, k)
    gr = _gradient_sign_at(obj, h_start + tol, A, k)
    gl_ok = isfinite(gl)
    gr_ok = isfinite(gr)
    if gl_ok && gr_ok
        return gl >= 0.0 && gr <= 0.0
    elseif gr_ok
        return h_start <= tol && gr <= 0.0
    elseif gl_ok
        return h_start >= 1.0 - tol && gl >= 0.0
    end
    return false
end

"""
    _derivative_best_response(obj::BestResponseObjective{S}, h_start::Float64)

Safeguarded derivative best response of `MDR-0017` (see `ADR-0022`):
solve `g = d log(U)/dh = 0` over the feasible interval of
`BestResponseObjective` and return `(candidate, true)`, or `(NaN, false)`
to run the `MDR-0002` fallback. Two accuracy tiers (the `MDR-0017`
contract):

1. Tier 1, the `_derivative_seed_certificate` seed certificate at
   `BEST_RESPONSE_TOL` (the model's documented best-response
   resolution): two cheap sign probes, no objective value; a certified
   seed returns itself, so a converged sweep keeps its hours at one
   probe-pair cost and a boundary-hugging seed certifies with one
   probe.
2. Tier 2, the full solve: lazy endpoint signs from the cheap
   `_best_response_gradient_sign` probes with the strict boundary rules
   and the analytic one-sided limits of `_one_sided_gradient` at
   guard-infeasible endpoints (a selected endpoint is validated through
   a full evaluation at that point), then a bracketed safeguarded
   Newton/bisection iteration (at most `DERIVATIVE_RESPONSE_MAX_ITER`
   steps). Candidate certification is either the probe sign-enclosure
   (`abs(g/g') <= DERIVATIVE_RESPONSE_TOL` or an exact computed root,
   with `g(h - tol) >= 0 >= g(h + tol)` at evaluable probes) or, at the
   width exit (a maintained sign bracket `g(a) > 0 > g(b)` of width `<=
   DERIVATIVE_RESPONSE_TOL` around the current `h`), the sign bracket
   itself: where both probes at `h +/- DERIVATIVE_RESPONSE_TOL` are
   evaluable they must confirm the enclosure signs (a pure noise guard
   under the non-increasing `g` certificate), and a probe skipped by the
   feasible-boundary guards accepts the sign bracket.

Tier-2 returns are certified within `DERIVATIVE_RESPONSE_TOL` of the
root of `g` (or are a certified boundary point); the probe-certified
exits are idempotent (a re-solve returns the point bitwise), and a
tier-1-certified point re-certifies at the same probes. Every full
evaluation goes through `_best_response_derivatives`; any numerical-gate
violation, unbracketable sign, uncertifiable candidate, or failed value
acceptance falls back. The accepted tier-2 candidate passes
`_derivative_response_accept` against the evaluated endpoint and seed
values.
"""
function _derivative_best_response(
        obj::BestResponseObjective{S}, h_start::Float64
    )::Tuple{Float64, Bool} where {S}
    _derivative_applicable(obj, h_start) || return (NaN, false)
    tol = DERIVATIVE_RESPONSE_TOL
    A = obj.recipient ? obj.wage_self : obj.wage_self * obj.one_minus_transfer
    B = obj.recipient ? obj.transfer_income : 0.0
    lo_open = B == 0.0 && A > 0.0
    hi_open = obj.h_spouse == 1.0

    # Tier-1 seed certificate (`MDR-0017` step 1): the two cheap sign
    # probes at the model resolution `BEST_RESPONSE_TOL` certify the
    # seed as within that resolution of the optimum and return it
    # without any objective evaluation.
    _seed_certificate_probes(obj, h_start, A, lo_open, hi_open) &&
        return (h_start, true)

    # Seed evaluation (the full-solve input and, at `h_start == 0` or
    # `h_start == 1`, the feasible endpoint evaluation of that end).
    seed_ok = 0.0 <= h_start <= 1.0 &&
        !(lo_open && h_start == 0.0) && !(hi_open && h_start == 1.0)
    g0 = NaN
    gp0 = NaN
    v0 = NaN
    if seed_ok
        g0, gp0, v0 = _best_response_derivatives(obj, h_start)
        isfinite(g0) || return (NaN, false)
    end
    seed_ok && g0 == 0.0 && return (NaN, false)

    # Endpoint signs and strict boundary rules (`MDR-0017` steps 2-3),
    # evaluated lazily and cheaply: a seed sign in one direction already
    # rules out the opposite boundary optimum under the non-increasing
    # `g` certificate, and an endpoint sign needs only the derivative
    # probe (its objective value is evaluated when that endpoint is
    # selected and validated there, see below).
    g_lo = NaN
    g_hi = NaN
    v_lo = NaN
    v_hi = NaN
    if seed_ok && h_start == 0.0
        g_lo, v_lo = g0, v0
    end
    if seed_ok && h_start == 1.0
        g_hi, v_hi = g0, v0
    end
    if !seed_ok || g0 < 0.0
        if lo_open
            _one_sided_gradient(obj, true) > 0.0 || return (NaN, false)
        elseif !isfinite(g_lo)
            g_lo = _best_response_gradient_sign(obj, 0.0)
            isfinite(g_lo) || return (NaN, false)
            g_lo == 0.0 && return (NaN, false)
            if g_lo < 0.0
                g_lo, _, v_lo = _best_response_derivatives(obj, 0.0)
                (isfinite(g_lo) && g_lo < 0.0) || return (NaN, false)
                _derivative_response_accept(v_lo, NaN, v_hi, v0) || return (NaN, false)
                return (0.0, true)
            end
        end
    end
    if !seed_ok || g0 > 0.0
        if hi_open
            _one_sided_gradient(obj, false) < 0.0 || return (NaN, false)
        elseif !isfinite(g_hi)
            g_hi = _best_response_gradient_sign(obj, 1.0)
            isfinite(g_hi) || return (NaN, false)
            g_hi == 0.0 && return (NaN, false)
            if g_hi > 0.0
                g_hi, _, v_hi = _best_response_derivatives(obj, 1.0)
                (isfinite(g_hi) && g_hi > 0.0) || return (NaN, false)
                _derivative_response_accept(v_hi, v_lo, NaN, v0) || return (NaN, false)
                return (1.0, true)
            end
        end
    end

    # Interior bracket `[a, b]` with `g(a) > 0 > g(b)` (`MDR-0017`
    # step 4), seeded at the feasible interior point nearest `h_start`
    # (or the midpoint when the seed is not evaluable).
    a = 0.0
    b = 1.0
    h = h_start
    g = g0
    gp = gp0
    v = v0
    if seed_ok && g0 > 0.0
        a = h_start
    elseif seed_ok && g0 < 0.0
        b = h_start
    else
        h = 0.5 * (a + b)
        g, gp, v = _best_response_derivatives(obj, h)
        isfinite(g) || return (NaN, false)
    end
    for _ in 1:DERIVATIVE_RESPONSE_MAX_ITER
        # Termination certificates (`MDR-0017` step 5): the Newton-step
        # enclosure at `h +/- tol`, else a bracket of width `<= tol`
        # around `h`.
        if gp < 0.0 && abs(g / gp) <= tol
            g_left = _best_response_gradient_sign(obj, h - tol)
            g_right = _best_response_gradient_sign(obj, h + tol)
            if isfinite(g_left) && isfinite(g_right) && g_left >= 0.0 && g_right <= 0.0
                _derivative_response_accept(v, v_lo, v_hi, v0) || return (NaN, false)
                return (h, true)
            end
        end
        if b - a <= tol
            # Width-exit certificate (`MDR-0017` step 5): the maintained
            # sign bracket `g(a) > 0 > g(b)` with width `<= tol` and the
            # current `h` in `[a, b]` encloses the root within `tol` of
            # `h`. Where both enclosure probes at `h +/- tol` are
            # evaluable they must confirm the enclosure signs (a pure
            # noise guard: under the non-increasing `g` certificate
            # `h - tol <= a` and `h + tol >= b` make the check
            # unfailable; a violation needs numerical non-monotonicity
            # of the computed `g` and falls back to legacy), while a
            # probe skipped by the feasible-boundary guards (`NaN`)
            # accepts the sign-bracket certificate.
            g_left = _best_response_gradient_sign(obj, h - tol)
            g_right = _best_response_gradient_sign(obj, h + tol)
            if isfinite(g_left) && isfinite(g_right) &&
                    !(g_left >= 0.0 && g_right <= 0.0)
                return (NaN, false)
            end
            _derivative_response_accept(v, v_lo, v_hi, v0) || return (NaN, false)
            return (h, true)
        end
        g == 0.0 && return (NaN, false)
        # Safeguarded Newton step strictly inside the bracket and past
        # the stall floor `tol`, else bisection (`MDR-0017` step 4); the
        # sign of the new evaluation tightens the bracket, so every step
        # shrinks it strictly and the width certificate terminates
        # within the iteration cap.
        h_try = gp < 0.0 ? h - g / gp : NaN
        h_new = NaN
        if isfinite(h_try) && a < h_try < b && abs(h_try - h) > tol
            h_new = h_try
        else
            h_new = 0.5 * (a + b)
        end
        (a < h_new < b) || return (NaN, false)
        g_new, gp_new, v_new = _best_response_derivatives(obj, h_new)
        isfinite(g_new) || return (NaN, false)
        if g_new > 0.0
            a = h_new
        elseif g_new < 0.0
            b = h_new
        else
            # Exact computed root: certify it through the probe
            # enclosure.
            if gp_new < 0.0
                g_left = _best_response_gradient_sign(obj, h_new - tol)
                g_right = _best_response_gradient_sign(obj, h_new + tol)
                if isfinite(g_left) && isfinite(g_right) &&
                        g_left >= 0.0 && g_right <= 0.0
                    if _derivative_response_accept(v_new, v_lo, v_hi, v0)
                        return (h_new, true)
                    end
                end
            end
            return (NaN, false)
        end
        h = h_new
        g = g_new
        gp = gp_new
        v = v_new
    end
    return (NaN, false)
end

"""
    best_response_1d(obj::BestResponseObjective{S}, h_start::Float64) where {S}

Own working time on `[0, 1]` for one partner at fixed spouse hours and
fixed transfer (ODD section Labour best response, NetLogo
`choose-bundle`), seeded at the current hours `h_start`. Eligible
objectives are solved by the safeguarded derivative root solve of
`MDR-0017` (`_derivative_best_response`, see `ADR-0022`) in two
accuracy tiers: the tier-1 seed certificate at `BEST_RESPONSE_TOL` (the
NetLogo `current-delta` resolution; a certified seed keeps its hours),
otherwise the tier-2 full solve certified at
`DERIVATIVE_RESPONSE_TOL`. Every ineligible or failed case runs exactly
the seeded Brent expression of `MDR-0002` (the generic
`best_response_1d` method), so those results are bitwise identical to
the pre-`MDR-0017` solver. Returns the best feasible hours, or `NaN`
when no feasible sample exists.
"""
function best_response_1d(obj::BestResponseObjective{S}, h_start::Float64) where {S}
    candidate, ok = _derivative_best_response(obj, h_start)
    ok && return candidate
    return maximize_1d(obj, 0.0, 1.0, h_start, BEST_RESPONSE_WINDOW, BEST_RESPONSE_TOL)
end

"""
    mutual_best_response(hw_init::Float64, hm_init::Float64, theta::Float64, pw::AgentPayoffParams, pm::AgentPayoffParams, config::UtilityConfig; eps = 1.0e-3, max_sweeps = 100)

Alternating continuous best responses of the two partners of one household
for a fixed transfer `theta`, starting from the working times `hw_init` and
`hm_init`. Port of NetLogo `choose-bundle` (ODD section Labour best
response): each best response starts from the current hours and keeps them
when no feasible sample exists. Eligible utility regimes solve each best
response with the safeguarded derivative root solve of `MDR-0017` (the
tier-1 seed certificate at the `current-delta` resolution keeps certified
hours, the tier-2 solve is global on `[0, 1]`); ineligible or failed
cases run the seeded continuous solver
of `MDR-0002` verbatim, whose window and probe semantics are documented
there (see `ADR-0022`).
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
        eps = 1.0e-3, max_sweeps = 100
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
