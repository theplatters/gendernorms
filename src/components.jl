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
