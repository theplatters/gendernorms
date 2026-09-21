# Norm perception port of the norm part of NetLogo `calculate-utility`,
# ODD section Norm perception (`calculate-utility`). Same-sex neighbours
# define each agent's reference group: perceived norms are means of lagged
# (`old-*`) working time and transfers, and the norm penalty weights the
# squared deviations of the committed current bundle from those means.
# See `MDR-0004` for the porting decisions (on-demand global means under
# homogenous mixing, committed-state storage of the norm parameter).

"""
    _mean_old_working_time(world, entities)

Mean lagged (`old`) working time over `entities`, which must be non-empty.
"""
function _mean_old_working_time(world, entities)
    total = sum(Ark.get_components(world, entity, (WorkingTime,))[1].old for entity in entities)
    return total / length(entities)
end

"""
    _mean_old_transfer(world, entities)

Mean lagged (`old`) transfer to the woman over `entities`, which must be
non-empty.
"""
function _mean_old_transfer(world, entities)
    total = sum(Ark.get_components(world, entity, (TransferToWoman,))[1].old for entity in entities)
    return total / length(entities)
end

"""
    norm_global_means(world, net::SocialNetwork)

Global means of the lagged (`old-*`) values over the entity vectors of
`net`: mean working time of women (`women_h`), mean working time of men
(`men_h`), and mean transfer to the woman over women (`transfer`, matching
NetLogo `global-mean-transfer`). Returns a `NamedTuple` with fields
`women_h`, `men_h`, and `transfer`.
"""
function norm_global_means(world, net::SocialNetwork)
    women_h = _mean_old_working_time(world, net.women_entities)
    men_h = _mean_old_working_time(world, net.men_entities)
    transfer = _mean_old_transfer(world, net.women_entities)
    return (; women_h, men_h, transfer)
end

"""
    norm_means(world, net::SocialNetwork, vertex::Int, is_woman::Bool, globals, spouse_seen::Vector{Ark.Entity})

Perceived norms of the agent at graph `vertex` (`is_woman` selects the
women or men graph and entity vector of `net`). With neighbours, returns
the mean lagged working time (`division_of_labor`) and transfer
(`transfer`) over the same-sex neighbours plus the mean lagged working
time over the deduplicated spouses of those neighbours
(`division_of_labor_spouse`). The neighbour sums accumulate in adjacency
order and the spouses deduplicate in first-occurrence order, matching the
`unique` semantics of NetLogo `calculate-utility` (ODD section Norm
perception (`calculate-utility`)); see `MDR-0004`. The caller-owned
scratch buffer `spouse_seen` holds the distinct neighbour spouses so the
neighbour branch allocates nothing; it is emptied at the start of each
neighbour-branch call and reused across calls. Without neighbours, falls back to the agent's own lag and
spouse lag when `globals` is `nothing`, or to the global means from
`norm_global_means` when `globals` is given (isolated agent under
homogenous mixing). Returns a `NamedTuple` with fields
`division_of_labor`, `transfer`, and `division_of_labor_spouse`.
"""
function norm_means(world, net::SocialNetwork, vertex::Int, is_woman::Bool, globals, spouse_seen::Vector{Ark.Entity})
    entities = is_woman ? net.women_entities : net.men_entities
    graph = is_woman ? net.women : net.men
    entity = entities[vertex]
    neighbours = Graphs.neighbors(graph, vertex)
    if !isempty(neighbours)
        empty!(spouse_seen)
        h_total = 0.0
        t_total = 0.0
        spouse_total = 0.0
        for nb in neighbours
            working_time, transfer, spouse = Ark.get_components(
                world, entities[nb], (WorkingTime, TransferToWoman, Spouse)
            )
            h_total += working_time.old
            t_total += transfer.old
            duplicate = false
            for seen_spouse in spouse_seen
                if seen_spouse == spouse.entity
                    duplicate = true
                    break
                end
            end
            if !duplicate
                push!(spouse_seen, spouse.entity)
                spouse_working_time, = Ark.get_components(world, spouse.entity, (WorkingTime,))
                spouse_total += spouse_working_time.old
            end
        end
        return (;
            division_of_labor = h_total / length(neighbours),
            transfer = t_total / length(neighbours),
            division_of_labor_spouse = spouse_total / length(spouse_seen),
        )
    end
    if globals === nothing
        working_time, transfer, spouse = Ark.get_components(world, entity, (WorkingTime, TransferToWoman, Spouse))
        spouse_working_time, = Ark.get_components(world, spouse.entity, (WorkingTime,))
        return (;
            division_of_labor = working_time.old,
            transfer = transfer.old,
            division_of_labor_spouse = spouse_working_time.old,
        )
    end
    if is_woman
        return (;
            division_of_labor = globals.women_h,
            transfer = globals.transfer,
            division_of_labor_spouse = globals.men_h,
        )
    end
    return (;
        division_of_labor = globals.men_h,
        transfer = globals.transfer,
        division_of_labor_spouse = globals.women_h,
    )
end

"""
    norm_penalty(conformism::Float64, h_self::Float64, h_spouse::Float64, theta::Float64, means, config::UtilityConfig)

Norm exponent of NetLogo `calculate-utility`: `-conformism` times the
weighted sum of the squared deviations of own hours `h_self`, transfer
`theta`, and spouse hours `h_spouse` from the perceived norms `means`
(fields `division_of_labor`, `transfer`, `division_of_labor_spouse`),
with weights `config.w_self`, `config.w_transfer`, and `config.w_partner`.
Returns a `Float64`.
"""
function norm_penalty(conformism::Float64, h_self::Float64, h_spouse::Float64, theta::Float64, means, config::UtilityConfig)
    return -conformism * (
        config.w_self * (h_self - means.division_of_labor)^2 +
        config.w_transfer * (theta - means.transfer)^2 +
        config.w_partner * (h_spouse - means.division_of_labor_spouse)^2
    )
end

"""
    calculate_norm_perception!(world, config::UtilityConfig)

Loop over women then men via the entity vectors and graph vertices of the
`SocialNetwork` resource, compute each agent's perceived norms with
`norm_means`, evaluate the committed-state penalty with `norm_penalty`
from current working times and the current transfer, and store
`PerceptionNormDivisionOfLabor` and `NormParameter` on each agent with
`Ark.set_components!`. Port of the norm part of NetLogo `calculate-utility`
(ODD section Norm perception). The global means are computed once with
`norm_global_means` when the `network` field of the world's `ModelProperties`
resource is `HomogeneousMixing`; the specification is read from that resource
(see `ADR-0010`). Returns `nothing`.
"""
function calculate_norm_perception!(world, config::UtilityConfig)
    net = Ark.get_resource(world, SocialNetwork)
    properties = Ark.get_resource(world, ModelProperties)
    globals = properties.network isa HomogeneousMixing ? norm_global_means(world, net) : nothing
    spouse_seen = Ark.Entity[]
    for (entities, is_woman) in ((net.women_entities, true), (net.men_entities, false))
        for (vertex, entity) in enumerate(entities)
            means = norm_means(world, net, vertex, is_woman, globals, spouse_seen)
            working_time, transfer, conformism, spouse =
                Ark.get_components(world, entity, (WorkingTime, TransferToWoman, Conformism, Spouse))
            spouse_working_time, = Ark.get_components(world, spouse.entity, (WorkingTime,))
            penalty = norm_penalty(
                conformism.amount, working_time.current, spouse_working_time.current, transfer.current, means, config,
            )
            Ark.set_components!(
                world, entity, (PerceptionNormDivisionOfLabor(means.division_of_labor), NormParameter(penalty)),
            )
        end
    end
    return nothing
end
