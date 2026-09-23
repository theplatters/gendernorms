# World creation and execution of the run pipeline (see `ADR-0012`).
#
# `create_world` builds and initializes a world from a validated
# `RunSpec` and attaches the `RunContext` resource; `run` executes
# the ticks and collects the in-memory `RunResult`. `run` is a
# module-local function, neither exported nor a `Base.run` method
# (extending `Base.run` would be type piracy on `Ark.World`).

"""
    create_world(spec::RunSpec)::Ark.World

Build and initialize a runnable world from a validated run
specification (see `ADR-0012`). Takes the `RunSpec`, resolves the
model, seeds `Random.MersenneTwister` with the required seed,
initializes the world with `setup_world`, restricts the model
metrics to the configured names, builds the specification loggers,
and attaches a `RunContext` resource carrying the fresh run UUID,
spec, model, config, metrics, loggers, and RNG. Throws on setup
errors. Returns the initialized world.
"""
function create_world(spec::RunSpec)::Ark.World
    model = resolve_model(spec.model_name)
    rng = Random.MersenneTwister(spec.seed)
    world = setup_world(model, spec.model_config, rng)
    available = model_metrics(model)
    metric_functions = Dict{String,Function}(
        name => available[name] for name in spec.logging.metrics
    )
    loggers = RunLogger[build_logger(output) for output in spec.logging.outputs]
    id = string(UUIDs.uuid4())
    Ark.add_resource!(
        world,
        RunContext(id, spec, model, spec.model_config, metric_functions, loggers, rng, false),
    )
    return world
end

"""
    add_logger!(world, logger::RunLogger)

Attach a programmatic logging backend to a created world (see
`ADR-0012`). Takes the world and the logger, appends it to the
`RunContext.loggers` of the world, and returns nothing. Throws
`ArgumentError` when the world carries no `RunContext`.
"""
function add_logger!(world, logger::RunLogger)
    Ark.has_resource(world, RunContext) ||
        throw(ArgumentError("world has no RunContext: build it with create_world first"))
    push!(Ark.get_resource(world, RunContext).loggers, logger)
    return nothing
end

"""
    run(world)::RunResult

Execute the run of a created world and collect the in-memory record
(see `ADR-0012`). Lifecycle: the world comes from `create_world`
(specification, then initialization); execution calls `step_model!`
for `tick in 0:(ticks - 1)`, evaluates the configured metrics after
every tick, and notifies the loggers; completion builds the
`RunResult`. Only step or metric errors stop the loop and are
recorded as `RUN_FAILURE` with the error and the completed tick
count, never as success; the `metrics_recorded!` notifications run
after the guarded region, so logger hook errors propagate to the
caller exactly like `run_started!`/`run_finished!` errors.
`InterruptException` is rethrown. One run per world: a second `run`
call on the same world throws `ArgumentError`, create a fresh world
from the spec instead. Takes the world with its `RunContext` and
returns the `RunResult`. Throws `ArgumentError` mentioning
`create_world` when the world carries no `RunContext`, and
`ArgumentError` mentioning the one-run-per-world rule when the world
has already been run.
"""
function run(world)::RunResult
    Ark.has_resource(world, RunContext) ||
        throw(ArgumentError("world has no RunContext: build it with create_world first"))
    context = Ark.get_resource(world, RunContext)
    context.executed && throw(
        ArgumentError(
            "world has already been run: one run per world; create a fresh world from the spec",
        ),
    )
    context.executed = true
    spec = context.spec
    config = config_to_dict(context.model, context.model_config)
    started_at = Dates.now()
    info = RunInfo(
        context.id,
        spec.name,
        spec.model_name,
        spec,
        config,
        sort!(collect(keys(context.metric_functions))),
        started_at,
    )
    for logger in context.loggers
        run_started!(logger, info)
    end
    names = sort!(collect(keys(context.metric_functions)))
    ticks = Int[]
    series = Dict{String,Vector{Float64}}(name => Float64[] for name in names)
    status = RUN_SUCCESS
    failure = nothing
    for tick in 0:(spec.runtime.ticks - 1)
        values = Dict{String,Float64}()
        try
            step_model!(context.model, world, context.model_config, tick)
            values = Dict{String,Float64}(
                name => Float64(context.metric_functions[name](world)) for name in names
            )
            push!(ticks, tick)
            for name in names
                push!(series[name], values[name])
            end
        catch e
            e isa InterruptException && rethrow()
            status = RUN_FAILURE
            failure = e
            break
        end
        for logger in context.loggers
            metrics_recorded!(logger, tick, values)
        end
    end
    finished_at = Dates.now()
    result = RunResult(
        context.id,
        spec.name,
        spec,
        spec.model_name,
        config,
        status,
        started_at,
        finished_at,
        length(ticks),
        failure,
        ticks,
        series,
    )
    for logger in context.loggers
        run_finished!(logger, result)
    end
    return result
end
