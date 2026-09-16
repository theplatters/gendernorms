Base.@kwdef struct ShockConfig
    shock::ShockType = SHOCK_NO # current="3"
    start::Int = 60
    depreciation::Float64 = 0.005
    pref_shock_male::Float64 = 0.0
    pref_shock_female::Float64 = 0.0
    perc_male::Float64 = 0.0
    perc_female::Float64 = 30.0
    wage_growth::Float64 = 0.0
    lambda::Float64 = 0.002 # endogenous pref adaptation
end
