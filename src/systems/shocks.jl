# Shock dynamics, port of NetLogo `start-shock` and `end-shock` (ODD section
# Shocks (`start-shock`, `end-shock`)), plus the ported-but-unscheduled
# `update-wages` (ODD section Endogenous preference adaptation and wage
# growth); see `MDR-0009`. Shock mode is resource presence: `WageShock`
# and `PreferenceShock` each carry their own schedule, and
# `update_shocks!` dispatches `tick == start` to `start_shock!` and
# `tick > start` to `recover_shock!`. The tick path uses `Ark.Query`
# with `@inbounds` index loops and allocates nothing; only the
# setup-only `select_affected!` may allocate.

"""
    WAGE_CUT

Kept fraction of the pre-shock wage for directly-affected agents
(NetLogo `set wage 0.6 * wage-pre`, a 40% cut, ODD section Shocks
(`start-shock`, `end-shock`)); see `MDR-0009`.
"""
const WAGE_CUT = 0.6

"""
    select_affected!(world, perc_male::Real, perc_female::Real, rng)

Draw the wage-shock target sets at setup: tag `floor(Int, n * perc /
100)` agents of each sex with `DirectlyAffected` through a partial
Fisher-Yates shuffle driven by `rng`, where `n` is the size of that
sex's population. Port of the `setup` draw of NetLogo
`directly-affected-men` and `directly-affected-women` with `n-of`
(ODD Initialization item 10 and Shocks (`start-shock`, `end-shock`));
NetLogo `n-of` rounds a fractional size down (4.5 becomes 4), which
the `floor` reproduces; see `MDR-0009`. Setup only, may allocate, and
one-shot per world: the tags are not cleared, so a re-setup must build
a new world. The world is mutated and nothing is returned. Throws
`ArgumentError` when a percent lies outside `[0, 100]` or when a
positive share is requested from an empty breed.
"""
function select_affected!(world, perc_male::Real, perc_female::Real, rng)
    0.0 <= perc_male <= 100.0 ||
        throw(ArgumentError("perc_male must be in [0, 100], got $perc_male"))
    0.0 <= perc_female <= 100.0 ||
        throw(ArgumentError("perc_female must be in [0, 100], got $perc_female"))
    men = entities_with(world, Male)
    isempty(men) && perc_male > 0.0 &&
        throw(ArgumentError("no men carry Male: cannot draw directly-affected men from an empty breed"))
    women = entities_with(world, Female)
    isempty(women) && perc_female > 0.0 &&
        throw(ArgumentError("no women carry Female: cannot draw directly-affected women from an empty breed"))
    _tag_affected!(world, men, floor(Int, length(men) * perc_male / 100), rng)
    _tag_affected!(world, women, floor(Int, length(women) * perc_female / 100), rng)
    return nothing
end

"""
    _tag_affected!(world, entities, count, rng)

Tag the first `count` entries of `entities` with `DirectlyAffected`
after moving a uniform random subset to the front with a partial
Fisher-Yates shuffle driven by `rng`; `count` is pre-validated by
`select_affected!` against the size of `entities`. Helper of
`select_affected!` (NetLogo `n-of`, ODD Initialization item 10); see
`MDR-0009`. The world is mutated and nothing is returned.
"""
function _tag_affected!(world, entities::Vector{Ark.Entity}, count::Int, rng)
    for i in 1:count
        j = rand(rng, i:length(entities))
        entities[i], entities[j] = entities[j], entities[i]
        Ark.add_components!(world, entities[i], (DirectlyAffected(),))
    end
    return nothing
end

"""
    start_shock!(world, ::WageShock)

Start the wage shock: save `Wage.old = Wage.current` for all turtles,
then keep `WAGE_CUT * old` for `DirectlyAffected` agents only. Port of
the wage branch of NetLogo `start-shock` (ODD section Shocks
(`start-shock`, `end-shock`)); see `MDR-0009`. The world is mutated in
`Ark.Query` passes and nothing is returned.
"""
function start_shock!(world, ::WageShock)
    for (entities, wages) in Ark.Query(world, (Wage,))
        @inbounds for i in eachindex(entities)
            wages[i] = Wage(wages[i].current, wages[i].current)
        end
    end
    for (entities, wages) in Ark.Query(world, (Wage,); with=(DirectlyAffected,))
        @inbounds for i in eachindex(entities)
            wages[i] = Wage(WAGE_CUT * wages[i].old, wages[i].old)
        end
    end
    return nothing
end

"""
    start_shock!(world, shock::PreferenceShock)

Start the preference shock: save `pre = current` for all turtles, then
apply `current = max(0, current - delta)` globally with the per-sex
deltas of `shock`. Port of the preference branch of NetLogo
`start-shock` (ODD section Shocks (`start-shock`, `end-shock`)); see
`MDR-0009`. The world is mutated in `Ark.Query` passes and nothing is
returned.
"""
function start_shock!(world, shock::PreferenceShock)
    for (entities, prefs) in Ark.Query(world, (PreferencePrivate,); with=(Male,))
        @inbounds for i in eachindex(entities)
            prefs[i] = PreferencePrivate(max(0.0, prefs[i].current - shock.delta_men), prefs[i].current)
        end
    end
    for (entities, prefs) in Ark.Query(world, (PreferencePrivate,); with=(Female,))
        @inbounds for i in eachindex(entities)
            prefs[i] = PreferencePrivate(max(0.0, prefs[i].current - shock.delta_woman), prefs[i].current)
        end
    end
    return nothing
end

"""
    recover_shock!(world, shock::WageShock)

Recover wages one exponential step toward `Wage.old` at rate
`shock.depreciation`, rewriting only agents still below their
baseline so closed gaps stay closed. Port of the wage branch of
NetLogo `end-shock` (ODD section Shocks (`start-shock`, `end-shock`));
see `MDR-0009`. The world is mutated in one `Ark.Query` pass and
nothing is returned.
"""
function recover_shock!(world, shock::WageShock)
    depreciation = shock.depreciation
    for (entities, wages) in Ark.Query(world, (Wage,))
        @inbounds for i in eachindex(entities)
            current = wages[i].current
            old = wages[i].old
            if current < old
                wages[i] = Wage(current + depreciation * (old - current), old)
            end
        end
    end
    return nothing
end

"""
    recover_shock!(world, shock::PreferenceShock)

Recover preferences one exponential step toward `pre` at rate
`shock.depreciation`, rewriting only agents still below their baseline
so closed gaps stay closed. Port of the preference branch of NetLogo
`end-shock` (ODD section Shocks (`start-shock`, `end-shock`)); see
`MDR-0009`. The world is mutated in one `Ark.Query` pass and nothing
is returned.
"""
function recover_shock!(world, shock::PreferenceShock)
    depreciation = shock.depreciation
    for (entities, prefs) in Ark.Query(world, (PreferencePrivate,))
        @inbounds for i in eachindex(entities)
            current = prefs[i].current
            pre = prefs[i].pre
            if current < pre
                prefs[i] = PreferencePrivate(current + depreciation * (pre - current), pre)
            end
        end
    end
    return nothing
end

"""
    update_shocks!(world, tick::Int)

Tick scheduler of the shocks: for each shock resource present on the
world, run `start_shock!` once when `tick` equals its `start` and
`recover_shock!` on every later tick. Port of the shock block of
NetLogo `go` (ODD section Shocks (`start-shock`, `end-shock`)); see
`MDR-0009`. With both resources present both run, wage first, then
preference; with neither present this is a no-op (NetLogo `shock =
"no"`). The world is mutated and nothing is returned.
"""
function update_shocks!(world, tick::Int)
    if Ark.has_resource(world, WageShock)
        shock = Ark.get_resource(world, WageShock)
        if tick == shock.start
            start_shock!(world, shock)
        elseif tick > shock.start
            recover_shock!(world, shock)
        end
    end
    if Ark.has_resource(world, PreferenceShock)
        shock = Ark.get_resource(world, PreferenceShock)
        if tick == shock.start
            start_shock!(world, shock)
        elseif tick > shock.start
            recover_shock!(world, shock)
        end
    end
    return nothing
end

"""
    update_wages!(world, growth::WageGrowth)

Grow all women wages by the daily rate `(1 + rate)^(1/365) - 1` while
the gender wage gap `1 - mean(women) / mean(men)` is positive. Port of
NetLogo `update-wages` (ODD section Endogenous preference adaptation
and wage growth); see `MDR-0009`. Ported but unscheduled because
NetLogo `go` never calls `update-wages`. Only `Wage.current` moves;
`Wage.old` is untouched. The world is mutated and nothing is returned.
Throws `ArgumentError` naming the gender when that gender has no
agents carrying `Wage`.
"""
function update_wages!(world, growth::WageGrowth)
    women_total = 0.0
    women_count = 0
    for (entities, wages) in Ark.Query(world, (Wage,); with=(Female,))
        @inbounds for i in eachindex(entities)
            women_total += wages[i].current
            women_count += 1
        end
    end
    women_count == 0 && throw(ArgumentError("no women carry Wage: cannot average an empty gender"))

    men_total = 0.0
    men_count = 0
    for (entities, wages) in Ark.Query(world, (Wage,); with=(Male,))
        @inbounds for i in eachindex(entities)
            men_total += wages[i].current
            men_count += 1
        end
    end
    men_count == 0 && throw(ArgumentError("no men carry Wage: cannot average an empty gender"))

    rate = growth.rate
    rate <= 0.0 && return nothing
    gap = 1.0 - (women_total / women_count) / (men_total / men_count)
    gap <= 0.0 && return nothing
    daily = (1.0 + rate)^(1.0 / 365.0) - 1.0
    for (entities, wages) in Ark.Query(world, (Wage,); with=(Female,))
        @inbounds for i in eachindex(entities)
            wages[i] = Wage(wages[i].current * (1.0 + daily), wages[i].old)
        end
    end
    return nothing
end
