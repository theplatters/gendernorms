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

# Chunk size of the norm perception world loop below: the serial path
# and the bounded worker tasks of `ADR-0024` both pull whole chunks of
# `NORM_PERCEPTION_CHUNK` agents, amortizing scheduling overhead over
# cheap per-agent iterations while keeping the load-balance granularity
# fine (chunking origin `ADR-0014`; the sweep over {16, 32, 64, 128} at
# 8 and 16 threads on 2000 agents per gender is flat within noise and
# 256 regresses, so the a-priori middle pick 64 is kept, see
# `ADR-0024`).
const NORM_PERCEPTION_CHUNK = 64

# Serial crossover of the `:auto` schedule of `calculate_norm_perception!`
# (`ADR-0024`): on multithreaded runs a world of at most
# `NORM_PERCEPTION_SERIAL_CUTOFF` total agents (women plus men) runs the
# direct serial path, where worker-task scheduling costs more than it
# saves below this size. The value 256 is selected from the small-world
# serial-versus-parallel crossover measurements at 8 threads (see
# `ADR-0024`).
const NORM_PERCEPTION_SERIAL_CUTOFF = 256

"""
    calculate_norm_perception!(world, config::UtilityConfig; chunk::Int=NORM_PERCEPTION_CHUNK, schedule::Symbol=:auto)

Loop over women then men via the entity vectors and graph vertices of the
`SocialNetwork` resource, compute each agent's perceived norms with
`norm_means`, evaluate the committed-state penalty with `norm_penalty`
from current working times and the current transfer, and store
`PerceptionNormDivisionOfLabor` and `NormParameter` on each agent with
`Ark.set_components!`. Port of the norm part of NetLogo `calculate-utility`
(ODD section Norm perception, see `MDR-0004`). The global means are
computed once with `norm_global_means` when the `network` field of the
world's `ModelProperties` resource is `HomogeneousMixing`; the
specification is read from that resource (see `ADR-0010`). The disjoint
agents run in chunks of `chunk` items (`NORM_PERCEPTION_CHUNK` by
default, at least 1), flattened over the women chunks then the men
chunks of one parallel region and decoded arithmetically per chunk.
`schedule` selects the execution path (`ADR-0024`): `:serial` runs one
direct loop, `:parallel` runs at most `min(Threads.nthreads(), nchunks)`
worker tasks that pull chunk indices dynamically from a shared atomic
chunk cursor, and `:auto` (the default) picks the serial path at one
thread and whenever the world holds at most
`NORM_PERCEPTION_SERIAL_CUTOFF` total agents, the parallel path
otherwise; forcing `:serial` or `:parallel` exists for tests and
benchmark sweeps and works at any thread count. Both paths run the same
per-chunk closure, so results are bit-identical across paths and thread
counts (the `MDR-0004` semantics - adjacency accumulation order and
first-occurrence spouse dedup order - are preserved): each worker task
owns one `spouse_seen` scratch vector for `norm_means` (capacity-hinted
to the maximum vertex degree, `ADR-0015`), reused across every chunk
the task processes and never shared across tasks. The `@sync` join of
the worker tasks is the completion barrier before the next tick system
runs, and worker failures propagate as
`TaskFailedException`/`CompositeException` (as under `ADR-0014`). The
world is mutated and nothing is returned.
"""
function calculate_norm_perception!(
    world, config::UtilityConfig;
    chunk::Int=NORM_PERCEPTION_CHUNK, schedule::Symbol=:auto,
)
    chunk >= 1 || throw(ArgumentError("chunk must be at least 1"))
    schedule in (:auto, :serial, :parallel) ||
        throw(ArgumentError("schedule must be :auto, :serial, or :parallel"))
    net = Ark.get_resource(world, SocialNetwork)
    properties = Ark.get_resource(world, ModelProperties)
    globals = properties.network isa HomogeneousMixing ? norm_global_means(world, net) : nothing
    nw = length(net.women_entities)
    nm = length(net.men_entities)
    wchunks = cld(nw, chunk)
    nchunks = wchunks + cld(nm, chunk)
    # Upper bound for the `spouse_seen` scratch buffer: `norm_means`
    # pushes at most one distinct spouse per same-sex neighbour, so the
    # maximum vertex degree of the two graphs covers every call (see
    # `ADR-0015`).
    spouse_capacity = max(
        maximum(v -> Graphs.degree(net.women, v), Graphs.vertices(net.women); init=0),
        maximum(v -> Graphs.degree(net.men, v), Graphs.vertices(net.men); init=0),
    )
    # The single per-chunk processing implementation shared by the
    # serial path and the bounded worker tasks below (`ADR-0024`):
    # chunk indices are flattened over the women chunks then the men
    # chunks and decoded arithmetically here, so the entity vectors are
    # never concatenated and no chunk descriptors are allocated. The
    # caller-owned scratch buffer is emptied at the start of each
    # neighbour-branch `norm_means` call, so reuse across chunks is
    # exact and the buffer stays task-local (see `ADR-0015`).
    function process_chunk!(chunk_index::Int, spouse_seen::Vector{Ark.Entity})
        if chunk_index <= wchunks
            entities = net.women_entities
            is_woman = true
            first_vertex = (chunk_index - 1) * chunk + 1
            last_vertex = min(chunk_index * chunk, nw)
        else
            entities = net.men_entities
            is_woman = false
            men_chunk = chunk_index - wchunks
            first_vertex = (men_chunk - 1) * chunk + 1
            last_vertex = min(men_chunk * chunk, nm)
        end
        for vertex in first_vertex:last_vertex
            entity = entities[vertex]
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
        return nothing
    end
    use_parallel = schedule === :parallel ||
        (schedule === :auto && Threads.nthreads() > 1 &&
            (nw + nm) > NORM_PERCEPTION_SERIAL_CUTOFF)
    if use_parallel
        # Bounded worker scheduling (`ADR-0024`, the `ADR-0023` shape):
        # at most `min(Threads.nthreads(), nchunks)` worker tasks claim
        # chunk indices from the shared atomic cursor until the chunks
        # are exhausted, keeping dynamic scheduling without a task per
        # chunk or per agent. The `let`-bound scratch buffer is
        # constructed inside the worker task and owned by it for all of
        # its chunks: the fresh binding cannot alias the serial path's
        # buffer or another worker's. The `@sync` join is the completion
        # barrier before the next tick system runs, and a failing worker
        # surfaces as `TaskFailedException`/`CompositeException` (see
        # `ADR-0014`).
        cursor = Threads.Atomic{Int}(0)
        @sync for _ in 1:min(Threads.nthreads(), nchunks)
            Threads.@spawn let spouse_seen = sizehint!(Ark.Entity[], spouse_capacity)
                while true
                    index = Threads.atomic_add!(cursor, 1)
                    index < nchunks || break
                    process_chunk!(index + 1, spouse_seen)
                end
            end
        end
    else
        # Direct serial path (`ADR-0024`): one `let`-bound scratch
        # buffer, no tasks and no cursor; an empty gender runs zero
        # chunks.
        let spouse_seen = sizehint!(Ark.Entity[], spouse_capacity)
            for chunk_index in 1:nchunks
                process_chunk!(chunk_index, spouse_seen)
            end
        end
    end
    return nothing
end
