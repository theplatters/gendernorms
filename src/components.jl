abstract type Gender end
struct Male <: Gender end
struct Female <: Gender end

struct WorkingTime
    current::Float64
    old::Float64
end

struct TransferToWoman
    current::Float64
    old::Float64
end

struct Spouse
    entity::Ark.Entity
end

struct Wage
    current::Float64
    old::Float64
end

"""
    PreferencePrivate

Private preference for own working time (`preference-private`
turtles-own variable) with its pre-shock memory (`pre`, the
`preference-private-pre` turtles-own variable). Port of NetLogo
`start-shock` (ODD section Shocks (`start-shock`, `end-shock`)); see
`MDR-0009`. The `pre` baseline is saved for all turtles when the
preference shock starts and is the recovery target of
`recover_shock!`; `update_preferences` adapts `current` and preserves
`pre`.
"""
struct PreferencePrivate
    current::Float64
    pre::Float64
end

"""
    DirectlyAffected

Empty tag marking the agents drawn into the wage-shock target sets at
`setup` (NetLogo `directly-affected-men` and `directly-affected-women`
agentsets, ODD Initialization item 10 and Shocks (`start-shock`,
`end-shock`)); see `MDR-0009`. Added with `Ark.add_components!` by
`select_affected!` and read through the `with` filter of `Ark.Query`
by `start_shock!`.
"""
struct DirectlyAffected end

struct Conformism
    amount::Float64
end

struct Lambda
    amount::Float64
end

"""
    NormParameter

Stored norm penalty (`norm-parameter` turtles-own variable).
Set by the norm perception system in `src/systems/norm_perception.jl`.
"""
struct NormParameter
    amount::Float64
end

"""
    PerceptionNormDivisionOfLabor

Stored perceived work norm (`perception-norm-division-of-labor`
turtles-own variable): the mean lagged working time of the agent's
same-sex reference group. Set by the norm perception system in
`src/systems/norm_perception.jl`.
"""
struct PerceptionNormDivisionOfLabor
    amount::Float64
end

"""
    CommittedUtility

Committed-bundle utility observation (`current-utility` in NetLogo is
the mutable `choose-bundle` scratch of the reference implementation;
ODD sections Entities, state variables, and scales and Labour best
response). The Julia observer stores the `individual_utility` level of
one partner at the household's committed bundle of the tick, evaluated
by `set_theta!` immediately after `bargain_transfer` returns with that
tick's prepared payoff parameters (see `MDR-0019`, which supersedes
`MDR-0018` only for this specified, populated, consumed observer). It
is evaluation state, not solver scratch: the stale last-counterfactual
value of the reference is deliberately not reproduced (ODD quirk 11
stays unported). Initialized to `NaN` = "not yet observed" at setup and
aggregated into the `UtilityStats` observer by `update_observer_stats!`
(see `MDR-0022`). Not named `CurrentUtility`: the unused zero-valued
placeholder of that name was removed under `MDR-0018`.
"""
struct CommittedUtility
    value::Float64
end
