struct Male end
struct Female end

struct WorkingTime
    current::Float64
    old::Float64
end

struct TransferToWomand
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
    old::Float64
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
