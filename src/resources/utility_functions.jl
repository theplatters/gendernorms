abstract type UtilitySpec end

struct Additive <: UtilitySpec end

Base.@kwdef struct CES <: UtilitySpec
    beta::Float64 = 0.5
end

struct Multiplicative <: UtilitySpec end

struct MultiplicativeWeighted <: UtilitySpec end

Base.@kwdef struct UtilityConfig{T <: UtilitySpec}
    func::T = CES()
    w_self::Float64 = 1.0
    w_partner::Float64 = 1.0
    w_transfer::Float64 = 1.0
end

material(::Additive, x::Float64, Q::Float64, alpha::Float64) =
    alpha * sqrt(x) + (1 - alpha) * sqrt(Q)

"""
    material(u::CES, x::Float64, Q::Float64, alpha::Float64)

CES material utility (ODD section Material utility): the general
`(alpha * x^beta + (1 - alpha) * Q^beta)^(1 / beta)` formula, with the
exact `beta == 0.5` case specialized to `s = alpha * sqrt(x) + (1 -
alpha) * sqrt(Q); s * s` (three runtime `pow` calls replaced by two
`sqrt` and one multiply; `x^0.5` and `sqrt(x)` differ by up to one ulp
on about 1% of values, a validated-equivalent arithmetic change of
`MDR-0013`, preserved by `MDR-0014`). Every other `beta` keeps the
general formula unchanged.
"""
function material(u::CES, x::Float64, Q::Float64, alpha::Float64)
    if u.beta == 0.5
        s = alpha * sqrt(x) + (1 - alpha) * sqrt(Q)
        return s * s
    end
    return (alpha * x^u.beta + (1 - alpha) * Q^u.beta)^(1 / u.beta)
end

material(::Multiplicative, x::Float64, Q::Float64, alpha::Float64) =
    sqrt(x) * sqrt(Q)

material(::MultiplicativeWeighted, x::Float64, Q::Float64, alpha::Float64) =
    x^alpha * Q^(1 - alpha)

"""
    _envelope_peak(f, q::Float64, d::Float64, v_star::Float64)

Envelope evaluation helper of the certified `-Inf` transfer-objective
certificate (see `ADR-0015` and `_material_envelope(::Additive, ...)`):
evaluates the envelope candidate `f` at `v == 0`, `v == v_star`, and
`v == d` and returns the largest value, or `NaN` (fail open) when a
candidate point leaves `[0, d]`, when its `q * v` or `2 - v` input is
non-finite or falls below `floatmin` where the analytic formulas assume
a positive normal value (a zero product is accepted only at `v == 0`,
zero `2 - v` only at `v == 2`), when a candidate value is non-finite
or negative, or when the largest candidate is subnormal. Evaluating
the analytic maximizer together with both interval endpoints and
taking the largest is belt-and-braces: the bound then does not depend
on `v_star` being located exactly (the per-spec maximizer formulas are
ill-conditioned at some parameter values), and the maximum can only
grow compared to the maximizer alone. Certification helper of
`ADR-0015`, not a ported NetLogo behavior.
"""
function _envelope_peak(f::F, q::Float64, d::Float64, v_star::Float64)::Float64 where {F}
    best = 0.0
    for v in (0.0, v_star, d)
        (isfinite(v) && 0.0 <= v <= d) || return NaN
        if v > 0.0
            xv = q * v
            (isfinite(xv) && xv >= floatmin(Float64)) || return NaN
        end
        if v < 2.0
            Qv = 2.0 - v
            (isfinite(Qv) && Qv >= floatmin(Float64)) || return NaN
        end
        value = f(v)::Float64
        (isfinite(value) && value >= 0.0) || return NaN
        value > best && (best = value)
    end
    best >= floatmin(Float64) || return NaN
    return best
end

"""
    _material_envelope(spec::UtilitySpec, q::Float64, d::Float64, alpha::Float64, recipient::Bool)

Fail-open fallback of `_material_envelope(::Additive, ...)`: a
`UtilitySpec` subtype without a certified envelope yields `NaN`, so the
certificate never certifies on an unenveloped spec and falls back to
the full solve (see `ADR-0015`).
"""
_material_envelope(::UtilitySpec, q::Float64, d::Float64, alpha::Float64, recipient::Bool)::Float64 = NaN

"""
    _material_envelope(::Additive, q::Float64, d::Float64, alpha::Float64, recipient::Bool)

Material-utility envelope of the certified `-Inf` transfer-objective
certificate (see `ADR-0015`): an upper bound of `material(spec, x, Q,
alpha)` over every feasible bundle `x <= q * v`, `Q <= 2 - v` with `v`
in `[0, d]`, where `v` is the effective working time of one partner
(`d == 1` for the payer, `d == 2` for the recipient; see
`_payoff_upper_bound`). Because the material functions are
non-decreasing in `x` and `Q` on the guarded domain, the envelope is
`max_v material(spec, q * v, 2 - v, alpha)` over `v` in `[0, d]`,
evaluated at the analytic maximizer of the spec and at both endpoints
`v == 0` and `v == d`. For `Additive` the maximizer is
`v* = clamp(2*alpha^2*q / (alpha^2*q + (1-alpha)^2), 0, d)`.
Returns `NaN` (fail open) when an input is out of range, when the
denominator of `v*` vanishes, or when an envelope intermediate is
non-finite or subnormal (see `_envelope_peak`). The argument
`recipient` is unused for this spec. Certification helper of
`ADR-0015`, not a ported NetLogo behavior.
"""
function _material_envelope(
        ::Additive, q::Float64, d::Float64, alpha::Float64, recipient::Bool
    )::Float64
    ok = isfinite(q) && q > 0.0 && isfinite(d) && d > 0.0 &&
        isfinite(alpha) && 0.0 <= alpha <= 1.0
    ok || return NaN
    denom = alpha * alpha * q + (1.0 - alpha) * (1.0 - alpha)
    denom > 0.0 || return NaN
    if alpha > 0.0
        # A zero numerator here is an underflow of `alpha^2 * q`, not an
        # exact optimum at `v == 0`; fail open on it.
        (alpha * alpha * q > 0.0) || return NaN
    end
    v_star = clamp(2.0 * alpha * alpha * q / denom, 0.0, d)
    return _envelope_peak(v -> alpha * sqrt(q * v) + (1.0 - alpha) * sqrt(2.0 - v), q, d, v_star)
end

# Lower end of the certified `beta` band of the CES envelope (see
# `ADR-0015` and `_material_envelope(::CES, ...)`): `beta` below the
# floor fails open (`NaN`) instead of certifying. The CES envelope and
# the computed `individual_utility` evaluate `S^(1/beta)` from the
# rounded inner sum `S = alpha * x^beta + (1 - alpha) * Q^beta`; the
# condition number of `S^(1/beta)` in `S` is `1/beta`, so the rounding
# of the two evaluations is amplified to the relative gap
# `(1 / beta) * n_ops * eps` (`eps = 2^-53`, `n_ops = 10` the combined
# operation/error budget of the two inner sums: two inner powers, two
# weight multiplies, and one add each, each `<= 1` ulp). At the floor
# `beta = 1.0e-3` the amplification is about 1.0e-12, well below the
# total relative margin `OBJECTIVE_CERT_MARGIN = 1.0e-9`; below the
# floor it grows like `1 / beta` and drowns the margin (`~1.0e-4` at
# `beta = 1.0e-12`). No upper bound is needed: for `beta >= 1` the
# exponent `1 / beta <= 1` contracts rather than amplifies rounding.
# The exact `beta == 0.5` sqrt/square specialization of `material`
# (`MDR-0014`) and of the envelope itself (`ADR-0019`, evaluating the
# same `t = alpha * sqrt(x) + (1 - alpha) * sqrt(Q); t * t` expression
# on both sides) has fewer rounding stages than the budgeted pow path
# (two `sqrt` and one correctly-rounded multiply against three `pow`)
# and the same factor-two amplification of the inner-sum rounding, so
# the error budget above covers it unchanged.
const CES_CERT_MIN_BETA = 1.0e-3

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

"""
    _material_envelope(u::CES, q::Float64, d::Float64, alpha::Float64, recipient::Bool)

CES envelope of `_material_envelope(::Additive, ...)`, certified only
inside the safe band `beta >= CES_CERT_MIN_BETA`; `beta` below the
floor, `beta <= 0`, and non-finite `beta` fail open (`NaN`), because
the outer power `S^(1/beta)` amplifies the rounding of the inner sum
by `1 / beta` (see `CES_CERT_MIN_BETA` and `ADR-0015`). The exact
`beta == 0.5` case (the `material(::CES, ...)` dispatch condition) is
specialized to the sqrt/square form of `material` (see `ADR-0019`):
the envelope candidate at `v` evaluates exactly the expression
`material` evaluates at `(q * v, 2 - v)`, `t = alpha * sqrt(q * v) +
(1 - alpha) * sqrt(2 - v); t * t`, so the candidate and the computed
material round identically at identical inputs and the bound gains
headroom against the pow path (fewer rounding stages, no `pow(x, 2)`
versus `s * s` gap); the analytic maximizer uses the closed form
`v* = clamp(2*alpha^2*q / (alpha^2*q + (1-alpha)^2), 0, d)` (the
general `R` form below specialized at `beta == 0.5`, and identical to
the `Additive` maximizer because `material_CES(beta=0.5) =
material_Additive^2`). Every other `beta` keeps the general form: for
`0 < beta < 1` the inner expression is concave in `v` and the analytic
maximizer applies: `R = (alpha*q^beta/(1-alpha))^(1/(1-beta))` with
`v* = clamp(2R/(1+R), 0, d)`, plus the endpoint limits `v* == 0` for
`alpha == 0`, `v* == d` for `alpha == 1` and for `R` infinite. For
`beta >= 1` the inner expression is convex in `v` and the maximum is at
an endpoint. Every candidate is evaluated at `v == 0`, `v == v_star`,
and `v == d` and the largest value is returned (see `_envelope_peak`),
so a mislocated `v*` (the `R` formula is ill-conditioned in
`1/(1-beta)` as `beta -> 1`) cannot lower the bound below the endpoint
values. The `beta >= 1` branch (outer exponent `1 / beta <= 1`) fails
open on a non-finite or subnormal inner sum `S` and accepts only an
exactly-zero `S` (from exact zero `x` or `Q`, computed exactly): the
root maps a subnormal `S`, whose relative quantization error is
unbounded, up into the normal material range where the error would
dwarf the margin. For `0 < beta < 1` (outer exponent `> 1`) no such
guard is needed: a subnormal `S` maps down below the `floatmin` floor
that `_envelope_peak` requires of the largest candidate, so it can
never dominate a certified bound (the same holds for the sqrt/square
specialization: a subnormal inner sum squares below the floor, and at
interior `v` both `sqrt` inputs are guarded to at least `floatmin`,
so the inner sum is normal there). An `x^beta`-style intermediate that
overflows or underflows to zero is covered by the same guards:
overflow makes `S` or the candidate value non-finite and fails open,
and a dropped-underflow term contributes under `2^-1075` absolute,
which is negligible against a normal `S` and mapped below the bound
floor when the whole sum underflows. The argument `recipient` is
unused for this spec. See `ADR-0015` and `ADR-0019`.
"""
function _material_envelope(
        u::CES, q::Float64, d::Float64, alpha::Float64, recipient::Bool
    )::Float64
    ok = isfinite(q) && q > 0.0 && isfinite(d) && d > 0.0 &&
        isfinite(alpha) && 0.0 <= alpha <= 1.0
    ok || return NaN
    beta = u.beta
    (isfinite(beta) && beta >= CES_CERT_MIN_BETA) || return NaN
    if beta == 0.5
        # The exact `beta == 0.5` sqrt/square form of `material`,
        # specialized for exactness against the computed utility and
        # for speed (see `ADR-0019`).
        peak = v -> begin
            t = alpha * sqrt(q * v) + (1.0 - alpha) * sqrt(2.0 - v)
            t * t
        end
        if alpha <= 0.0
            v_star = 0.0
        elseif alpha >= 1.0
            v_star = d
        else
            denom = alpha * alpha * q + (1.0 - alpha) * (1.0 - alpha)
            denom > 0.0 || return NaN
            # A zero numerator here is an underflow of `alpha^2 * q`,
            # not an exact optimum at `v == 0`; fail open on it (the
            # `Additive` rule).
            (alpha * alpha * q > 0.0) || return NaN
            v_star = clamp(2.0 * alpha * alpha * q / denom, 0.0, d)
        end
        return _envelope_peak(peak, q, d, v_star)
    end
    beta_inv = 1.0 / beta
    if beta >= 1.0
        peak = v -> begin
            s = alpha * (q * v)^beta + (1.0 - alpha) * (2.0 - v)^beta
            (isfinite(s) && (iszero(s) || s >= floatmin(Float64))) || return NaN
            return s^beta_inv
        end
        return _envelope_peak(peak, q, d, 0.0)
    end
    peak = v -> (alpha * (q * v)^beta + (1.0 - alpha) * (2.0 - v)^beta)^beta_inv
    if alpha <= 0.0
        v_star = 0.0
    elseif alpha >= 1.0
        v_star = d
    else
        R = (alpha * q^beta / (1.0 - alpha))^(1.0 / (1.0 - beta))
        isnan(R) && return NaN
        if isinf(R)
            v_star = d
        elseif R <= 0.0
            return NaN
        else
            v_star = clamp(2.0 * R / (1.0 + R), 0.0, d)
        end
    end
    return _envelope_peak(peak, q, d, v_star)
end

"""
    _material_envelope(::Multiplicative, q::Float64, d::Float64, alpha::Float64, recipient::Bool)

Multiplicative envelope of `_material_envelope(::Additive, ...)`: the
maximizer of `sqrt(q*v)*sqrt(2-v)` is `v* = min(d, 1)`. The argument
`recipient` is unused for this spec and `alpha` does not enter the
material function, but the uniform input guards apply. See
`ADR-0015`.
"""
function _material_envelope(
        ::Multiplicative, q::Float64, d::Float64, alpha::Float64, recipient::Bool
    )::Float64
    ok = isfinite(q) && q > 0.0 && isfinite(d) && d > 0.0 &&
        isfinite(alpha) && 0.0 <= alpha <= 1.0
    ok || return NaN
    v_star = min(d, 1.0)
    return _envelope_peak(v -> sqrt(q * v) * sqrt(2.0 - v), q, d, v_star)
end

"""
    _material_envelope(::MultiplicativeWeighted, q::Float64, d::Float64, alpha::Float64, recipient::Bool)

MultiplicativeWeighted envelope of `_material_envelope(::Additive,
...)`. The recipient uses the `material` method `x^alpha * Q^(1-alpha)`
with maximizer `v* = clamp(2*alpha, 0, d)`; the payer uses the special
branch of `individual_utility`, `(x^alpha * Q)^(1-alpha)`, with
maximizer `v* = clamp(2*alpha/(1+alpha), 0, d)`. The argument
`recipient` selects the branch and must match the one
`individual_utility` takes. See `ADR-0015`.
"""
function _material_envelope(
        ::MultiplicativeWeighted, q::Float64, d::Float64, alpha::Float64, recipient::Bool
    )::Float64
    ok = isfinite(q) && q > 0.0 && isfinite(d) && d > 0.0 &&
        isfinite(alpha) && 0.0 <= alpha <= 1.0
    ok || return NaN
    if recipient
        v_star = clamp(2.0 * alpha, 0.0, d)
        return _envelope_peak(v -> (q * v)^alpha * (2.0 - v)^(1.0 - alpha), q, d, v_star)
    end
    v_star = clamp(2.0 * alpha / (1.0 + alpha), 0.0, d)
    return _envelope_peak(v -> ((q * v)^alpha * (2.0 - v))^(1.0 - alpha), q, d, v_star)
end

"""
    AgentPayoffParams

Transient per-agent parameter object of the household bargaining: own and
spouse wage, material preference `alpha`, conformism, the perceived norms
`N_h` (own working time), `N_theta` (transfer), and `N_h_spouse` (spouse
working time), and the agent's sex. `set_theta!` builds it at the
`mutual_best_response` call and the solver passes it to
`individual_utility`; it is never stored or returned (see `ADR-0007`).
"""
Base.@kwdef struct AgentPayoffParams
    wage_self::Float64 = 1.0
    wage_spouse::Float64 = 1.0
    alpha::Float64 = 0.5
    conformism::Float64 = 0.0
    N_h::Float64 = 0.5
    N_theta::Float64 = 0.0
    N_h_spouse::Float64 = 0.5
    is_woman::Bool = true
end

"""
    BestResponseObjective{S}

Prepared own-hours objective of one `best_response_1d` call (see
`MDR-0013` and `ADR-0018`): the `individual_utility` of one partner at
fixed spouse hours and fixed transfer, with every transfer- and
spouse-dependent term hoisted out of the per-hours evaluation. Built by
`BestResponseObjective(theta, h_spouse, self_params, config)` and called
as `obj(h::Float64)`; an isbits callable that allocates nothing and
keeps the `UtilitySpec` type `S` static for the material dispatch (the
`MDR-0002` no-boxing discipline, now structural: `mutual_best_response`
passes this callable instead of a closure). Fields hold the hoisted
consumption terms `wage_self`, `transfer_income`, and
`one_minus_transfer` of `x` (the recipient's `h * wage_self +
transfer_income` with `transfer_income = abs(relevant_transfer) *
wage_spouse * h_spouse`, the payer's `(h * wage_self) *
one_minus_transfer`), the fixed spouse hours `h_spouse` of `Q = (2 -
h) - h_spouse`, the hoisted transfer and spouse norm products
`norm_transfer` and `norm_spouse` of `norm = -conformism *
((norm_weight * (h - norm_hours)^2 + norm_transfer) + norm_spouse)`,
the material
preference `alpha` with `one_minus_alpha` for the
`MultiplicativeWeighted` payer branch, the partner role `recipient`,
and the spouse-hours guard `spouse_out_of_range`. Every formula keeps
the exact expression grouping of `individual_utility`, so the
evaluation is bitwise identical to it (CSE-style hoisting only; the
regrouped coefficient form of `MDR-0013` was measured and dropped,
see the record). The formula is the `individual_utility` of NetLogo
`calculate-utility` (ODD sections Material utility and conformity
multiplier and Norm perception).
"""
struct BestResponseObjective{S <: UtilitySpec}
    func::S
    alpha::Float64
    one_minus_alpha::Float64
    wage_self::Float64
    transfer_income::Float64
    one_minus_transfer::Float64
    h_spouse::Float64
    norm_transfer::Float64
    norm_spouse::Float64
    norm_weight::Float64
    norm_hours::Float64
    conformism::Float64
    recipient::Bool
    spouse_out_of_range::Bool
end

"""
    BestResponseObjective(theta::Float64, h_spouse::Float64, self_params::AgentPayoffParams, config::UtilityConfig)

Build the prepared own-hours objective of one `best_response_1d` call
(see `BestResponseObjective` and `MDR-0013`): hoists the transfer- and
spouse-dependent terms of `individual_utility` for own hours `h` at
fixed spouse hours `h_spouse` and fixed transfer `theta`. The role
(`recipient`), the consumption terms of `x`, and the norm products are
computed exactly as `individual_utility` derives them. Returns the
callable objective.
"""
function BestResponseObjective(
        theta::Float64, h_spouse::Float64,
        self_params::AgentPayoffParams, config::UtilityConfig{S}
    ) where {S}
    relevant_transfer = self_params.is_woman ? -theta : theta
    recipient = relevant_transfer < 0
    transfer_income::Float64 = 0.0
    one_minus_transfer::Float64 = 1.0
    if recipient
        transfer_income = abs(relevant_transfer) * self_params.wage_spouse * h_spouse
    else
        one_minus_transfer = 1 - relevant_transfer
    end
    dtheta = theta - self_params.N_theta
    d_spouse = h_spouse - self_params.N_h_spouse
    return BestResponseObjective{S}(
        config.func,
        self_params.alpha,
        1 - self_params.alpha,
        self_params.wage_self,
        transfer_income,
        one_minus_transfer,
        h_spouse,
        config.w_transfer * (dtheta * dtheta),
        config.w_partner * (d_spouse * d_spouse),
        config.w_self,
        self_params.N_h,
        self_params.conformism,
        recipient,
        h_spouse < 0 || h_spouse > 1,
    )
end

"""
    (obj::BestResponseObjective)(h::Float64)

Prepared own-hours objective at own hours `h`: the `individual_utility`
formula of NetLogo `calculate-utility` (ODD sections Material utility
and conformity multiplier and Norm perception) evaluated from the
hoisted constants of `BestResponseObjective`. The guards and their
trigger conditions are those of `individual_utility`, preserved
bit-exactly by the kept expression groupings (`x <= 0`, `Q <= 0`, `h`
outside `[0, 1]`, spouse hours outside `[0, 1]`; see `MDR-0013`).
Returns the utility, `-Inf` for infeasible `h`, `NaN` for non-finite
inputs.
"""
function (obj::BestResponseObjective)(h::Float64)
    x = obj.recipient ? (h * obj.wage_self + obj.transfer_income) :
        ((h * obj.wage_self) * obj.one_minus_transfer)
    Q = (2 - h) - obj.h_spouse
    if x <= 0 || Q <= 0 || h < 0 || h > 1 || obj.spouse_out_of_range
        return -Inf
    end
    dh = h - obj.norm_hours
    norm = -obj.conformism * (
        (obj.norm_weight * (dh * dh) + obj.norm_transfer) + obj.norm_spouse
    )
    material_value = if !obj.recipient && obj.func isa MultiplicativeWeighted
        (x^obj.alpha * Q)^obj.one_minus_alpha
    else
        material(obj.func, x, Q, obj.alpha)
    end
    return material_value * exp(norm)
end

"""
    individual_utility(h_self::Float64, h_spouse::Float64, theta::Float64, self_params::AgentPayoffParams, config::UtilityConfig)

Material utility times the conformity multiplier of NetLogo
`calculate-utility` (ODD sections Material utility and conformity multiplier
and Norm perception) for own hours `h_self`, spouse hours `h_spouse`, and
transfer `theta`, evaluated for the transient `AgentPayoffParams` bundle
`self_params` (see `ADR-0007`). Returns `-Inf` for infeasible bundles.
Delegates to the prepared own-hours objective `BestResponseObjective`
(one source of truth with the labour solver; see `MDR-0013`).
"""
function individual_utility(
        h_self::Float64, h_spouse::Float64, theta::Float64,
        self_params::AgentPayoffParams, config::UtilityConfig
    )
    return BestResponseObjective(theta, h_spouse, self_params, config)(h_self)
end

# Absolute argument tolerance of the seeded best-response search: the NetLogo
# `current-delta` resolution (see `MDR-0002`).
const BEST_RESPONSE_TOL = 1.0e-4
# Half-width of the seeded best-response window around the current hours (see
# `MDR-0002`).
const BEST_RESPONSE_WINDOW = 5.0e-2

"""
    _brent_maximize(f, a, b, tol, max_iter)

Core Brent search behind `maximize_1d`: the maximization variant of the
standard Brent minimization (Numerical Recipes section 10.2), golden section
with parabolic interpolation over the bracket `[a, b]` with the absolute
argument tolerance `tol`. Non-finite samples never enter the parabolic fit;
the best finite sample is tracked across all evaluations. Returns the
`(best_x, best_value)` pair with `best_value == -Inf` when no sample was
finite.
"""
function _brent_maximize(f::F, a::Float64, b::Float64, tol::Float64, max_iter::Int) where {F}
    return _brent_maximize(f, a, b, tol, max_iter, a + 0.3819660112501051 * (b - a))
end

"""
    _brent_maximize(f, a, b, tol, max_iter, x0)

Seeded bounded Brent core of `ADR-0021`, initialized at `x0` in `[a, b]`.
Return the best finite `(point, value)`; non-finite values remain worst.
The original unseeded variant retains its golden-section initialization.
"""
function _brent_maximize(
        f::F, a::Float64, b::Float64, tol::Float64, max_iter::Int, x0::Float64
    ) where {F}
    a <= x0 <= b || throw(ArgumentError("Brent seed must lie in the bracket"))
    cgold::Float64 = 0.3819660112501051
    lo::Float64 = a
    hi::Float64 = b
    x::Float64 = x0
    w::Float64 = x
    v::Float64 = x
    fx_raw::Float64 = f(x)
    fx::Float64 = isfinite(fx_raw) ? -fx_raw : Inf
    fw::Float64 = fx
    fv::Float64 = fx
    best_x::Float64 = x
    best_value::Float64 = fx_raw
    if !isfinite(best_value)
        best_x = NaN
        best_value = -Inf
    end
    e::Float64 = 0.0
    d::Float64 = 0.0
    tol2::Float64 = 2.0 * tol
    iter::Int = 0
    while iter < max_iter
        iter += 1
        xm::Float64 = 0.5 * (lo + hi)
        if abs(x - xm) <= tol2 - 0.5 * (hi - lo)
            break
        end
        take_parabolic::Bool = false
        p::Float64 = 0.0
        q::Float64 = 0.0
        etemp::Float64 = e
        if abs(etemp) > tol && isfinite(fx) && isfinite(fw) && isfinite(fv) && x != w && x != v
            e = d
            r::Float64 = (x - w) * (fx - fv)
            q = (x - v) * (fx - fw)
            p = (x - v) * q - (x - w) * r
            q = 2.0 * (q - r)
            if q != 0.0
                if q > 0.0
                    p = -p
                end
                q = abs(q)
                if abs(p) < abs(0.5 * q * etemp) && p > q * (lo - x) && p < q * (hi - x)
                    take_parabolic = true
                    d = p / q
                    u_try::Float64 = x + d
                    if u_try - lo < tol2 || hi - u_try < tol2
                        d = xm >= x ? tol : -tol
                    end
                end
            end
        end
        if !take_parabolic
            e = x >= xm ? lo - x : hi - x
            d = cgold * e
        end
        u::Float64 = x + (abs(d) >= tol ? d : (d >= 0.0 ? tol : -tol))
        if u < a
            u = a
        elseif u > b
            u = b
        end
        fu_raw::Float64 = f(u)
        fu::Float64 = isfinite(fu_raw) ? -fu_raw : Inf
        if isfinite(fu_raw) && fu_raw > best_value
            best_x = u
            best_value = fu_raw
        end
        if fu <= fx
            if u >= x
                lo = x
            else
                hi = x
            end
            v = w
            fv = fw
            w = x
            fw = fx
            x = u
            fx = fu
        else
            if u < x
                lo = u
            else
                hi = u
            end
            if fu <= fw || w == x
                v = w
                fv = fw
                w = u
                fw = fu
            elseif fu <= fv || v == x || v == w
                v = u
                fv = fu
            end
        end
    end
    return best_x, best_value
end

"""
    maximize_1d(f::F, a::Float64, b::Float64, tol::Float64; max_iter::Int = 64) where {F}

Brent maximization of `f` on the bracket `[a, b]` (precondition `a < b`)
with the absolute argument tolerance `tol`: the maximization variant of the
standard Brent minimization (Numerical Recipes section 10.2), golden section
with parabolic interpolation, replacing the `Optim.Brent` call of the first
port (see `MDR-0002` and `MDR-0012`). Every non-finite objective value (`-Inf`
on infeasible regions, `NaN`) is treated as the worst value and never enters
the parabolic fit; the search is specialized on `F` and allocates nothing.
Arguments are the objective `f`, the bracket endpoints `a` and `b`, the
tolerance `tol`, and the iteration guard `max_iter`. Both bracket endpoints
are evaluated as candidates, so a corner optimum is returned exactly.
Returns the best finite sample, or `NaN` when no sample was finite.
"""
function maximize_1d(f::F, a::Float64, b::Float64, tol::Float64; max_iter::Int = 64) where {F}
    best_x, best_value = _brent_maximize(f, a, b, tol, max_iter)
    fa::Float64 = f(a)
    if isfinite(fa) && fa >= best_value
        best_x = a
        best_value = fa
    end
    fb::Float64 = f(b)
    if isfinite(fb) && fb >= best_value
        best_x = b
        best_value = fb
    end
    return best_x
end

"""
    maximize_1d(f::F, a::Float64, b::Float64, x0::Float64, w::Float64, tol::Float64; max_iter::Int = 64) where {F}

Seeded Brent maximization of `f` over the full bracket `[a, b]`, starting
from the seed `x0` with the window half-width `w` (see `MDR-0002` and
`MDR-0012`). The full bracket is needed because of the fallback below.
Arguments are the objective `f`, the bracket endpoints `a` and `b`, the seed
`x0`, the half-width `w`, the tolerance `tol`, and the iteration guard
`max_iter`. Returns the maximizer: the seed `x0` clamped to `[a, b]` when
`f(x0)` is finite and neither neighbour probe at the resolution `tol` beats
it; otherwise the best finite sample among the seed, the probes, the window
`[max(a, x0 - w), min(b, x0 + w)]`, and the full bracket, where the two
window endpoints are evaluated as candidates so that a maximizer
constrained by the window sits exactly on the edge. Falls back to the full
bracket when that point lies on an interior window edge or the window holds
no finite sample. Returns `NaN` only when neither search found a finite
sample.
"""
function maximize_1d(
        f::F, a::Float64, b::Float64, x0::Float64, w::Float64, tol::Float64;
        max_iter::Int = 64
    ) where {F}
    xs::Float64 = clamp(x0, a, b)
    f0::Float64 = f(xs)
    seed_x::Float64 = NaN
    seed_value::Float64 = -Inf
    if isfinite(f0)
        seed_x = xs
        seed_value = f0
        improves::Bool = false
        if xs - tol >= a
            fm::Float64 = f(xs - tol)
            if isfinite(fm) && fm > seed_value
                seed_x = xs - tol
                seed_value = fm
            end
            if fm > f0
                improves = true
            end
        end
        if xs + tol <= b
            fp::Float64 = f(xs + tol)
            if isfinite(fp) && fp > seed_value
                seed_x = xs + tol
                seed_value = fp
            end
            if fp > f0
                improves = true
            end
        end
        if !improves
            return xs
        end
    end
    wa::Float64 = max(a, xs - w)
    wb::Float64 = min(b, xs + w)
    window_x::Float64 = NaN
    window_value::Float64 = -Inf
    if wa < wb
        window_x, window_value = _brent_maximize(f, wa, wb, tol, max_iter)
    end
    fa::Float64 = f(wa)
    if isfinite(fa) && fa >= window_value
        window_x = wa
        window_value = fa
    end
    fb::Float64 = f(wb)
    if isfinite(fb) && fb >= window_value
        window_x = wb
        window_value = fb
    end
    on_edge::Bool = (window_x == wa && wa != a) || (window_x == wb && wb != b)
    if !isfinite(window_value) || on_edge
        full_x, full_value = _brent_maximize(f, a, b, tol, max_iter)
        best_x::Float64 = window_x
        best_value::Float64 = window_value
        if isfinite(full_value) && full_value > best_value
            best_x = full_x
            best_value = full_value
        end
        if isfinite(seed_value) && seed_value > best_value
            best_x = seed_x
            best_value = seed_value
        end
        if isfinite(best_value)
            return best_x
        end
        return isfinite(full_value) ? full_x : NaN
    end
    if isfinite(seed_value) && seed_value > window_value
        return seed_x
    end
    return window_x
end

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
    _material_log_derivatives(func::UtilitySpec, obj::BestResponseObjective, x::Float64, Q::Float64, A::Float64)

Per-spec material part `(g_mat, g_prime_mat, mval)` of
`_best_response_derivatives` (`MDR-0017`, see `ADR-0022`): the
log-utility derivative `g_mat = d log(material)/dh` and its derivative
`g_prime_mat`, plus the material value `mval` of the same pass (bitwise
the material branch the call overload takes at this role and spec). The
coefficient `A` enters the derivative formulas; `x` and `Q` are the
exact-grouping values of the call overload. The fallback method fails
open with `(NaN, NaN, NaN)` for an unenveloped spec. See `MDR-0017` for
the formulas.
"""
function _material_log_derivatives(
        func::UtilitySpec, obj::BestResponseObjective, x::Float64, Q::Float64, A::Float64
    )
    return (NaN, NaN, NaN)
end

function _material_log_derivatives(
        func::Multiplicative, obj::BestResponseObjective, x::Float64, Q::Float64, A::Float64
    )
    inv_x = 1.0 / x
    inv_Q = 1.0 / Q
    ax = A * inv_x
    g_mat = 0.5 * (ax - inv_Q)
    g_prime_mat = -0.5 * (ax * ax + inv_Q * inv_Q)
    mval = sqrt(x) * sqrt(Q)
    return (g_mat, g_prime_mat, mval)
end

function _material_log_derivatives(
        func::MultiplicativeWeighted, obj::BestResponseObjective,
        x::Float64, Q::Float64, A::Float64
    )
    inv_x = 1.0 / x
    inv_Q = 1.0 / Q
    ax = A * inv_x
    if obj.recipient
        g_mat = obj.alpha * ax - obj.one_minus_alpha * inv_Q
        g_prime_mat = -(obj.alpha * (ax * ax) + obj.one_minus_alpha * (inv_Q * inv_Q))
        mval = x^obj.alpha * Q^obj.one_minus_alpha
    else
        # The preserved NetLogo quirk branch of the call overload,
        # `(x^alpha * Q)^(1-alpha)` (see `MDR-0003`).
        g_mat = obj.one_minus_alpha * (obj.alpha * ax - inv_Q)
        g_prime_mat = -obj.one_minus_alpha * (obj.alpha * (ax * ax) + inv_Q * inv_Q)
        mval = (x^obj.alpha * Q)^obj.one_minus_alpha
    end
    return (g_mat, g_prime_mat, mval)
end

function _material_log_derivatives(
        func::Additive, obj::BestResponseObjective, x::Float64, Q::Float64, A::Float64
    )
    r = sqrt(x)
    s = sqrt(Q)
    m = obj.alpha * r + obj.one_minus_alpha * s
    m_prime = 0.5 * (obj.alpha * A / r - obj.one_minus_alpha / s)
    m_second = -0.25 * (obj.alpha * (A * A) / (x * r) + obj.one_minus_alpha / (Q * s))
    inv_m = 1.0 / m
    g_mat = m_prime * inv_m
    g_prime_mat = m_second * inv_m - g_mat * g_mat
    return (g_mat, g_prime_mat, m)
end

function _material_log_derivatives(
        func::CES, obj::BestResponseObjective, x::Float64, Q::Float64, A::Float64
    )
    beta = func.beta
    if beta == 0.5
        # The sqrt/square `material` specialization of `MDR-0013`:
        # `material == m * m`, so `log(U) = 2 * log(m) + norm` and the
        # derivative pair is the twice-scaled `Additive` log form.
        r = sqrt(x)
        s = sqrt(Q)
        m = obj.alpha * r + obj.one_minus_alpha * s
        m_prime = 0.5 * (obj.alpha * A / r - obj.one_minus_alpha / s)
        m_second = -0.25 * (obj.alpha * (A * A) / (x * r) + obj.one_minus_alpha / (Q * s))
        inv_m = 1.0 / m
        g_over_m = m_prime * inv_m
        g_mat = 2.0 * g_over_m
        g_prime_mat = 2.0 * (m_second * inv_m - g_over_m * g_over_m)
        return (g_mat, g_prime_mat, m * m)
    end
    if beta == 1.0
        # Linear material, a special case of the general form below that
        # avoids the `0 * Inf` of the `T` term of `g_prime_mat` at the
        # guarded boundary: `s_sum` is the `pow(x, 1) == x` grouping of
        # `material(::CES, ...)` (IEEE 754).
        s_sum = obj.alpha * x + obj.one_minus_alpha * Q
        d = obj.alpha * A - obj.one_minus_alpha
        g_mat = d / s_sum
        return (g_mat, -g_mat * g_mat, s_sum)
    end
    xb = x^beta
    Qb = Q^beta
    s_sum = obj.alpha * xb + obj.one_minus_alpha * Qb
    inv_x = 1.0 / x
    inv_Q = 1.0 / Q
    xbm = xb * inv_x
    Qbm = Qb * inv_Q
    d = obj.alpha * A * xbm - obj.one_minus_alpha * Qbm
    t = obj.alpha * (A * A) * (xbm * inv_x) + obj.one_minus_alpha * (Qbm * inv_Q)
    inv_s_sum = 1.0 / s_sum
    g_mat = d * inv_s_sum
    g_prime_mat = (beta - 1.0) * (t * inv_s_sum) - beta * g_mat * g_mat
    return (g_mat, g_prime_mat, s_sum^(1.0 / beta))
end

"""
    _gradient_sign_residual(func::UtilitySpec, obj::BestResponseObjective, x::Float64, Q::Float64, A::Float64, n_prime::Float64)

Per-spec division-free sign residual of the total log-derivative `g`
of `MDR-0017` for the derivative sign probes (`_gradient_sign_at`, see
`ADR-0022`): `g` multiplied through by the spec's positive denominator
`den`, `residual = den * g = num + n_prime * den`, so the residual's
sign is the analytic sign of `g` (exactly in exact arithmetic) while
the probe evaluates products instead of divisions. The norm slope
`n_prime = -2 * conformism * norm_weight * (h - norm_hours)` is
supplied by the caller and multiplied through by the same `den`. The
exact formulas (the `MDR-0017` sign forms, `den > 0` throughout) are:

- Multiplicative (`den = 2*x*Q`): `A*Q - x + 2*n_prime*x*Q`.
- MultiplicativeWeighted recipient (`den = x*Q`):
  `alpha*A*Q - (1-alpha)*x + n_prime*x*Q`.
- MultiplicativeWeighted payer (`den = x*Q`, the preserved NetLogo
  quirk branch of `MDR-0003`):
  `(1-alpha)*(alpha*A*Q - x) + n_prime*x*Q`.
- Additive (`den = m*r*s`, `r = sqrt(x)`, `s = sqrt(Q)`, `m = alpha*r +
  (1-alpha)*s`): `0.5*(alpha*A*s - (1-alpha)*r) + n_prime*m*r*s`.
- CES `beta == 0.5` (`den = m*r*s` as above):
  `alpha*A*s - (1-alpha)*r + n_prime*m*r*s`.
- CES `beta == 1` (`den = S`, `S = alpha*x + (1-alpha)*Q`):
  `D + n_prime*S` with `D = alpha*A - (1-alpha)`.
- CES general (`den = S*x*Q`, `S = alpha*x^beta + (1-alpha)*Q^beta`):
  `alpha*A*x^beta*Q - (1-alpha)*Q^beta*x + n_prime*S*x*Q` (two `pow`
  calls, no division).

The residual sign is the analytic sign of `g` up to the rounding of
this MULTIPLIED-THROUGH form (a different rounding of `g` than the
Newton loop's `_best_response_derivatives` `g`): a spurious sign flip
needs the residual within rounding noise of zero, in which case the
true root sits in the probe window up to noise / `|g'|` (the `MDR-0017`
probe noise note). Fails open with `NaN` (the probe is skipped, never
fatal) for an unenveloped spec, when a positive denominator product
(`x * Q`, or `sqrt(x) * sqrt(Q)`) or the `den` of the `beta == 1` form
is non-finite or subnormal, or when the residual is non-finite.
"""
function _gradient_sign_residual(
        func::UtilitySpec, obj::BestResponseObjective,
        x::Float64, Q::Float64, A::Float64, n_prime::Float64,
    )::Float64
    return NaN
end

function _gradient_sign_residual(
        func::Multiplicative, obj::BestResponseObjective,
        x::Float64, Q::Float64, A::Float64, n_prime::Float64,
    )::Float64
    xQ = x * Q
    (isfinite(xQ) && xQ >= floatmin(Float64)) || return NaN
    residual = A * Q - x + 2.0 * (n_prime * xQ)
    return isfinite(residual) ? residual : NaN
end

function _gradient_sign_residual(
        func::MultiplicativeWeighted, obj::BestResponseObjective,
        x::Float64, Q::Float64, A::Float64, n_prime::Float64,
    )::Float64
    xQ = x * Q
    (isfinite(xQ) && xQ >= floatmin(Float64)) || return NaN
    residual = if obj.recipient
        obj.alpha * A * Q - obj.one_minus_alpha * x + n_prime * xQ
    else
        # The preserved NetLogo quirk branch of the call overload,
        # `(x^alpha * Q)^(1-alpha)` (see `MDR-0003`).
        obj.one_minus_alpha * (obj.alpha * A * Q - x) + n_prime * xQ
    end
    return isfinite(residual) ? residual : NaN
end

function _gradient_sign_residual(
        func::Additive, obj::BestResponseObjective,
        x::Float64, Q::Float64, A::Float64, n_prime::Float64,
    )::Float64
    r = sqrt(x)
    s = sqrt(Q)
    rs = r * s
    (isfinite(rs) && rs >= floatmin(Float64)) || return NaN
    m = obj.alpha * r + obj.one_minus_alpha * s
    residual = 0.5 * (obj.alpha * A * s - obj.one_minus_alpha * r) + (n_prime * m) * rs
    return isfinite(residual) ? residual : NaN
end

function _gradient_sign_residual(
        func::CES, obj::BestResponseObjective,
        x::Float64, Q::Float64, A::Float64, n_prime::Float64,
    )::Float64
    beta = func.beta
    if beta == 0.5
        # The sqrt/square `material` specialization of `MDR-0013`
        # doubles the `Additive` log form, halving its numerator.
        r = sqrt(x)
        s = sqrt(Q)
        rs = r * s
        (isfinite(rs) && rs >= floatmin(Float64)) || return NaN
        m = obj.alpha * r + obj.one_minus_alpha * s
        residual = obj.alpha * A * s - obj.one_minus_alpha * r + (n_prime * m) * rs
        return isfinite(residual) ? residual : NaN
    end
    if beta == 1.0
        s_sum = obj.alpha * x + obj.one_minus_alpha * Q
        (isfinite(s_sum) && s_sum >= floatmin(Float64)) || return NaN
        d = obj.alpha * A - obj.one_minus_alpha
        residual = d + n_prime * s_sum
        return isfinite(residual) ? residual : NaN
    end
    xb = x^beta
    Qb = Q^beta
    s_sum = obj.alpha * xb + obj.one_minus_alpha * Qb
    xQ = x * Q
    (isfinite(xQ) && xQ >= floatmin(Float64)) || return NaN
    residual = obj.alpha * A * (xb * Q) - obj.one_minus_alpha * (Qb * x) +
        n_prime * (s_sum * xQ)
    return isfinite(residual) ? residual : NaN
end

"""
    _best_response_derivatives(obj::BestResponseObjective{S}, h::Float64)

Combined derivative evaluation of the best-response solve of `MDR-0017`
(see `ADR-0022`): one pass over the exact `x`, `Q`, and `norm` groupings
of the `(obj::BestResponseObjective)(h)` call overload computes the
log-utility derivative `g = d log(U)/dh`, its derivative
`g_prime = d2 log(U)/dh2` (the material part of
`_material_log_derivatives` plus the norm terms `n'(h) = -2 *
conformism * norm_weight * (h - norm_hours)` and `n'' = -2 *
conformism * norm_weight`), and the objective `value`, which is bitwise
`obj(h)`. Returns `(g, g_prime, value)`, or `(NaN, NaN, NaN)` (fail open
to the `MDR-0002` fallback) when the point leaves the guarded domain
(`x <= 0`, `Q <= 0`, `h` outside `[0, 1]`, spouse hours outside
`[0, 1]`), when `x` or `Q` is subnormal, when a material intermediate is
non-finite or subnormal, or when `g`, `g_prime`, or `value` is non-finite
or the value is subnormal (the `_envelope_peak` guard style of
`ADR-0015`).
"""
function _best_response_derivatives(
        obj::BestResponseObjective{S}, h::Float64
    )::Tuple{Float64, Float64, Float64} where {S}
    x = obj.recipient ? (h * obj.wage_self + obj.transfer_income) :
        ((h * obj.wage_self) * obj.one_minus_transfer)
    Q = (2 - h) - obj.h_spouse
    if !(x >= floatmin(Float64)) || !(Q >= floatmin(Float64)) ||
            h < 0.0 || h > 1.0 || obj.spouse_out_of_range
        return (NaN, NaN, NaN)
    end
    A = obj.recipient ? obj.wage_self : obj.wage_self * obj.one_minus_transfer
    g_mat, g_prime_mat, mval = _material_log_derivatives(obj.func, obj, x, Q, A)
    (isfinite(g_mat) && isfinite(g_prime_mat)) || return (NaN, NaN, NaN)
    (isfinite(mval) && mval >= floatmin(Float64)) || return (NaN, NaN, NaN)
    dh = h - obj.norm_hours
    norm = -obj.conformism * (
        (obj.norm_weight * (dh * dh) + obj.norm_transfer) + obj.norm_spouse
    )
    value = mval * exp(norm)
    k = obj.conformism * obj.norm_weight
    g = g_mat - 2.0 * k * dh
    g_prime = g_prime_mat - 2.0 * k
    if isfinite(g) && isfinite(g_prime) && isfinite(value) && value >= floatmin(Float64)
        return (g, g_prime, value)
    end
    return (NaN, NaN, NaN)
end

"""
    _best_response_gradient_sign(obj::BestResponseObjective{S}, h::Float64)

Derivative sign probe of the enclosure checks of `MDR-0017` (see
`ADR-0022`): the division-free sign residual of
`_gradient_sign_residual` at `h` (its sign is the analytic sign of the
log-utility derivative `g`, computed by the multiplied-through form of
`MDR-0017` instead of the solver's `g` value). Computes the
consumption coefficient `A` and the norm slope factor `k` and
delegates to `_gradient_sign_at`, so the tier-1 certificate can share
`A` and `k` across its two probes. Consumers use only the sign of the
result. Returns `NaN` when the probe
is skipped (never fatal): outside the guarded domain (`h` outside `[0, 1]`,
`x` or `Q` subnormal or smaller, spouse hours outside `[0, 1]`), when a
positive denominator product of the sign form (`x * Q`, or `sqrt(x) *
sqrt(Q)`) is non-finite or subnormal, or when the computed residual is
non-finite. The skipped-probe semantics are the
`MDR-0017` enclosure rule: a probe that leaves the feasible interval or
hits a guard cannot confirm an enclosure.
"""
function _best_response_gradient_sign(
        obj::BestResponseObjective{S}, h::Float64
    )::Float64 where {S}
    A = obj.recipient ? obj.wage_self : obj.wage_self * obj.one_minus_transfer
    k = obj.conformism * obj.norm_weight
    return _gradient_sign_at(obj, h, A, k)
end

"""
    _gradient_sign_at(obj::BestResponseObjective{S}, h::Float64, A::Float64, k::Float64)

Probe core of `_best_response_gradient_sign` with the shared
coefficients `A` (the consumption coefficient) and `k = conformism *
norm_weight` (the norm slope factor) supplied by the caller, so the
two probes of the tier-1 seed certificate compute them once. Returns
the `_gradient_sign_residual` sign residual of `g` (whose sign is the
analytic sign of the solver's `g`, see there), with the exact `x`, `Q`,
and `n_prime` groupings and the point guards and `NaN` skip semantics
of `_best_response_gradient_sign`. Returns a `Float64`.
"""
function _gradient_sign_at(
        obj::BestResponseObjective{S}, h::Float64, A::Float64, k::Float64
    )::Float64 where {S}
    x = obj.recipient ? (h * obj.wage_self + obj.transfer_income) :
        ((h * obj.wage_self) * obj.one_minus_transfer)
    Q = (2 - h) - obj.h_spouse
    if !(x >= floatmin(Float64)) || !(Q >= floatmin(Float64)) ||
            h < 0.0 || h > 1.0 || obj.spouse_out_of_range
        return NaN
    end
    dh = h - obj.norm_hours
    n_prime = -2.0 * k * dh
    isfinite(n_prime) || return NaN
    return _gradient_sign_residual(obj.func, obj, x, Q, A, n_prime)
end

"""
    _one_sided_gradient(obj::BestResponseObjective{S}, at_lower::Bool)

Analytic one-sided limit of the total log-utility derivative `g` of
`MDR-0017` (see `ADR-0022`) at a guard-infeasible endpoint of the
feasible interval: `h -> 0+` when `x(0) == 0` removes the lower
endpoint (`B == 0` with `A > 0`), `h -> 1-` when `Q(1) == 0` removes
the upper one (`h_spouse == 1`). The limit is `+Inf` at `x -> 0+`
(`Multiplicative`; the weighted specs when the `1/x` coefficient is
positive; `Additive` and `CES` `beta < 1` at `alpha > 0`; `CES`
`beta == 1` at `alpha == 1`) and `-Inf` at `Q -> 0+`
(`Multiplicative`; whenever a `1/Q` or `1/sqrt(Q)` coefficient is
negative, i.e. `alpha < 1` outside `CES` `beta == 1`). The nonsingular
cases return their finite analytic limit, material part plus the norm
slope `n'(h)`: `CES` `beta == 1` has `g = D / S` with `D = alpha * A -
(1 - alpha)` and `S -> (1 - alpha) * Q(0)` at the lower end, `S ->
alpha * x(1)` at the upper end; `Additive` at `alpha == 0` has
`-0.5 / Q(0)`; the `MultiplicativeWeighted` quirk branch at
`alpha == 1` is the constant material with zero material part. The
solve brackets with the limit only when it points away from the
infeasible endpoint (positive at the lower end, negative at the upper
end); a zero or opposite-signed limit (the unattainable supremum, e.g.
`alpha == 0` with `B == 0` at the lower end, where `U` rises toward
the infeasible `h -> 0+`) or an indeterminate form (`NaN`) makes the
solve fall back to `MDR-0002`. Returns a `Float64`.
"""
function _one_sided_gradient(
        obj::BestResponseObjective{S}, at_lower::Bool
    )::Float64 where {S}
    func = obj.func
    A = obj.recipient ? obj.wage_self : obj.wage_self * obj.one_minus_transfer
    k = obj.conformism * obj.norm_weight
    local g_mat::Float64
    if at_lower
        Q0 = 2.0 - obj.h_spouse
        if func isa Multiplicative
            return Inf
        elseif func isa MultiplicativeWeighted
            if obj.recipient
                g_mat = obj.alpha > 0.0 ? Inf : -1.0 / Q0
            else
                g_mat = obj.alpha == 1.0 ? 0.0 :
                    (obj.alpha > 0.0 ? Inf : -1.0 / Q0)
            end
        elseif func isa Additive
            g_mat = obj.alpha > 0.0 ? Inf : -0.5 / Q0
        elseif func isa CES
            if func.beta == 1.0
                g_mat = obj.alpha == 1.0 ? Inf :
                    (obj.alpha * A - obj.one_minus_alpha) /
                    (obj.one_minus_alpha * Q0)
            else
                g_mat = obj.alpha > 0.0 ? Inf : -1.0 / Q0
            end
        else
            return NaN
        end
        isfinite(g_mat) || return g_mat
        n_prime = 2.0 * k * obj.norm_hours
        return isfinite(n_prime) ? g_mat + n_prime : NaN
    end
    x1 = obj.recipient ? (obj.wage_self + obj.transfer_income) : A
    if func isa Multiplicative
        return -Inf
    elseif func isa MultiplicativeWeighted
        if obj.recipient
            g_mat = obj.alpha < 1.0 ? -Inf : A / x1
        else
            g_mat = obj.alpha < 1.0 ? -Inf : 0.0
        end
    elseif func isa Additive
        g_mat = obj.alpha < 1.0 ? -Inf : 0.5 * A / x1
    elseif func isa CES
        if func.beta == 1.0
            g_mat = obj.alpha == 0.0 ? -Inf :
                (obj.alpha * A - obj.one_minus_alpha) / (obj.alpha * x1)
        else
            g_mat = obj.alpha < 1.0 ? -Inf : A / x1
        end
    else
        return NaN
    end
    isfinite(g_mat) || return g_mat
    n_prime = -2.0 * k * (1.0 - obj.norm_hours)
    return isfinite(n_prime) ? g_mat + n_prime : NaN
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
