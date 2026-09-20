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

material(u::CES, x::Float64, Q::Float64, alpha::Float64) =
    (alpha * x^u.beta + (1 - alpha) * Q^u.beta)^(1 / u.beta)

material(::Multiplicative, x::Float64, Q::Float64, alpha::Float64) =
    sqrt(x) * sqrt(Q)

material(::MultiplicativeWeighted, x::Float64, Q::Float64, alpha::Float64) =
    x^alpha * Q^(1 - alpha)

"""
    AgentPayoffParams

Transient per-agent parameter object of the household bargaining: own and
spouse wage, material preference `alpha`, conformism, the perceived norms
`N_h` (own working time), `N_theta` (transfer), and `N_h_spouse` (spouse
working time), and the agent's sex. `choose_bundles` builds it at the
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
    individual_utility(h_self::Float64, h_spouse::Float64, theta::Float64, self_params::AgentPayoffParams, config::UtilityConfig)

Material utility times the conformity multiplier of NetLogo
`calculate-utility` (ODD sections Material utility and conformity multiplier
and Norm perception) for own hours `h_self`, spouse hours `h_spouse`, and
transfer `theta`, evaluated for the transient `AgentPayoffParams` bundle
`self_params` (see `ADR-0007`). Returns `-Inf` for infeasible bundles.
"""
function individual_utility(
        h_self::Float64, h_spouse::Float64, theta::Float64,
        self_params::AgentPayoffParams, config::UtilityConfig
    )
    relevant_transfer = self_params.is_woman ? -theta : theta
    recipient = relevant_transfer < 0
    if recipient
        x = h_self * self_params.wage_self +
            abs(relevant_transfer) * self_params.wage_spouse * h_spouse
    else
        x = h_self * self_params.wage_self * (1 - relevant_transfer)
    end
    Q = 2 - h_self - h_spouse
    if x <= 0 || Q <= 0 || h_self < 0 || h_self > 1 || h_spouse < 0 || h_spouse > 1
        return -Inf
    end
    norm = -self_params.conformism * (
        config.w_self * (h_self - self_params.N_h)^2 +
            config.w_transfer * (theta - self_params.N_theta)^2 +
            config.w_partner * (h_spouse - self_params.N_h_spouse)^2
    )
    if !recipient && config.func isa MultiplicativeWeighted
        return (x^self_params.alpha * Q)^(1 - self_params.alpha) * exp(norm)
    end
    return material(config.func, x, Q, self_params.alpha) * exp(norm)
end

function best_response_1d(U::Function; lb::Float64 = 0.0, ub::Float64 = 1.0)
    res = Optim.maximize(U, lb, ub, Optim.Brent(); rel_tol = 1.0e-8, abs_tol = 1.0e-10)
    return clamp(Optim.maximizer(res), 0, 1)
end
