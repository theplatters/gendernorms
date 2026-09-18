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

struct Theta
  amount::Float64
end
