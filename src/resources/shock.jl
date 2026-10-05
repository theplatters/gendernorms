"""
    Shock

Abstract supertype of the shock-mode resources. Dispatch root only:
never used as a struct field or as a world resource type, so every
stored field keeps a concrete type. Port of the NetLogo `shock`
chooser (ODD section Shocks (`start-shock`, `end-shock`)); see
`MDR-0009`.
"""
abstract type Shock end

"""
    WageShock

Wage-shock mode resource (NetLogo `shock = "wage"` or `"both"`, ODD
section Shocks (`start-shock`, `end-shock`)); see `MDR-0009`. Field
`start` is the `shock-start` tick of the one-off cut, field
`depreciation` is the per-tick `shock-depreciation` recovery rate.
The affected-share draws (`perc-affected-*`) are not stored here;
they are `select_affected!` setup arguments.
"""
Base.@kwdef struct WageShock <: Shock
    start::Int = 60
    depreciation::Float64 = 0.005
end

"""
    PreferenceShock

Preference-shock mode resource (NetLogo `shock = "preference"` or
`"both"`, ODD section Shocks (`start-shock`, `end-shock`)); see
`MDR-0009`. Fields `start` and `depreciation` are the `shock-start`
tick and the per-tick `shock-depreciation` recovery rate; fields
`delta_men` and `delta_woman` are the per-sex
`preference-private-shock-*` downward shifts applied globally to all
turtles.
"""
Base.@kwdef struct PreferenceShock <: Shock
    start::Int = 60
    depreciation::Float64 = 0.005
    delta_men::Float64 = 0.0
    delta_woman::Float64 = 0.0
end

"""
    WageGrowth

Gender-gap-closing wage-growth resource (NetLogo `wage-growth-rate`,
ODD section Endogenous preference adaptation and wage growth); see
`MDR-0009`. Field `rate` is the annual growth rate applied to women
only while a wage gap remains. Ported but unscheduled: NetLogo `go`
never calls `update-wages`.
"""
Base.@kwdef struct WageGrowth
    rate::Float64 = 0.0
end
