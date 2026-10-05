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

"""
    material(::MultiplicativeWeighted, x::Float64, Q::Float64, alpha::Float64)

MultiplicativeWeighted material utility (ODD section Material utility):
the Cobb-Douglas form `x^alpha * Q^(1 - alpha)` for both roles. The
NetLogo `calculate-utility` payer branch of this spec, the
wrong-parenthesis form `(x^alpha * Q)^(1 - alpha)`, is removed and the
intended form applies to payer and recipient alike (recorded deviation
`MDR-0023`).
"""
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
    _material_envelope(spec::UtilitySpec, q::Float64, d::Float64, alpha::Float64)

Fail-open fallback of `_material_envelope(::Additive, ...)`: a
`UtilitySpec` subtype without a certified envelope yields `NaN`, so the
certificate never certifies on an unenveloped spec and falls back to
the full solve (see `ADR-0015`).
"""
_material_envelope(::UtilitySpec, q::Float64, d::Float64, alpha::Float64)::Float64 = NaN

"""
    _material_envelope(::Additive, q::Float64, d::Float64, alpha::Float64)

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
non-finite or subnormal (see `_envelope_peak`). Certification helper of
`ADR-0015`, not a ported NetLogo behavior.
"""
function _material_envelope(
        ::Additive, q::Float64, d::Float64, alpha::Float64
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

"""
    _material_envelope(u::CES, q::Float64, d::Float64, alpha::Float64)

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
floor when the whole sum underflows. See `ADR-0015` and `ADR-0019`.
"""
function _material_envelope(
        u::CES, q::Float64, d::Float64, alpha::Float64
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
    _material_envelope(::Multiplicative, q::Float64, d::Float64, alpha::Float64)

Multiplicative envelope of `_material_envelope(::Additive, ...)`: the
maximizer of `sqrt(q*v)*sqrt(2-v)` is `v* = min(d, 1)`. `alpha` does
not enter the material function, but the uniform input guards apply.
See `ADR-0015`.
"""
function _material_envelope(
        ::Multiplicative, q::Float64, d::Float64, alpha::Float64
    )::Float64
    ok = isfinite(q) && q > 0.0 && isfinite(d) && d > 0.0 &&
        isfinite(alpha) && 0.0 <= alpha <= 1.0
    ok || return NaN
    v_star = min(d, 1.0)
    return _envelope_peak(v -> sqrt(q * v) * sqrt(2.0 - v), q, d, v_star)
end

"""
    _material_envelope(::MultiplicativeWeighted, q::Float64, d::Float64, alpha::Float64)

MultiplicativeWeighted envelope of `_material_envelope(::Additive,
...)`: the single `material` form `x^alpha * Q^(1-alpha)` with
maximizer `v* = clamp(2*alpha, 0, d)`, for both roles. Both roles use
this intended Cobb-Douglas form; the NetLogo payer branch of
`calculate-utility`, `(x^alpha * Q)^(1-alpha)` with maximizer
`2*alpha/(1+alpha)`, is removed as a recorded deviation of `MDR-0023`.
See `ADR-0015`.
"""
function _material_envelope(
        ::MultiplicativeWeighted, q::Float64, d::Float64, alpha::Float64
    )::Float64
    ok = isfinite(q) && q > 0.0 && isfinite(d) && d > 0.0 &&
        isfinite(alpha) && 0.0 <= alpha <= 1.0
    ok || return NaN
    v_star = clamp(2.0 * alpha, 0.0, d)
    return _envelope_peak(v -> (q * v)^alpha * (2.0 - v)^(1.0 - alpha), q, d, v_star)
end

"""
    AgentPayoffParams{G<:Gender}

Transient per-agent parameter object of the household bargaining: own and
spouse wage, material preference `alpha`, conformism, the perceived norms
`N_h` (own working time), `N_theta` (transfer), and `N_h_spouse` (spouse
working time). The `Gender` marker type parameter `G` is `Male` or
`Female` (from `src/components.jl`) and marks the agent's sex for the
role dispatch of `_get_relevant_transfer`; it replaces the deleted
`is_woman` field (see `ADR-0029`). `set_theta!` builds it at the
`mutual_best_response` call and the solver passes it to
`individual_utility`; it is never stored or returned (see `ADR-0007`).
"""
Base.@kwdef struct AgentPayoffParams{G <: Gender}
    wage_self::Float64 = 1.0
    wage_spouse::Float64 = 1.0
    alpha::Float64 = 0.5
    conformism::Float64 = 0.0
    N_h::Float64 = 0.5
    N_theta::Float64 = 0.0
    N_h_spouse::Float64 = 0.5
end

"""
    BestResponseObjective{S<:UtilitySpec,Recipient}

Prepared own-hours objective of one `best_response_1d` call (see
`MDR-0013` and `ADR-0018`): the `individual_utility` of one partner at
fixed spouse hours and fixed transfer, with every transfer- and
spouse-dependent term hoisted out of the per-hours evaluation. Built by
`BestResponseObjective(theta, h_spouse, self_params, config)` and called
as `obj(h::Float64)`; an isbits callable that allocates nothing and
keeps the `UtilitySpec` type `S` static for the material dispatch (the
`MDR-0002` no-boxing discipline, now structural: `mutual_best_response`
passes this callable instead of a closure). The `S<:UtilitySpec` type
parameter is the material spec of the config; the `Recipient::Bool`
type parameter marks the partner role (`true` = recipient) and replaces
the deleted `recipient` field with a static marker (see `ADR-0029`):
it selects the call overload and with it the consumption form of `x`
(see below) without a runtime branch. Fields hold the hoisted
consumption terms `wage_self`, `transfer_income`, and
`one_minus_transfer` of `x` (the recipient's `h * wage_self +
transfer_income` with `transfer_income = abs(relevant_transfer) *
wage_spouse * h_spouse`, the payer's `(h * wage_self) *
one_minus_transfer`), the fixed spouse hours `h_spouse` of `Q = (2 -
h) - h_spouse`, the hoisted transfer and spouse norm products
`norm_transfer` and `norm_spouse` of `norm = -conformism *
((norm_weight * (h - norm_hours)^2 + norm_transfer) + norm_spouse)`,
the material
preference `alpha` with its hoisted complement `one_minus_alpha`, and
the spouse-hours guard `spouse_out_of_range`. Every formula keeps
the exact expression grouping of `individual_utility`, so the
evaluation is bitwise identical to it (CSE-style hoisting only; the
regrouped coefficient form of `MDR-0013` was measured and dropped,
see the record). The formula is the `individual_utility` of NetLogo
`calculate-utility` (ODD sections Material utility and conformity
multiplier and Norm perception), with the `MultiplicativeWeighted`
deviation of `MDR-0023` (both roles use the intended Cobb-Douglas
material `x^alpha * Q^(1-alpha)`).
"""
struct BestResponseObjective{S <: UtilitySpec, Recipient}
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
    spouse_out_of_range::Bool
end

"""
    BestResponseObjective(theta::Float64, h_spouse::Float64, self_params::AgentPayoffParams, config::UtilityConfig{S}) where {S}

Build the prepared own-hours objective of one `best_response_1d` call
(see `BestResponseObjective` and `MDR-0013`): hoists the transfer- and
spouse-dependent terms of `individual_utility` for own hours `h` at
fixed spouse hours `h_spouse` and fixed transfer `theta`. The role
(`recipient = relevant_transfer < 0`, with `relevant_transfer` from
`_get_relevant_transfer`), the consumption terms of `x`, and the norm
products are computed exactly as `individual_utility` derives them. The
runtime role selects the return type with a static `if recipient`
split: the recipient branch returns `BestResponseObjective{S,true}`,
the payer branch `BestResponseObjective{S,false}`, so every return path
is a concrete isbits type and the method returns the 2-element small
union of the two, never `Any` (the parametric role marker of
`ADR-0029`). Arguments are the transfer `theta`, the spouse hours
`h_spouse`, the transient parameter bundle `self_params`, and the
utility config `config`, whose `UtilitySpec` type `S` is carried to the
result. Returns the callable objective.
"""
function BestResponseObjective(
        theta::Float64, h_spouse::Float64,
        self_params::AgentPayoffParams, config::UtilityConfig{S}
    ) where {S}
    relevant_transfer = _get_relevant_transfer(theta, self_params)
    recipient = relevant_transfer < 0
    transfer_income = 0.0
    one_minus_transfer = 1.0
    if recipient
        transfer_income = abs(relevant_transfer) * self_params.wage_spouse * h_spouse
    else
        one_minus_transfer = 1 - relevant_transfer
    end
    dtheta = theta - self_params.N_theta
    d_spouse = h_spouse - self_params.N_h_spouse
    args = (
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
        h_spouse < 0 || h_spouse > 1,
    )
    if recipient
        return BestResponseObjective{S, true}(args...)
    else
        return BestResponseObjective{S, false}(args...)
    end
end

# Role-dispatched consumption geometry (see `ADR-0029`): the signed
# transfer and the consumption `x` of one partner with its linear
# coefficients `A` (slope in own hours) and `B` (intercept), selected by
# the `Gender` marker of `AgentPayoffParams` and the `Recipient` marker
# of `BestResponseObjective` instead of the deleted `is_woman` and
# `recipient` fields. Every expression keeps the exact grouping of
# `individual_utility` and its call overloads.

"""
    _get_relevant_transfer(theta::Float64, self_params::AgentPayoffParams)

Signed transfer of the household transfer `theta` (positive from the
man to the woman) from the perspective of partner `self_params`, of
NetLogo `calculate-utility` (ODD section Material utility and
conformity multiplier): `theta` for the man
(`AgentPayoffParams{Male}`), `-theta` for the woman
(`AgentPayoffParams{Female}`), so a positive value is a transfer the
partner pays and a negative value one the partner receives. The
`Gender` marker type parameter selects the sign by role dispatch (the
parametric replacement of the deleted `is_woman` field, `ADR-0029`).
Returns the signed transfer; `relevant_transfer < 0` marks the
recipient role.
"""
_get_relevant_transfer(theta, ::AgentPayoffParams{Male}) = theta
_get_relevant_transfer(theta, ::AgentPayoffParams{Female}) = -theta

"""
    _x_for_gradient(h, obj::BestResponseObjective)

Consumption `x` at own hours `h` in the exact expression grouping of
the `(obj::BestResponseObjective)(h::Float64)` call overloads (see
`_eval_objective_function`): the recipient's `h * wage_self +
transfer_income` and the payer's `(h * wage_self) *
one_minus_transfer`, dispatched on the `Recipient` marker type
parameter (`ADR-0029`). The derivative and sign probes of `MDR-0017`
(`_best_response_derivatives`, `_gradient_sign_at`) must evaluate
bitwise the `x` the objective call evaluates, hence the shared helper.
Returns a `Float64`.
"""
function _x_for_gradient(h, obj::BestResponseObjective{S, true}) where {S}
    return (h * obj.wage_self + obj.transfer_income)
end

function _x_for_gradient(h, obj::BestResponseObjective{S, false}) where {S}
    return ((h * obj.wage_self) * obj.one_minus_transfer)
end

"""
    _A_for_gradient(obj::BestResponseObjective)

Consumption slope `A` in the exact expression grouping of the
derivative solve of `MDR-0017` (`_best_response_derivatives`,
`_best_response_gradient_sign`): the recipient's `wage_self` and the
payer's `wage_self * one_minus_transfer`, dispatched on the `Recipient`
marker type parameter (`ADR-0029`). Same coefficient as
`_consumption_slope`, named for the derivative formulas that use `A`
as their `dx/dh` factor. Returns a `Float64`.
"""
_A_for_gradient(obj::BestResponseObjective{S, true}) where {S} = obj.wage_self
function _A_for_gradient(obj::BestResponseObjective{S, false}) where {S}
    return obj.wage_self * obj.one_minus_transfer
end

"""
    _consumption_slope(obj::BestResponseObjective)

Consumption slope `A` of one partner: the coefficient of own hours in
the call overload's `x`, the recipient's `wage_self` and the payer's
`wage_self * one_minus_transfer`, dispatched on the `Recipient` marker
type parameter (`ADR-0029`). Role-dispatch helper of the derivative
solve of `MDR-0017` (`_derivative_applicable`,
`_derivative_seed_certificate`, `_one_sided_gradient`,
`_derivative_best_response`); with `_consumption_intercept` it replaces
the deleted `obj.recipient` field reads. Returns a `Float64`.
"""
_consumption_slope(obj::BestResponseObjective{S, true}) where {S} =
    obj.wage_self

function _consumption_slope(obj::BestResponseObjective{S, false}) where {S}
    return obj.wage_self * obj.one_minus_transfer
end

"""
    _consumption_at_upper(obj::BestResponseObjective, A::Float64)

Consumption `x` at own hours `h == 1`, computed from the slope `A` of
`_consumption_slope`: the recipient's `A + transfer_income` and the
payer's `A` (zero intercept), dispatched on the `Recipient` marker
type parameter (`ADR-0029`). Supplies the upper-endpoint consumption
`x1` of `_one_sided_gradient` and `_upper_material_gradient` (`MDR-0017`).
Returns a `Float64`.
"""
_consumption_at_upper(
    obj::BestResponseObjective{S, true}, A::Float64
) where {S} = A + obj.transfer_income

_consumption_at_upper(
    ::BestResponseObjective{S, false}, A::Float64
) where {S} = A

"""
    _consumption_intercept(obj::BestResponseObjective)

Consumption intercept `B` of one partner: the constant term of the
call overload's `x`, the recipient's `transfer_income` and the payer's
`0.0`, dispatched on the `Recipient` marker type parameter
(`ADR-0029`). With `_consumption_slope` it replaces the deleted
`obj.recipient` field reads and drives the lower-endpoint test
`B == 0 && A > 0` (`x(0) == 0`) of `_derivative_applicable` and
`_derivative_best_response` (`MDR-0017`). Returns a `Float64`.
"""
_consumption_intercept(
    obj::BestResponseObjective{S, true}
) where {S} = obj.transfer_income

_consumption_intercept(
    ::BestResponseObjective{S, false}
) where {S} = 0.0

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
function (obj::BestResponseObjective{S, true})(h::Float64) where {S}
    x = (h * obj.wage_self + obj.transfer_income)
    return _eval_objective_function(h, x, obj)
end

function (obj::BestResponseObjective{S, false})(h::Float64) where {S}
    x = ((h * obj.wage_self) * obj.one_minus_transfer)
    return _eval_objective_function(h, x, obj)
end

"""
    _eval_objective_function(h::Float64, x::Float64, obj::BestResponseObjective{S,Recipient}) where {S,Recipient}

Shared evaluation core of the two `(obj::BestResponseObjective)(h::Float64)`
call overloads, given the own hours `h` and the already-evaluated
consumption `x` of the calling role overload and the objective `obj`:
computes `Q = (2 - h) - h_spouse`, applies the feasibility guards of
`individual_utility` (`x <= 0`, `Q <= 0`, `h` outside `[0, 1]`, spouse
hours outside `[0, 1]` return `-Inf`; see `MDR-0013`), and returns
`material(obj.func, x, Q, obj.alpha) * exp(norm)` with `norm =
-conformism * ((norm_weight * (h - norm_hours)^2 + norm_transfer) +
norm_spouse)`, in the exact expression grouping of `individual_utility`
(the NetLogo `calculate-utility` formula, ODD sections Material utility
and conformity multiplier and Norm perception, with the
`MultiplicativeWeighted` deviation of `MDR-0023`). Returns the utility
value (`Float64`).
"""
function _eval_objective_function(
        h::Float64, x::Float64, obj::BestResponseObjective{S, Recipient}
    ) where {S, Recipient}
    Q = (2 - h) - obj.h_spouse
    if x <= 0 || Q <= 0 || h < 0 || h > 1 || obj.spouse_out_of_range
        return -Inf
    end
    dh = h - obj.norm_hours
    norm = -obj.conformism * (
        (obj.norm_weight * (dh * dh) + obj.norm_transfer) + obj.norm_spouse
    )
    material_value = material(obj.func, x, Q, obj.alpha)
    return material_value * exp(norm)
end

"""
    individual_utility(h_self::Float64, h_spouse::Float64, theta::Float64, self_params::AgentPayoffParams, config::UtilityConfig)

Material utility times the conformity multiplier of NetLogo
`calculate-utility` (ODD sections Material utility and conformity multiplier
and Norm perception) for own hours `h_self`, spouse hours `h_spouse`, and
transfer `theta`, evaluated for the transient `AgentPayoffParams` bundle
`self_params` (see `ADR-0007`). For `MultiplicativeWeighted` both
partners use the intended Cobb-Douglas material `x^alpha *
Q^(1-alpha)`; the NetLogo payer branch `(x^alpha * Q)^(1-alpha)` is a
recorded deviation (`MDR-0023`). Returns `-Inf` for infeasible bundles.
Delegates to the prepared own-hours objective `BestResponseObjective`
(one source of truth with the labour solver; see `MDR-0013`).
"""
function individual_utility(
        h_self::Float64, h_spouse::Float64, theta::Float64,
        self_params::AgentPayoffParams, config::UtilityConfig
    )
    return BestResponseObjective(theta, h_spouse, self_params, config)(h_self)
end

"""
    _material_log_derivatives(func::UtilitySpec, obj::BestResponseObjective, x::Float64, Q::Float64, A::Float64)

Per-spec material part `(g_mat, g_prime_mat, mval)` of
`_best_response_derivatives` (`MDR-0017`, see `ADR-0022`): the
log-utility derivative `g_mat = d log(material)/dh` and its derivative
`g_prime_mat`, plus the material value `mval` of the same pass (bitwise
the `material` value the call overload evaluates for this spec). The
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
        ::Multiplicative, obj::BestResponseObjective, x::Float64, Q::Float64, A::Float64
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
        ::MultiplicativeWeighted, obj::BestResponseObjective,
        x::Float64, Q::Float64, A::Float64
    )
    inv_x = 1.0 / x
    inv_Q = 1.0 / Q
    ax = A * inv_x
    g_mat = obj.alpha * ax - obj.one_minus_alpha * inv_Q
    g_prime_mat = -(obj.alpha * (ax * ax) + obj.one_minus_alpha * (inv_Q * inv_Q))
    mval = x^obj.alpha * Q^obj.one_minus_alpha
    return (g_mat, g_prime_mat, mval)
end

function _material_log_derivatives(
        ::Additive, obj::BestResponseObjective, x::Float64, Q::Float64, A::Float64
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
- MultiplicativeWeighted (`den = x*Q`):
  `alpha*A*Q - (1-alpha)*x + n_prime*x*Q`.
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
    residual = obj.alpha * A * Q - obj.one_minus_alpha * x + n_prime * xQ
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
        obj::BestResponseObjective, h::Float64
    )::Tuple{Float64, Float64, Float64}
    x = _x_for_gradient(h, obj)
    Q = (2 - h) - obj.h_spouse
    if !(x >= floatmin(Float64)) || !(Q >= floatmin(Float64)) ||
            h < 0.0 || h > 1.0 || obj.spouse_out_of_range
        return (NaN, NaN, NaN)
    end
    A = _A_for_gradient(obj)
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
_best_response_gradient_sign(
    obj::BestResponseObjective, h::Float64
)::Float64 = _gradient_sign_at(obj, h, _A_for_gradient(obj), obj.conformism * obj.norm_weight)

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
        obj::BestResponseObjective, h::Float64, A::Float64, k::Float64
    )::Float64
    x = _x_for_gradient(h, obj)
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

# Material log-gradient limit at the infeasible lower endpoint.

"""
    _lower_material_gradient(spec::UtilitySpec, obj::BestResponseObjective, A::Float64, Q0::Float64)

Material part `g_mat` of the analytic one-sided limit of
`_one_sided_gradient` at the guard-infeasible lower endpoint `h -> 0+`
(`x(0) == 0`; `MDR-0017`, see `ADR-0022`): the limit of
`d log(material)/dh` as the consumption `x -> 0+`, from the
consumption slope `A` and the endpoint spouse consumption `Q0 = 2 -
h_spouse`. Per spec (role-independent, the `Recipient` role enters only
through `A`; `ADR-0029` and the unified `MultiplicativeWeighted` form
of `MDR-0023`): `Multiplicative` is `+Inf`;
`MultiplicativeWeighted` is `+Inf` at `alpha > 0` and `-1 / Q0` at
`alpha == 0`; `Additive` is `+Inf` at `alpha > 0` and `-0.5 / Q0` at
`alpha == 0`; `CES` `beta == 1` is `D / ((1 - alpha) * Q0)` with `D =
alpha * A - (1 - alpha)`, `+Inf` at `alpha == 1`, and every other
`beta` like `MultiplicativeWeighted`. The fallback fails open with
`NaN` for an unenveloped spec. Returns a `Float64`.
"""
_lower_material_gradient(
    ::UtilitySpec, ::BestResponseObjective, ::Float64, ::Float64
)::Float64 = NaN

_lower_material_gradient(
    ::Multiplicative, ::BestResponseObjective, ::Float64, ::Float64
)::Float64 = Inf

_lower_material_gradient(
    ::MultiplicativeWeighted, obj::BestResponseObjective,
    ::Float64, Q0::Float64
)::Float64 = obj.alpha > 0.0 ? Inf : -1.0 / Q0

_lower_material_gradient(
    ::Additive, obj::BestResponseObjective, ::Float64, Q0::Float64
)::Float64 = obj.alpha > 0.0 ? Inf : -0.5 / Q0

function _lower_material_gradient(
        func::CES, obj::BestResponseObjective, A::Float64, Q0::Float64
    )::Float64
    if func.beta == 1.0
        return obj.alpha == 1.0 ? Inf :
            (obj.alpha * A - obj.one_minus_alpha) /
            (obj.one_minus_alpha * Q0)
    end
    return obj.alpha > 0.0 ? Inf : -1.0 / Q0
end

# Material log-gradient limit at the infeasible upper endpoint.

"""
    _upper_material_gradient(spec::UtilitySpec, obj::BestResponseObjective, A::Float64, x1::Float64)

Material part `g_mat` of the analytic one-sided limit of
`_one_sided_gradient` at the guard-infeasible upper endpoint `h -> 1-`
(`Q(1) == 0`; `MDR-0017`, see `ADR-0022`): the limit of
`d log(material)/dh` as the spouse consumption `Q -> 0+`, from the
consumption slope `A` and the endpoint consumption `x1 =
_consumption_at_upper(obj, A)`. Per spec (role-independent, the
`Recipient` role enters only through `A` and `x1`; `ADR-0029` and the
unified `MultiplicativeWeighted` form of `MDR-0023`):
`Multiplicative` is `-Inf`; `MultiplicativeWeighted` is `-Inf` at
`alpha < 1` and `A / x1` at `alpha == 1`; `Additive` is `-Inf` at
`alpha < 1` and `0.5 * A / x1` at `alpha == 1`; `CES` `beta == 1` is
`D / (alpha * x1)` with `D = alpha * A - (1 - alpha)`, `-Inf` at
`alpha == 0`, and every other `beta` like `MultiplicativeWeighted`.
The fallback fails open with `NaN` for an unenveloped spec. Returns a
`Float64`.
"""
_upper_material_gradient(
    ::UtilitySpec, ::BestResponseObjective, ::Float64, ::Float64
)::Float64 = NaN

_upper_material_gradient(
    ::Multiplicative, ::BestResponseObjective, ::Float64, ::Float64
)::Float64 = -Inf

_upper_material_gradient(
    ::MultiplicativeWeighted, obj::BestResponseObjective,
    A::Float64, x1::Float64
)::Float64 = obj.alpha < 1.0 ? -Inf : A / x1

_upper_material_gradient(
    ::Additive, obj::BestResponseObjective, A::Float64, x1::Float64
)::Float64 = obj.alpha < 1.0 ? -Inf : 0.5 * A / x1

function _upper_material_gradient(
        func::CES, obj::BestResponseObjective, A::Float64, x1::Float64
    )::Float64
    if func.beta == 1.0
        return obj.alpha == 0.0 ? -Inf :
            (obj.alpha * A - obj.one_minus_alpha) / (obj.alpha * x1)
    end
    return obj.alpha < 1.0 ? -Inf : A / x1
end

# Shared endpoint selection, norm slope, and guard handling.

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
`-0.5 / Q(0)`; `MultiplicativeWeighted` at `alpha == 1` has the finite
upper-end material limit `A / x(1)` of the unified Cobb-Douglas form
(its lower-end limit is the `+Inf` of the `1/x` term above; `MDR-0023`,
the NetLogo quirk branch with zero material part is removed). The
material part is the role-independent per-spec dispatch of
`_lower_material_gradient` and `_upper_material_gradient` (the
`Recipient` marker enters only through the consumption terms `A`,
`x(1)`, and `Q(0)`, see
`ADR-0029`). The
solve brackets with the limit only when it points away from the
infeasible endpoint (positive at the lower end, negative at the upper
end); a zero or opposite-signed limit (the unattainable supremum, e.g.
`alpha == 0` with `B == 0` at the lower end, where `U` rises toward
the infeasible `h -> 0+`) or an indeterminate form (`NaN`) makes the
solve fall back to `MDR-0002`. Returns a `Float64`.
"""
function _one_sided_gradient(
        obj::BestResponseObjective, at_lower::Bool
    )::Float64
    A = _consumption_slope(obj)
    k = obj.conformism * obj.norm_weight

    g_mat = if at_lower
        Q0 = 2.0 - obj.h_spouse
        _lower_material_gradient(obj.func, obj, A, Q0)
    else
        x1 = _consumption_at_upper(obj, A)
        _upper_material_gradient(obj.func, obj, A, x1)
    end
    isfinite(g_mat) || return g_mat

    n_prime = at_lower ? 2.0 * k * obj.norm_hours :
        -2.0 * k * (1.0 - obj.norm_hours)
    return isfinite(n_prime) ? g_mat + n_prime : NaN
end
