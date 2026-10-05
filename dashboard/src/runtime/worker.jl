# Worker job execution of the dashboard runtime.
#
# `bin/run_worker.jl` runs one dashboard job in a child process: it
# parses its job (options on `argv`, spec dict on stdin), builds the
# spec, creates the world, attaches the dashboard-managed `TomlLogger`
# and the `LiveLogger`, runs `GenderNorms.run`, streams the metric rows
# while running, and emits its terminal protocol message only after
# `GenderNorms.run` returns and all published rows are drained.

"""
    WorkerJob

One dashboard worker job. Field `job_id` is the dashboard-owned job
UUID, field `spec_dict` the run spec dictionary to execute, field
`staging_dir` the job staging directory the record is written under
(`<staging_dir>/<run-id>/run.toml`), and field `record` whether the run
is recorded to a TOML record.
"""
struct WorkerJob
    job_id::UUIDs.UUID
    spec_dict::Dict{String, Any}
    staging_dir::String
    record::Bool
end

"""
    WorkerJob(; job_id, spec_dict, staging_dir, record)::WorkerJob

Construct a worker job from parsed job values. Takes the job UUID (as
`UUIDs.UUID` or UUID string), the spec dictionary, the staging
directory, and the record flag (`Bool` or the strings `"true"` and
`"false"`). Returns the job. Throws `ArgumentError` on an unparseable
UUID or record flag.
"""
function WorkerJob(;
        job_id,
        spec_dict::AbstractDict,
        staging_dir::AbstractString,
        record::Union{Bool, AbstractString},
    )::WorkerJob
    id = job_id isa UUIDs.UUID ? job_id : UUIDs.UUID(string(job_id))
    flag = if record isa Bool
        record
    elseif record == "true"
        true
    elseif record == "false"
        false
    else
        throw(ArgumentError("record must be \"true\" or \"false\", got $(repr(record))"))
    end
    return WorkerJob(
        id,
        Dict{String, Any}(string(key) => value for (key, value) in spec_dict),
        String(staging_dir),
        flag,
    )
end

"""
    WORKER_OPTION_KEYS

Required `argv` options of the worker process: `--job-id`, `--staging-dir`,
and `--record`. `parse_worker_options` rejects every other key.
"""
const WORKER_OPTION_KEYS = ("job_id", "staging_dir", "record")

"""
    parse_worker_options(args)::Dict{String,String}

Parse the `argv` options of the worker process. Takes the argument
list with `--key=value` entries and returns the key to value mapping;
dashes in keys are normalized to underscores, so `--job-id` and
`--job_id` are equivalent. Throws `ArgumentError` on arguments that
are not `--key=value`, on unknown or duplicate keys
(`WORKER_OPTION_KEYS`), and on empty keys.
"""
function parse_worker_options(args)::Dict{String, String}
    options = Dict{String, String}()
    for arg in args
        text = String(arg)
        (startswith(text, "--") && occursin('=', text)) ||
            throw(ArgumentError("worker option must have the form --key=value, got $(repr(text))"))
        eq = findfirst('=', text)
        key = replace(text[3:(eq - 1)], "-" => "_")
        value = text[(eq + 1):end]
        isempty(key) && throw(ArgumentError("worker option has an empty key, got $(repr(text))"))
        key in WORKER_OPTION_KEYS || throw(
            ArgumentError(
                "unknown worker option \"$key\" (allowed: $(join(WORKER_OPTION_KEYS, ", ")))",
            ),
        )
        haskey(options, key) && throw(ArgumentError("duplicate worker option \"$key\""))
        options[key] = value
    end
    return options
end

"""
    execution_spec_dict(job::WorkerJob)::Dict{String,Any}

Build the spec dictionary a worker executes. Takes the job and returns
a copy of its `spec_dict` whose `[logging] outputs` are replaced by the
dashboard-managed policy: one `toml` output into `staging_dir` when the
job records, and no outputs otherwise. Submitted logging outputs are
never reused, so recorded output directories cannot leak into new runs.
"""
function execution_spec_dict(job::WorkerJob)::Dict{String, Any}
    dict = Dict{String, Any}(string(key) => value for (key, value) in job.spec_dict)
    logging = get(dict, "logging", nothing)
    table = if logging isa AbstractDict
        Dict{String, Any}(string(key) => value for (key, value) in logging)
    else
        Dict{String, Any}()
    end
    table["outputs"] = if job.record
        Any[Dict{String, Any}("type" => "toml", "directory" => job.staging_dir)]
    else
        Any[]
    end
    dict["logging"] = table
    return dict
end

"""
    _emit_failure(out::IO, err::IO, stage::String, text::String)::Int

Report one infrastructure failure to the server. Takes the protocol
stream, the diagnostics stream, the failing stage, and the failure
text, writes a `failed` protocol message, and logs the text to stderr.
Returns exit code 1. Helper of `execute_worker_job`.
"""
function _emit_failure(out::IO, err::IO, stage::String, text::String)::Int
    write_message!(out, failed_message(text, stage))
    println(err, "worker failure in stage \"$stage\": ", text)
    return 1
end

"""
    execute_worker_job(job::WorkerJob, out::IO, err::IO)::Int

Execute one worker job and stream its protocol messages. Takes the
job, the protocol stream (stdout of the process), and the diagnostics
stream (stderr). Sends `handshake`, then validates the spec and creates
the world (infrastructure failures send `failed` and return 1),
attaches `GenderNorms.TomlLogger(staging_dir)` via the executed spec
when recording plus the `LiveLogger` via `GenderNorms.add_logger!`,
runs `GenderNorms.run`, and drains all published rows with
`finish_stream!` before the terminal message. `InterruptException`
sends `cancelled` and returns 3. A completed run sends `finished`:
`success` returns 0, a recorded model failure returns 2 with
`sprint(showerror, result.error)` as its error text. Setup, logger,
and protocol errors send `failed` and return 1.
"""
function execute_worker_job(job::WorkerJob, out::IO, err::IO)::Int
    write_message!(out, handshake_message(string(job.job_id)))
    spec = try
        GN.parse_spec(execution_spec_dict(job))
    catch caught
        return _emit_failure(out, err, "spec", sprint(showerror, caught))
    end
    world = try
        GN.create_world(spec)
    catch caught
        return _emit_failure(out, err, "setup", sprint(showerror, caught))
    end
    logger = LiveLogger(copy(spec.logging.metrics), spec.runtime.ticks)
    GN.add_logger!(world, logger)
    writer = StreamWriter(out, logger)
    start_stream(writer)
    result = try
        GN.run(world)
    catch caught
        finish_stream!(writer)
        if caught isa InterruptException
            run_id = logger.info === nothing ? "" : logger.info.id
            write_message!(out, cancelled_message(run_id))
            println(err, "worker cancelled")
            return 3
        end
        return _emit_failure(out, err, "run", sprint(showerror, caught))
    end
    finish_stream!(writer)
    success = GN.is_success(result)
    error_text = result.error === nothing ? "" : sprint(showerror, result.error)
    write_message!(
        out,
        finished_message(
            result.id,
            success ? "success" : "model_failure",
            error_text,
            result.ticks_executed,
            Dates.format(result.finished_at, Dates.ISODateTimeFormat),
        ),
    )
    return success ? 0 : 2
end

"""
    worker_main(args, input::IO, out::IO, err::IO)::Int

Entry point of the worker process. Takes the `argv` options, the job
spec stream (stdin), the protocol stream (stdout), and the diagnostics
stream (stderr). Parses the job with `parse_worker_options` and
`WorkerJob` (job parsing errors send `failed` and return 1) and runs
`execute_worker_job`. Returns the worker exit code.
"""
function worker_main(args, input::IO, out::IO, err::IO)::Int
    job = try
        options = parse_worker_options(args)
        for key in WORKER_OPTION_KEYS
            haskey(options, key) ||
                throw(ArgumentError("missing required worker option --$key=value"))
        end
        spec_dict = JSON.parse(read(input, String))
        spec_dict isa AbstractDict ||
            throw(ArgumentError("job spec must be a JSON object, got $(repr(spec_dict))"))
        WorkerJob(;
            job_id = options["job_id"],
            spec_dict,
            staging_dir = options["staging_dir"],
            record = options["record"],
        )
    catch caught
        return _emit_failure(out, err, "protocol", sprint(showerror, caught))
    end
    return execute_worker_job(job, out, err)
end
