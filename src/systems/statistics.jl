# Statistics core, port of NetLogo `update-statistics`, ODD section
# Statistics (`update-statistics`); see `MDR-0007`. Copies `current-*` to
# `old-*` and recomputes the contemporaneous global working-time means
# into the `WorkingTimeStats` resource. Histories, moving averages,
# subgroup means, and the `run-time` timer are deferred under `TASK-0001`.

"""
    update_old_working_time_and_transfer!(world)

Copy `current` to `old` for `WorkingTime` and `TransferToWoman` on every agent carrying both `WorkingTime` and `TransferToWoman`. Port of the lag-copy lines of NetLogo `update-statistics` (ODD
section Statistics (`update-statistics`)); see `MDR-0007`. The world is
mutated in one `Ark.Query` pass and nothing is returned.
"""
function update_old_working_time_and_transfer!(world)
    for (entities, times, transfers) in Ark.Query(world, (WorkingTime, TransferToWoman))
        @inbounds for i in eachindex(entities)
            times[i] = WorkingTime(times[i].current, times[i].current)
            transfers[i] = TransferToWoman(transfers[i].current, transfers[i].current)
        end
    end
    return nothing
end

"""
    update_global_working_times!(world)

Write the contemporaneous mean `WorkingTime.current` of women and men
plus `gap = men - women` into the world's `WorkingTimeStats` resource
with a single resource write. Port of the global-mean lines of NetLogo
`update-statistics` (ODD section Statistics (`update-statistics`)); see
`MDR-0007`. The resource must already exist (added with
`Ark.add_resource!` at setup, see `ADR-0010`); the world is mutated and
nothing is returned. Throws `ArgumentError` naming the gender when that
gender has no agents.
"""
function update_global_working_times!(world)
    women_total = 0.0
    women_count = 0
    for (entities, times) in Ark.Query(world, (WorkingTime,); with=(Female,))
        @inbounds for i in eachindex(entities)
            women_total += times[i].current
            women_count += 1
        end
    end
    women_count == 0 && throw(ArgumentError("no women carry WorkingTime: cannot average an empty gender"))

    men_total = 0.0
    men_count = 0
    for (entities, times) in Ark.Query(world, (WorkingTime,); with=(Male,))
        @inbounds for i in eachindex(entities)
            men_total += times[i].current
            men_count += 1
        end
    end
    men_count == 0 && throw(ArgumentError("no men carry WorkingTime: cannot average an empty gender"))

    women_mean = women_total / women_count
    men_mean = men_total / men_count
    stats = Ark.get_resource(world, WorkingTimeStats)
    stats.women = women_mean
    stats.men = men_mean
    stats.gap = men_mean - women_mean
    return nothing
end
