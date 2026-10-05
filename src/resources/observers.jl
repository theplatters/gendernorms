mutable struct WorkingTimeStats
    men::Float64
    women::Float64
    gap::Float64
end

"""
    PreferenceStats

Per-sex mean of `PreferencePrivate.current`, observed pre-adaptation
at the tick's single observer snapshot before `update_preferences`
adapts the agents (see `MDR-0020` and `MDR-0022`; written by
`update_observer_stats!` in `src/systems/statistics.jl`). A Julia-side
diagnostic with no NetLogo global: the reference only plots `mean
[preference-difference]` per sex, which stays not ported. Fields `men`
and `women` hold the means in `[0, 1]` and initialize to `NaN` =
"not yet observed" at setup.
"""
mutable struct PreferenceStats
    men::Float64
    women::Float64
end

"""
    UtilityStats

Per-sex mean of the `CommittedUtility` observations of the tick (see
`MDR-0019` and `MDR-0022`; written by `update_observer_stats!` in
`src/systems/statistics.jl`). `women` matches the female-mean diagnostic
intent of the reference's `mean [current-utility] of women`;
`men` is an explicitly recorded Julia extension. Non-finite
observations propagate into the means (no clamping, no zero-filling).
Fields initialize to `NaN` = "not yet observed" at setup.
"""
mutable struct UtilityStats
    men::Float64
    women::Float64
end

"""
    TransferStats

Mean of `TransferToWoman.current` over the women at the tick's single
observer snapshot (see `MDR-0021` and `MDR-0022`; written by
`update_observer_stats!` in `src/systems/statistics.jl`): the stored
`global-mean-transfer` of NetLogo `update-statistics` (ODD section
Statistics (`update-statistics`)), distinct from the lagged transfer
mean of `norm_global_means` (see `MDR-0004`). Spouses mirror their
wives' current transfer, so only the women's column is averaged. The
`mean` field holds the value in `[-1, 1]` and initializes to `NaN` =
"not yet observed" at setup.
"""
mutable struct TransferStats
    mean::Float64
end
