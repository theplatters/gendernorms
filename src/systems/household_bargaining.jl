# Household bargaining ECS layer: `set_theta!`, the world loop porting
# NetLogo `set-theta` for every household (ODD section Transfer
# bargaining (`set-theta`, `calculate-payoff`)), plus the transient
# bundle builder `payoff_params`. Household components are extracted
# with `Ark.Query` (see `ADR-0007`); the chunked serial/parallel
# scheduling and the worker-owned scratch pair are `ADR-0014` /
# `ADR-0023`. The pure solvers moved to `src/optim/` under `ADR-0028`
# (the labour stage `mutual_best_response` to
# `src/optim/labour_optimization.jl` and the transfer stage
# `bargain_transfer` and its helpers to
# `src/optim/transfer_optimization.jl`); `set_theta!` calls the solver
# API unchanged.

"""
    payoff_params(wage_self::Float64, wage_spouse::Float64, alpha::Float64, conformism::Float64, means, ::G) where {G<:Gender}

Transient per-agent parameter bundle of NetLogo `set-theta` (ODD section
Transfer bargaining (`set-theta`, `calculate-payoff`)); the perceived norms
`means` supply `N_h` (own working time), `N_theta` (transfer), and
`N_h_spouse` (spouse working time) (see `MDR-0014` and `ADR-0007`). Returns
an `AgentPayoffParams`.
"""
function payoff_params(
        wage_self::Float64, wage_spouse::Float64, alpha::Float64,
        conformism::Float64, means, ::G
    ) where {G <: Gender}
    return AgentPayoffParams{G}(
        wage_self = wage_self,
        wage_spouse = wage_spouse,
        alpha = alpha,
        conformism = conformism,
        N_h = means.division_of_labor,
        N_theta = means.transfer,
        N_h_spouse = means.division_of_labor_spouse,
    )
end

# Chunk size of the household loop of `set_theta!` below: the serial
# path and the bounded worker tasks of `ADR-0023` both pull whole chunks
# of `HOUSEHOLD_BARGAIN_CHUNK` households, amortizing scheduling
# overhead while keeping the load-balance granularity fine for the
# uneven Brent iterations of `bargain_transfer` (chunking origin
# `ADR-0014`; the value 4 was re-confirmed by the chunk-size sweep over
# {4, 8, 16, 32} on ws_500/heterogeneous/ws_100, see
# `benchmark/scheduling_tuning.md` and `ADR-0023`).
const HOUSEHOLD_BARGAIN_CHUNK = 4

# Serial crossover of the `:auto` schedule of `set_theta!`
# (`ADR-0023`): on multithreaded runs a household group of at most
# `HOUSEHOLD_BARGAIN_SERIAL_CUTOFF` households runs the direct serial
# path, where worker-task scheduling costs more than it saves below
# this size. The value 8 is selected from the 8-thread
# small-population crossover measurements (parallel wins from about 10
# households up, serial wins at 4 and below, tie at 6-8; see
# `benchmark/scheduling_tuning.md` and `ADR-0023`).
const HOUSEHOLD_BARGAIN_SERIAL_CUTOFF = 8

"""
    set_theta!(world, config::UtilityConfig; search::Symbol = :local, chunk::Int = HOUSEHOLD_BARGAIN_CHUNK, schedule::Symbol = :auto)

Household loop of the household bargaining: ports NetLogo `set-theta` for
every household (ODD section Transfer bargaining (`set-theta`,
`calculate-payoff`)); the labour stage runs inside `bargain_transfer` (see
`MDR-0016`). Production defaults to the bounded local search; use
`search=:discovery` only for explicit validation trajectories (`ADR-0021`).
Household components are extracted with `Ark.Query` (see
`ADR-0007`); the transfer component mirrors the wife's value on the man (see
`registry/model/entities.md`). The disjoint households run in chunks of
`chunk` items (`HOUSEHOLD_BARGAIN_CHUNK` by default, at least 1).
`schedule` selects the execution path (`ADR-0023`): `:serial` runs one
direct loop, `:parallel` runs at most `min(Threads.nthreads(), nchunks)`
worker tasks that pull chunk indices dynamically from a shared atomic
chunk cursor, and `:auto` (the default) picks the serial path at one
thread and whenever a group holds at most
`HOUSEHOLD_BARGAIN_SERIAL_CUTOFF` households, the parallel path
otherwise; forcing `:serial` or `:parallel` exists for tests and
benchmark sweeps and works at any thread count. Every committed bundle
also stores the partners' committed-bundle utility levels in
`CommittedUtility` (`MDR-0019`, `ADR-0026`; NetLogo `current-utility`,
ODD sections Labour best response and Entities, state variables, and
scales): `individual_utility` at the committed `(theta, hw, hm)` and
this tick's prepared `pw`/`pm`, evaluated right after `bargain_transfer`
returns, the woman's value written through her query column and the
man's through the commit tuple, with no shared accumulation in the
parallel region. Both paths run the same
per-chunk closure over `(chunk_range, spouse_seen, scratch)`, so results
are bit-identical across paths and thread counts: each worker task owns
one `spouse_seen` scratch vector for `norm_means` (capacity-hinted to
the maximum vertex degree) and one `TransferSearchScratch` for the
transfer search, reused across every chunk the task processes, reset per
household by `bargain_transfer`, and never shared across tasks
(`ADR-0015`, `ADR-0017`, and `ADR-0023`, which amends the per-chunk
ownership wording of the earlier two records to per worker task). The
`@sync` join of the worker tasks is the completion barrier before the
next tick system runs, and worker failures propagate as
`TaskFailedException`/`CompositeException` (as under `ADR-0014`). The
world is mutated and nothing is returned.
"""
function set_theta!(
        world, config::UtilityConfig;
        search::Symbol = :local, chunk::Int = HOUSEHOLD_BARGAIN_CHUNK, schedule::Symbol = :auto
    )
    search in (:local, :discovery) || throw(ArgumentError("search must be :local or :discovery"))
    chunk >= 1 || throw(ArgumentError("chunk must be at least 1"))
    schedule in (:auto, :serial, :parallel) ||
        throw(ArgumentError("schedule must be :auto, :serial, or :parallel"))
    net = Ark.get_resource(world, SocialNetwork)
    properties = Ark.get_resource(world, ModelProperties)
    globals = properties.network isa HomogeneousMixing ? norm_global_means(world, net) : nothing
    women_index = Dict(entity => vertex for (vertex, entity) in enumerate(net.women_entities))
    men_index = Dict(entity => vertex for (vertex, entity) in enumerate(net.men_entities))
    # Upper bound for the `spouse_seen` scratch buffer: `norm_means` pushes at
    # most one distinct spouse per same-sex neighbour, so the maximum vertex
    # degree of the two graphs covers every call (see `ADR-0015`).
    spouse_capacity = max(
        maximum(v -> Graphs.degree(net.women, v), Graphs.vertices(net.women); init = 0),
        maximum(v -> Graphs.degree(net.men, v), Graphs.vertices(net.men); init = 0),
    )
    component_types = (Wage, WorkingTime, TransferToWoman, Conformism, PreferencePrivate, Spouse, CommittedUtility)
    for (entities, wages, times, transfers, conformisms, preferences, spouses, utilities) in
        Ark.Query(world, component_types; with = (Female,))
        # The single per-chunk processing implementation shared by the
        # serial path and the bounded worker tasks below (`ADR-0023`):
        # parameterized by the chunk's households and the caller-owned
        # scratch pair, so the two paths cannot drift and the results stay
        # bit-identical across paths and thread counts. One scratch buffer
        # pair per caller: `norm_means` empties `spouse_seen` at the start
        # of its neighbour branch, so reuse across households is exact and
        # the buffers stay task-local (see `ADR-0015`). The capacity hint
        # matches the largest neighbour list it will hold, so no call grows
        # it. The `TransferSearchScratch` is the task-owned transfer-search
        # storage of `ADR-0017`, reset by every `bargain_transfer` call.
        function process_chunk!(
                chunk_range, spouse_seen::Vector{Ark.Entity}, scratch::TransferSearchScratch
            )
            for f in chunk_range
                woman = entities[f]
                man = spouses[f].entity
                man_wage, man_time, man_transfer, man_conformism, man_preference =
                    Ark.get_components(world, man, (Wage, WorkingTime, TransferToWoman, Conformism, PreferencePrivate))
                woman_vertex = get(women_index, woman, 0)
                woman_vertex == 0 && throw(ArgumentError("woman is not in the women entity vector"))
                man_vertex = get(men_index, man, 0)
                man_vertex == 0 && throw(ArgumentError("man is not in the men entity vector"))

                woman_norms = norm_means(world, net, woman_vertex, true, globals, spouse_seen)
                man_norms = norm_means(world, net, man_vertex, false, globals, spouse_seen)

                pw = payoff_params(
                    wages[f].current, man_wage.current, preferences[f].current,
                    conformisms[f].amount, woman_norms, Female()
                )
                pm = payoff_params(
                    man_wage.current, wages[f].current, man_preference.current,
                    man_conformism.amount, man_norms, Male()
                )

                theta, hw, hm = bargain_transfer(
                    scratch, times[f].current, man_time.current, transfers[f].current, pw, pm, config;
                    search = search
                )
                # Committed-bundle utility observation (`MDR-0019`): the
                # `individual_utility` levels of both partners at the committed
                # bundle and this tick's prepared parameters `pw`/`pm`, the
                # single objective implementation of the labour solver
                # (`MDR-0013`). Evaluated on every commit path, including
                # status-quo retention and the non-finite fallback of
                # `bargain_transfer`; non-finite values propagate unchanged.
                utility_woman = individual_utility(hw, hm, theta, pw, config)
                utility_man = individual_utility(hm, hw, theta, pm, config)
                # the woman is in the query, so the views write in place
                times[f] = WorkingTime(hw, times[f].old)
                transfers[f] = TransferToWoman(theta, transfers[f].old)
                utilities[f] = CommittedUtility(utility_woman)
                # the man is not in the women's query, so only the entity API exists
                Ark.set_components!(
                    world,
                    man,
                    (
                        WorkingTime(hm, man_time.old),
                        TransferToWoman(theta, man_transfer.old),
                        CommittedUtility(utility_man),
                    ),
                )
            end
            return nothing
        end
        chunks = collect(Iterators.partition(eachindex(entities), chunk))
        use_parallel = schedule === :parallel ||
            (
            schedule === :auto && Threads.nthreads() > 1 &&
                length(entities) > HOUSEHOLD_BARGAIN_SERIAL_CUTOFF
        )
        if use_parallel
            # Bounded worker scheduling (`ADR-0023`): at most
            # `min(Threads.nthreads(), nchunks)` worker tasks replace the
            # `Threads.@threads :greedy` loop of `ADR-0014`; each worker
            # claims the next chunk index from the shared atomic cursor until
            # the chunks are exhausted, keeping dynamic scheduling without a
            # task per chunk or per household. The `let`-bound scratch pair is
            # constructed inside the worker task and owned by it for all of
            # its chunks: the fresh bindings cannot alias the serial path's
            # buffers or another worker's. The `@sync` join is the completion
            # barrier before the next tick system runs, and a failing worker
            # surfaces as `TaskFailedException`/`CompositeException` (see
            # `ADR-0014`).
            nchunks = length(chunks)
            cursor = Threads.Atomic{Int}(0)
            @sync for _ in 1:min(Threads.nthreads(), nchunks)
                Threads.@spawn let spouse_seen = sizehint!(Ark.Entity[], spouse_capacity),
                        scratch = TransferSearchScratch()
                    while true
                        index = Threads.atomic_add!(cursor, 1)
                        index < nchunks || break
                        process_chunk!(chunks[index + 1], spouse_seen, scratch)
                    end
                end
            end
        else
            # Direct serial path (`ADR-0023`): one `let`-bound scratch pair,
            # no tasks and no cursor; an empty household group runs zero
            # chunks and returns cleanly.
            let spouse_seen = sizehint!(Ark.Entity[], spouse_capacity),
                    scratch = TransferSearchScratch()
                for chunk_range in chunks
                    process_chunk!(chunk_range, spouse_seen, scratch)
                end
            end
        end
    end
    return nothing
end
