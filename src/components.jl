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

struct PreferencePrivate
  current::Float64
end

struct Conformism
  amount::Float64
end

struct CurrentUtility
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
