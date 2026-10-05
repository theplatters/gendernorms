# Versioned JSONL protocol between the run manager and worker
# processes. Messages are plain primitive dictionaries on the wire, one
# JSON object per line: `handshake`, `started`, `rows`, `finished`,
# `failed`, and `cancelled`. `encode_message` validates before writing
# and maps non-finite metric values to the tokens `"NaN"`, `"Inf"`, and
# `"-Inf"` (JSON has no non-finite literals); `decode_message` is strict
# and rejects malformed messages with a `ProtocolError`.

"""
    PROTOCOL_VERSION

Version number of the worker protocol. A `handshake` message must carry
exactly this value in `protocol_version`; `decode_message` rejects
other versions.
"""
const PROTOCOL_VERSION = 1

"""
    NONFINITE_TOKENS

Wire tokens for non-finite metric values. JSON cannot represent `NaN`
or `Inf`, so `encode_message` writes these strings and `decode_message`
maps them back to `NaN`, `Inf`, and `-Inf`.
"""
const NONFINITE_TOKENS = ("NaN", "Inf", "-Inf")

"""
    ProtocolError <: Exception

Aggregated worker protocol failure. Field `problems` holds one problem
line per malformed message field, for example `[rows] missing required
key "ticks"`.
"""
struct ProtocolError <: Exception
    problems::Vector{String}
end

"""
    Base.showerror(io::IO, err::ProtocolError)

Print an aggregated worker protocol failure. Shows `invalid protocol
message:` followed by one `- ` line per problem in `err.problems`.
Returns nothing.
"""
function Base.showerror(io::IO, err::ProtocolError)
    print(io, "invalid protocol message:")
    for problem in err.problems
        print(io, "\n- ", problem)
    end
    return nothing
end

"""
    MESSAGE_SCHEMAS

Field schemas of the worker protocol messages. Maps each message type
to its required fields with their kinds: `:string`, `:int`,
`:string_vector`, `:int_vector`, or `:metric_table`. Unknown fields and
unknown types are rejected by `validate_message`.
"""
const MESSAGE_SCHEMAS = Dict{String, Dict{String, Symbol}}(
    "handshake" => Dict{String, Symbol}("protocol_version" => :int, "job_id" => :string),
    "started" => Dict{String, Symbol}(
        "run_id" => :string,
        "name" => :string,
        "model_name" => :string,
        "metric_names" => :string_vector,
        "started_at" => :string,
        "ticks_requested" => :int,
    ),
    "rows" => Dict{String, Symbol}("ticks" => :int_vector, "metrics" => :metric_table),
    "finished" => Dict{String, Symbol}(
        "run_id" => :string,
        "outcome" => :string,
        "error" => :string,
        "ticks_executed" => :int,
        "finished_at" => :string,
    ),
    "failed" => Dict{String, Symbol}("error" => :string, "stage" => :string),
    "cancelled" => Dict{String, Symbol}("run_id" => :string),
)

"""
    FINISHED_OUTCOMES

Allowed values of the `outcome` field of a `finished` message:
`"success"` when every tick completed and `"model_failure"` when the
model run recorded a failure.
"""
const FINISHED_OUTCOMES = ("success", "model_failure")

"""
    _is_int_value(value)::Bool

Report whether `value` is a protocol integer. Returns true for
non-boolean `Integer` values, the only shape `encode_message` writes
for `:int` and `:int_vector` fields.
"""
_is_int_value(value)::Bool = value isa Integer && !(value isa Bool)

"""
    _is_metric_value(value)::Bool

Report whether `value` is one protocol metric value. Returns true for
non-boolean `Real` numbers and for the non-finite tokens listed in
`NONFINITE_TOKENS`.
"""
function _is_metric_value(value)::Bool
    value isa Real && !(value isa Bool) && return true
    return value isa AbstractString && value in NONFINITE_TOKENS
end

"""
    _check_field_kind(value, kind::Symbol)::Bool

Check one message field against its schema kind. Takes the raw field
value and the `MESSAGE_SCHEMAS` kind. Returns true when the value has
the required shape: `:string` requires a string, `:int` a protocol
integer, `:string_vector` a vector of strings, `:int_vector` a vector
of protocol integers, and `:metric_table` a string-keyed table of
vectors of metric values.
"""
function _check_field_kind(value, kind::Symbol)::Bool
    kind === :string && return value isa AbstractString
    kind === :int && return _is_int_value(value)
    kind === :string_vector &&
        return value isa AbstractVector && all(entry -> entry isa AbstractString, value)
    kind === :int_vector &&
        return value isa AbstractVector && all(entry -> _is_int_value(entry), value)
    if kind === :metric_table
        value isa AbstractDict || return false
        for (key, series) in value
            key isa AbstractString || return false
            series isa AbstractVector || return false
            all(_is_metric_value, series) || return false
        end
        return true
    end
    return false
end

"""
    validate_message(msg::AbstractDict)::Vector{String}

Validate one protocol message dictionary. Takes the message and checks
its `type` against `MESSAGE_SCHEMAS`, rejecting unknown types, unknown
keys, missing keys, wrong field kinds, metric vectors that do not match
the `ticks` length, `outcome` values outside `FINISHED_OUTCOMES`, and a
`handshake` version other than `PROTOCOL_VERSION`. Returns the problem
lines, empty for a valid message.
"""
function validate_message(msg::AbstractDict)::Vector{String}
    problems = String[]
    if !haskey(msg, "type")
        push!(problems, "[message] missing required key \"type\"")
        return problems
    end
    kind = msg["type"]
    if !(kind isa AbstractString) || !haskey(MESSAGE_SCHEMAS, kind)
        push!(
            problems,
            "[message] unknown type $(repr(kind)) " *
                "(known: $(join(sort!(collect(keys(MESSAGE_SCHEMAS))), ", ")))",
        )
        return problems
    end
    schema = MESSAGE_SCHEMAS[kind]
    for key in sort!(String[string(key) for key in keys(msg)])
        key == "type" && continue
        haskey(schema, key) ||
            push!(problems, "[$kind] unknown key \"$key\" (allowed: $(join(sort!(collect(keys(schema))), ", ")))")
    end
    for key in sort!(collect(keys(schema)))
        if !haskey(msg, key)
            push!(problems, "[$kind] missing required key \"$key\"")
            continue
        end
        value = msg[key]
        if !_check_field_kind(value, schema[key])
            push!(problems, "[$kind] key \"$key\" must be a $(schema[key]), got $(repr(value))")
        end
    end
    if kind == "rows" && _check_field_kind(get(msg, "ticks", nothing), :int_vector) &&
            _check_field_kind(get(msg, "metrics", nothing), :metric_table)
        ticks = msg["ticks"]
        for name in sort!(String[string(key) for key in keys(msg["metrics"])])
            series = msg["metrics"][name]
            length(series) == length(ticks) ||
                push!(
                problems,
                "[rows] metric \"$name\" has $(length(series)) values but ticks has $(length(ticks))",
            )
        end
    end
    if kind == "finished" && haskey(msg, "outcome") && msg["outcome"] isa AbstractString
        outcome = msg["outcome"]
        outcome in FINISHED_OUTCOMES || push!(
            problems,
            "[finished] key \"outcome\" must be one of " *
                "$(join((repr(o) for o in FINISHED_OUTCOMES), ", ")), got $(repr(outcome))",
        )
    end
    if kind == "handshake" && _is_int_value(get(msg, "protocol_version", nothing))
        version = msg["protocol_version"]
        Int(version) == PROTOCOL_VERSION || push!(
            problems,
            "[handshake] protocol version mismatch: got $version, expected $PROTOCOL_VERSION",
        )
    end
    return problems
end

"""
    _encode_value(value)

Map one message value onto JSON-safe primitives. Takes any message
value and returns non-finite numbers as `NONFINITE_TOKENS` strings,
dictionaries and vectors as copies with recursively encoded values,
and everything else unchanged. Helper of `encode_message`.
"""
function _encode_value(value)
    if value isa AbstractFloat && !isfinite(value)
        isnan(value) && return "NaN"
        return value > 0 ? "Inf" : "-Inf"
    end
    value isa AbstractDict &&
        return Dict{String, Any}(string(key) => _encode_value(entry) for (key, entry) in value)
    value isa AbstractVector && return Any[_encode_value(entry) for entry in value]
    return value
end

"""
    _decode_metric_value(value)::Float64

Map one wire metric value back to `Float64`. Takes a `Real` number or a
`NONFINITE_TOKENS` string and returns the float, with the tokens
decoded to `NaN`, `Inf`, and `-Inf`. Helper of `decode_message`.
"""
function _decode_metric_value(value)::Float64
    value isa Real && return Float64(value)
    value == "NaN" && return NaN
    value == "Inf" && return Inf
    return -Inf
end

"""
    _decode_message(msg::Dict)::Dict{String,Any}

Normalize a validated wire message into typed values. Takes the parsed
message and returns a copy with integer fields as `Int`, string vectors
as `Vector{String}`, tick vectors as `Vector{Int}`, and metric tables
as `Dict{String,Vector{Float64}}` with `NONFINITE_TOKENS` decoded.
Helper of `decode_message`.
"""
function _decode_message(msg::Dict)::Dict{String, Any}
    out = Dict{String, Any}()
    for (key, value) in msg
        name = string(key)
        kind = get(MESSAGE_SCHEMAS[msg["type"]], name, :string)
        if kind === :int
            out[name] = Int(value)
        elseif kind === :int_vector
            out[name] = Int[Int(entry) for entry in value]
        elseif kind === :string_vector
            out[name] = String[String(entry) for entry in value]
        elseif kind === :metric_table
            out[name] = Dict{String, Vector{Float64}}(
                string(metric) => Float64[_decode_metric_value(entry) for entry in series] for
                    (metric, series) in value
            )
        else
            out[name] = value isa AbstractString ? String(value) : value
        end
    end
    return out
end

"""
    encode_message(msg::AbstractDict)::String

Encode one protocol message as a JSONL line. Takes the message
dictionary, validates it with `validate_message`, and throws
`ProtocolError` on any problem. Returns the JSON object text with a
trailing newline; non-finite metric values are written as
`NONFINITE_TOKENS` strings.
"""
function encode_message(msg::AbstractDict)::String
    problems = validate_message(msg)
    isempty(problems) || throw(ProtocolError(problems))
    return JSON.json(_encode_value(msg)) * "\n"
end

"""
    decode_message(line::AbstractString)::Dict{String,Any}

Decode one JSONL protocol message strictly. Takes the line and returns
the normalized message dictionary. Throws `ProtocolError` when the line
is not a JSON object, when `validate_message` reports problems, or
when a `handshake` carries a version other than `PROTOCOL_VERSION`.
"""
function decode_message(line::AbstractString)::Dict{String, Any}
    msg = try
        JSON.parse(line)
    catch err
        throw(ProtocolError(["[message] not valid JSON: $(sprint(showerror, err))"]))
    end
    msg isa AbstractDict ||
        throw(ProtocolError(["[message] must be a JSON object, got $(repr(line))"]))
    problems = validate_message(msg)
    isempty(problems) || throw(ProtocolError(problems))
    return _decode_message(Dict{String, Any}(string(key) => value for (key, value) in msg))
end

"""
    write_message!(io::IO, msg::AbstractDict)::Nothing

Write one encoded protocol message to a stream. Takes the stream and
the message dictionary and writes the `encode_message` line, flushing
the stream. Returns nothing.
"""
function write_message!(io::IO, msg::AbstractDict)
    write(io, encode_message(msg))
    flush(io)
    return nothing
end

"""
    handshake_message(job_id::AbstractString)::Dict{String,Any}

Build the `handshake` message a worker sends first. Takes the
dashboard job UUID string and returns the message dictionary carrying
`PROTOCOL_VERSION`.
"""
function handshake_message(job_id::AbstractString)::Dict{String, Any}
    return Dict{String, Any}(
        "type" => "handshake",
        "protocol_version" => PROTOCOL_VERSION,
        "job_id" => String(job_id),
    )
end

"""
    started_message(run_id::AbstractString, name::AbstractString, model_name::AbstractString, metric_names, started_at::AbstractString, ticks_requested::Integer)::Dict{String,Any}

Build the `started` message of a running run. Takes the run UUID, run
label, model name, evaluated metric names, ISO-8601 start timestamp,
and tick budget. Returns the message dictionary.
"""
function started_message(
        run_id::AbstractString,
        name::AbstractString,
        model_name::AbstractString,
        metric_names,
        started_at::AbstractString,
        ticks_requested::Integer,
    )::Dict{String, Any}
    return Dict{String, Any}(
        "type" => "started",
        "run_id" => String(run_id),
        "name" => String(name),
        "model_name" => String(model_name),
        "metric_names" => String[String(entry) for entry in metric_names],
        "started_at" => String(started_at),
        "ticks_requested" => Int(ticks_requested),
    )
end

"""
    rows_message(ticks, metrics)::Dict{String,Any}

Build a batched `rows` message of recorded tick rows. Takes the tick
counts and the per-metric value vectors and returns the message
dictionary; every metric vector must match the tick count.
"""
function rows_message(ticks, metrics)::Dict{String, Any}
    return Dict{String, Any}(
        "type" => "rows",
        "ticks" => Int[Int(tick) for tick in ticks],
        "metrics" => Dict{String, Vector{Float64}}(
            String(name) => Float64[Float64(value) for value in values] for
                (name, values) in metrics
        ),
    )
end

"""
    finished_message(run_id::AbstractString, outcome::AbstractString, error::AbstractString, ticks_executed::Integer, finished_at::AbstractString)::Dict{String,Any}

Build the terminal `finished` message of a completed run. Takes the
run UUID, the `FINISHED_OUTCOMES` outcome, the failure text (empty on
success), the executed tick count, and the ISO-8601 finish timestamp.
Returns the message dictionary.
"""
function finished_message(
        run_id::AbstractString,
        outcome::AbstractString,
        error::AbstractString,
        ticks_executed::Integer,
        finished_at::AbstractString,
    )::Dict{String, Any}
    return Dict{String, Any}(
        "type" => "finished",
        "run_id" => String(run_id),
        "outcome" => String(outcome),
        "error" => String(error),
        "ticks_executed" => Int(ticks_executed),
        "finished_at" => String(finished_at),
    )
end

"""
    failed_message(error::AbstractString, stage::AbstractString)::Dict{String,Any}

Build the terminal `failed` message of an infrastructure failure. Takes
the failure text and the failing stage (`"spec"`, `"setup"`, `"run"`,
or `"protocol"`). Returns the message dictionary.
"""
function failed_message(error::AbstractString, stage::AbstractString)::Dict{String, Any}
    return Dict{String, Any}("type" => "failed", "error" => String(error), "stage" => String(stage))
end

"""
    cancelled_message(run_id::AbstractString)::Dict{String,Any}

Build the terminal `cancelled` message of an interrupted run. Takes the
run UUID string (empty when the run never started) and returns the
message dictionary.
"""
function cancelled_message(run_id::AbstractString)::Dict{String, Any}
    return Dict{String, Any}("type" => "cancelled", "run_id" => String(run_id))
end
