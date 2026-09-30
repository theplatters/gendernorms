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
struct BestResponseObjective{S<:UtilitySpec}
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
"""
function best_response_1d(U::F, h_start::Float64) where {F}
    return maximize_1d(U, 0.0, 1.0, h_start, BEST_RESPONSE_WINDOW, BEST_RESPONSE_TOL)
end
