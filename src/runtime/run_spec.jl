# Run specification of the execution pipeline (see `ADR-0012`).
#
# The TOML run specification is parsed into an immutable `RunSpec`
# carrying the run name and seed, the resolved model configuration, the
# runtime tick budget, and the logging selection. `parse_spec`
# validates untrusted input and aggregates every problem into one
# `RunSpecError`; `load_spec` reads a TOML file; `spec_to_dict`
# echoes a validated specification back into the accepted input shape.

"""
    RuntimeConfig

Immutable runtime section of a run specification (see `ADR-0012`).
Field `ticks` is the number of `step_model!` calls the runner
executes, counting from tick 0.
"""
struct RuntimeConfig
    ticks::Int
end

"""
    OutputSpec

Immutable selection of one logging backend (see `ADR-0012`). Field
`type` names a backend registered in `LOG_OUTPUT_TYPES`; field `args`
carries the remaining `[[logging.outputs]]` keys validated by
`validate_output_spec`.
"""
struct OutputSpec
    type::String
    args::Dict{String,Any}
end

"""
    LoggingConfig

Immutable logging section of a run specification (see `ADR-0012`).
Field `metrics` lists the evaluated metric names; field `outputs`
lists the logging backends receiving the run.
"""
struct LoggingConfig
    metrics::Vector{String}
    outputs::Vector{OutputSpec}
end

"""
    RunSpec

Immutable validated run specification (see `ADR-0012`). Field `name`
is the run label, field `seed` the required non-negative seed, field
`model_name` the registered model name, field `model_config` the
model-specific validated configuration, field `runtime` the tick
budget, and field `logging` the metric and backend selection.
"""
struct RunSpec
    name::String
    seed::Int
    model_name::String
    model_config::Any
    runtime::RuntimeConfig
    logging::LoggingConfig
end

"""
    RunSpecError <: Exception

Aggregated run specification validation failure (see `ADR-0012`).
Field `problems` holds one key-pathed problem line per invalid
input, for example `[runtime.ticks] must be an integer >= 1, got
"ten"`.
"""
struct RunSpecError <: Exception
    problems::Vector{String}
end

"""
    Base.showerror(io::IO, err::RunSpecError)

Print an aggregated run specification failure (see `ADR-0012`). Shows
`invalid run specification:` followed by one `- ` line per problem in
`err.problems`. Returns nothing.
"""
function Base.showerror(io::IO, err::RunSpecError)
    print(io, "invalid run specification:")
    for problem in err.problems
        print(io, "\n- ", problem)
    end
    return nothing
end

"""
    _key_problems(raw::AbstractDict, allowed, path::String)::Vector{String}

List the unknown keys of `raw` as `[path] unknown key "..."
(allowed: ...)` lines (see `ADR-0012`). Takes the raw table, the
allowed key names, and the key path used in the messages. Returns the
problem lines sorted by key. Reused by model bindings validating
their own `[model]` keys.
"""
function _key_problems(raw::AbstractDict, allowed, path::String)::Vector{String}
    names = Set{String}(string(k) for k in allowed)
    problems = String[]
    for key in sort!(String[string(k) for k in keys(raw)])
        key in names || push!(
            problems,
            "[$path] unknown key \"$key\" (allowed: $(join(sort!(collect(names)), ", ")))",
        )
    end
    return problems
end

"""
    parse_spec(raw::AbstractDict)::RunSpec

Validate a raw run specification dictionary and build the immutable
`RunSpec` (see `ADR-0012`). Takes the TOML-parsed top-level table,
which allows exactly the `run`, `model`, `runtime`, and `logging`
tables; `[logging]` is optional and the other three are required.
Collects every missing key, wrong type, out-of-range value, unknown
key, unregistered model, metric, or output backend into one
`RunSpecError`. Returns the validated `RunSpec` on valid input.
"""
function parse_spec(raw::AbstractDict)::RunSpec
    problems = String[]
    append!(problems, _key_problems(raw, ("run", "model", "runtime", "logging"), "spec"))

    function section(name::String)
        haskey(raw, name) || return nothing
        table = raw[name]
        table isa AbstractDict ||
            push!(problems, "[$name] must be a table, got $(repr(table))")
        return table isa AbstractDict ? table : nothing
    end

    run_raw = section("run")
    run_raw === nothing &&
        !haskey(raw, "run") &&
        push!(problems, "[run] missing required table \"run\"")
    run_name = "unnamed"
    seed = 0
    if run_raw !== nothing
        append!(problems, _key_problems(run_raw, ("name", "seed"), "run"))
        if haskey(run_raw, "name")
            if run_raw["name"] isa String
                run_name = run_raw["name"]
            else
                push!(problems, "[run.name] must be a string, got $(repr(run_raw["name"]))")
            end
        end
        if !haskey(run_raw, "seed")
            push!(problems, "[run] missing required key \"seed\"")
        elseif run_raw["seed"] isa Bool ||
               !(run_raw["seed"] isa Integer) ||
               run_raw["seed"] < 0
            push!(problems, "[run.seed] must be an integer >= 0, got $(repr(run_raw["seed"]))")
        else
            seed = Int(run_raw["seed"])
        end
    end

    model_raw = section("model")
    model_raw === nothing &&
        !haskey(raw, "model") &&
        push!(problems, "[model] missing required table \"model\"")
    model = nothing
    model_config = nothing
    if model_raw !== nothing
        model_name = nothing
        if !haskey(model_raw, "name")
            push!(problems, "[model] missing required key \"name\"")
        elseif !(model_raw["name"] isa String)
            push!(problems, "[model.name] must be a string, got $(repr(model_raw["name"]))")
        else
            model_name = model_raw["name"]
            try
                model = resolve_model(model_name)
            catch e
                e isa ArgumentError || rethrow()
                push!(problems, "[model.name] $(e.msg)")
            end
        end
        if model !== nothing
            config_raw = Dict{String,Any}(string(k) => v for (k, v) in model_raw if string(k) != "name")
            try
                model_config = parse_model_config(model, config_raw)
            catch e
                e isa RunSpecError || rethrow()
                append!(problems, e.problems)
            end
        end
    end

    runtime_raw = section("runtime")
    runtime_raw === nothing &&
        !haskey(raw, "runtime") &&
        push!(problems, "[runtime] missing required table \"runtime\"")
    ticks = 0
    if runtime_raw !== nothing
        append!(problems, _key_problems(runtime_raw, ("ticks",), "runtime"))
        if !haskey(runtime_raw, "ticks")
            push!(problems, "[runtime] missing required key \"ticks\"")
        elseif runtime_raw["ticks"] isa Bool ||
               !(runtime_raw["ticks"] isa Integer) ||
               runtime_raw["ticks"] < 1
            push!(
                problems,
                "[runtime.ticks] must be an integer >= 1, got $(repr(runtime_raw["ticks"]))",
            )
        else
            ticks = Int(runtime_raw["ticks"])
        end
    end

    available_metrics = String[]
    if model !== nothing
        available_metrics = sort!(collect(keys(model_metrics(model))))
    end
    metric_names = copy(available_metrics)
    outputs = OutputSpec[]
    logging_raw = haskey(raw, "logging") ? section("logging") : nothing
    if logging_raw !== nothing
        append!(problems, _key_problems(logging_raw, ("metrics", "outputs"), "logging"))
        if haskey(logging_raw, "metrics")
            entries = logging_raw["metrics"]
            if !(entries isa AbstractVector)
                push!(
                    problems,
                    "[logging.metrics] must be an array of strings, got $(repr(entries))",
                )
            else
                names = String[]
                for entry in entries
                    if !(entry isa String)
                        push!(
                            problems,
                            "[logging.metrics] entry must be a string, got $(repr(entry))",
                        )
                    else
                        push!(names, entry)
                    end
                end
                metric_names = names
                if model !== nothing
                    for entry in names
                        entry in available_metrics || push!(
                            problems,
                            "[logging.metrics] unknown metric \"$entry\" (available: $(join(available_metrics, ", ")))",
                        )
                    end
                end
                seen = Set{String}()
                reported = Set{String}()
                for entry in names
                    if entry in seen && !(entry in reported)
                        push!(problems, "[logging.metrics] duplicate metric name \"$entry\"")
                        push!(reported, entry)
                    end
                    push!(seen, entry)
                end
            end
        end
        if haskey(logging_raw, "outputs")
            entries = logging_raw["outputs"]
            if !(entries isa AbstractVector)
                push!(
                    problems,
                    "[logging.outputs] must be an array of tables, got $(repr(entries))",
                )
            else
                for (i, entry) in enumerate(entries)
                    if !(entry isa AbstractDict)
                        push!(
                            problems,
                            "[logging.outputs] entry $i must be a table, got $(repr(entry))",
                        )
                        continue
                    end
                    if !haskey(entry, "type")
                        push!(problems, "[logging.outputs] entry $i missing required key \"type\"")
                        continue
                    end
                    if !(entry["type"] isa String)
                        push!(
                            problems,
                            "[logging.outputs] entry $i output \"type\" must be a string, got $(repr(entry["type"]))",
                        )
                        continue
                    end
                    args = Dict{String,Any}(
                        string(k) => v for (k, v) in entry if string(k) != "type"
                    )
                    output = OutputSpec(entry["type"], args)
                    append!(problems, validate_output_spec(output, "[logging.outputs[$i]]"))
                    push!(outputs, output)
                end
            end
        end
    end

    isempty(problems) || throw(RunSpecError(problems))
    return RunSpec(
        run_name,
        seed,
        string(raw["model"]["name"]),
        model_config,
        RuntimeConfig(ticks),
        LoggingConfig(metric_names, outputs),
    )
end

"""
    load_spec(path::AbstractString)::RunSpec

Read a TOML run specification file and validate it (see `ADR-0012`).
Takes the file path, parses it with `TOML.parsefile`, and validates
the result with `parse_spec`. Throws `RunSpecError` with a single
problem line on an unreadable path or a TOML syntax error, and the
aggregated `RunSpecError` of `parse_spec` on invalid content. Returns
the validated `RunSpec`.
"""
function load_spec(path::AbstractString)::RunSpec
    raw = try
        TOML.parsefile(path)
    catch e
        throw(RunSpecError(["[spec] cannot load \"$path\": $(sprint(showerror, e))"]))
    end
    return parse_spec(raw)
end

"""
    spec_to_dict(spec::RunSpec)::Dict{String,Any}

Echo a validated run specification back into the accepted TOML input
shape (see `ADR-0012`). Takes the `RunSpec` and returns a
TOML-printable dictionary with the `run`, `model` (the
`config_to_dict` echo plus `name`), `runtime`, and `logging` tables,
so `parse_spec(spec_to_dict(spec))` round-trips.
"""
function spec_to_dict(spec::RunSpec)::Dict{String,Any}
    model_dict = config_to_dict(resolve_model(spec.model_name), spec.model_config)
    model_dict["name"] = spec.model_name
    outputs = Any[
        Dict{String,Any}("type" => output.type, output.args...) for output in spec.logging.outputs
    ]
    return Dict{String,Any}(
        "run" => Dict{String,Any}("name" => spec.name, "seed" => spec.seed),
        "model" => model_dict,
        "runtime" => Dict{String,Any}("ticks" => spec.runtime.ticks),
        "logging" => Dict{String,Any}(
            "metrics" => copy(spec.logging.metrics),
            "outputs" => outputs,
        ),
    )
end
