# Run record catalog of the dashboard runtime.
#
# `scan_records` discovers only direct `runs/<id>/run.toml` children of
# the record root (ignoring dot-directories such as
# `runs/.dashboard-staging`); `catalog_signature` fingerprints that same
# set cheaply so callers can skip unchanged rescans; `read_record`
# validates one record into a
# `RunPath`. Malformed records become per-record diagnostics, never
# exceptions that break the catalog: a bad or missing spec disables
# cloning but not visualization. `promote_record!` promotes a staged run
# directory into the catalog atomically (staged into a hidden
# destination-side directory, then renamed into place in one
# same-filesystem rename).

"""
    RECORD_STATUS_STATES

Mapping of the `[run] status` strings of a record onto dashboard
states: `"success"` becomes `JOB_COMPLETED` and `"failure"` becomes
`JOB_MODEL_FAILED`. Any other status string is a record diagnostic.
"""
const RECORD_STATUS_STATES = Dict{String, JobState}(
    "success" => JOB_COMPLETED,
    "failure" => JOB_MODEL_FAILED,
)

"""
    RecordCache

Validation cache of `read_record` keyed by absolute record path. Each
entry stores the file size, modification time, and the resulting
`RunPath`; a record is re-read only when its size or modification time
changed. `scan_records` shares one cache across scans.
"""
mutable struct RecordCache
    entries::Dict{String, Tuple{Int, Float64, RunPath}}
end

"""
    RecordCache()

Construct an empty record validation cache. Takes no arguments and
returns the cache.
"""
RecordCache() = RecordCache(Dict{String, Tuple{Int, Float64, RunPath}}())

"""
    _parse_timestamp(text, key::String, diagnostics::Vector{String})

Parse one ISO-8601 timestamp of a record. Takes the raw value, the key
path used in the diagnostic, and the shared diagnostic list. Pushes a
diagnostic when the value is not a parseable timestamp string.
Returns the `Dates.DateTime` or `nothing`.
"""
function _parse_timestamp(
        text,
        key::String,
        diagnostics::Vector{String},
    )::Union{Nothing, Dates.DateTime}
    if !(text isa AbstractString)
        push!(diagnostics, "[$key] must be an ISO-8601 timestamp string, got $(repr(text))")
        return nothing
    end
    timestamp = try
        Dates.DateTime(text)
    catch
        nothing
    end
    timestamp === nothing &&
        push!(diagnostics, "[$key] must be an ISO-8601 timestamp, got $(repr(text))")
    return timestamp
end

"""
    _read_run_table(raw, path::AbstractString, diagnostics::Vector{String})

Validate the `[run]` table of one record. Takes the parsed TOML, the
record path, and the shared diagnostic list. Checks the required keys
`id`, `name`, `model`, `status`, `seed`, `started_at`, `finished_at`,
and `ticks_executed`, the UUID parseability of `id`, its agreement
with the directory name, and the recognized `status` strings of
`RECORD_STATUS_STATES`. Returns a named tuple of the validated fields
with fallbacks for invalid entries.
"""
function _read_run_table(
        raw,
        path::AbstractString,
        diagnostics::Vector{String},
    )
    id = ""
    name = ""
    model = ""
    state = JOB_WORKER_FAILED
    seed = 0
    started_at = nothing
    finished_at = nothing
    ticks_executed = -1
    error = ""
    if !haskey(raw, "run") || !(raw["run"] isa AbstractDict)
        push!(diagnostics, "[run] missing required table \"run\"")
        return (; id, name, model, state, seed, started_at, finished_at, ticks_executed, error)
    end
    table = raw["run"]
    if get(table, "id", nothing) isa AbstractString
        id = String(table["id"])
        try
            UUIDs.UUID(id)
        catch
            push!(diagnostics, "[run.id] must be a UUID, got $(repr(table["id"]))")
        end
        expected = basename(dirname(path))
        expected == id ||
            push!(diagnostics, "[run.id] is $(repr(id)) but the record directory is $(repr(expected))")
    else
        push!(diagnostics, "[run] missing required key \"id\" or not a string")
    end
    if get(table, "name", nothing) isa AbstractString
        name = String(table["name"])
    else
        push!(diagnostics, "[run] missing required key \"name\" or not a string")
    end
    if get(table, "model", nothing) isa AbstractString
        model = String(table["model"])
    else
        push!(diagnostics, "[run] missing required key \"model\" or not a string")
    end
    status = get(table, "status", nothing)
    if status isa AbstractString && haskey(RECORD_STATUS_STATES, status)
        state = RECORD_STATUS_STATES[status]
    else
        push!(
            diagnostics,
            "[run.status] must be one of $(join(sort!(collect(keys(RECORD_STATUS_STATES))), ", ")), got $(repr(status))",
        )
    end
    seed_raw = get(table, "seed", nothing)
    if seed_raw isa Integer && !(seed_raw isa Bool) && seed_raw >= 0
        seed = Int(seed_raw)
    else
        push!(diagnostics, "[run.seed] must be an integer >= 0, got $(repr(seed_raw))")
    end
    started_at = _parse_timestamp(get(table, "started_at", nothing), "run.started_at", diagnostics)
    finished_at = _parse_timestamp(
        get(table, "finished_at", nothing),
        "run.finished_at",
        diagnostics,
    )
    executed_raw = get(table, "ticks_executed", nothing)
    if executed_raw isa Integer && !(executed_raw isa Bool) && executed_raw >= 0
        ticks_executed = Int(executed_raw)
    else
        push!(diagnostics, "[run.ticks_executed] must be an integer >= 0, got $(repr(executed_raw))")
    end
    error_raw = get(table, "error", nothing)
    if error_raw !== nothing
        if error_raw isa AbstractString
            error = String(error_raw)
        else
            push!(diagnostics, "[run.error] must be a string, got $(repr(error_raw))")
        end
    end
    return (; id, name, model, state, seed, started_at, finished_at, ticks_executed, error)
end

"""
    _read_metrics_table(raw, diagnostics::Vector{String})

Validate the `[metrics]` table of one record. Takes the parsed TOML and
the shared diagnostic list. Requires the `tick` array of non-negative
strictly increasing integers and checks every metric array for numeric
entries and a length matching `tick`; non-numeric entries become `NaN`
with a diagnostic, non-finite numbers are kept as data, and a column
whose length disagrees with `tick` is excluded entirely (with a
diagnostic) so one bad column can never misalign or hide the remaining
ones. Returns the `(ticks, metrics)` pair, empty on a missing table.
"""
function _read_metrics_table(raw, diagnostics::Vector{String})::Tuple{Vector{Int}, Dict{String, Vector{Float64}}}
    metrics = Dict{String, Vector{Float64}}()
    if !haskey(raw, "metrics") || !(raw["metrics"] isa AbstractDict)
        push!(diagnostics, "[metrics] missing required table \"metrics\"")
        return (Int[], metrics)
    end
    table = raw["metrics"]
    ticks = Int[]
    ticks_usable = false
    ticks_raw = get(table, "tick", nothing)
    if !(ticks_raw isa AbstractVector)
        push!(diagnostics, "[metrics] missing required key \"tick\" or not an array")
    else
        ticks_usable = true
        for entry in ticks_raw
            if !(entry isa Integer) || entry isa Bool || entry < 0
                push!(
                    diagnostics,
                    "[metrics.tick] entries must be integers >= 0, got $(repr(ticks_raw))",
                )
                ticks_usable = false
                empty!(ticks)
                break
            end
            push!(ticks, Int(entry))
        end
        for i in 2:length(ticks)
            if ticks[i - 1] >= ticks[i]
                push!(
                    diagnostics,
                    "[metrics.tick] must be strictly increasing, got $(repr(ticks_raw))",
                )
                break
            end
        end
    end
    for name in sort!(String[String(key) for key in keys(table)])
        name == "tick" && continue
        series_raw = table[name]
        if !(series_raw isa AbstractVector)
            push!(diagnostics, "[metrics] \"$name\" must be an array of numbers, got $(repr(series_raw))")
            continue
        end
        series = Float64[]
        for (i, entry) in enumerate(series_raw)
            if entry isa Real && !(entry isa Bool)
                push!(series, Float64(entry))
            else
                push!(
                    diagnostics,
                    "[metrics] \"$name\" entry $i must be a number, got $(repr(entry))",
                )
                push!(series, NaN)
            end
        end
        if ticks_usable && length(series) != length(ticks)
            push!(
                diagnostics,
                "[metrics] \"$name\" has $(length(series)) values but \"tick\" has $(length(ticks)); column excluded",
            )
            continue
        end
        metrics[name] = series
    end
    return (ticks, metrics)
end

"""
    _read_record_file(path::AbstractString)::RunPath

Read and validate one `run.toml` record without caching. Takes the
record path and builds the `RunPath` from the `[run]`, `[spec]`, and
`[metrics]` tables. Unreadable or malformed content becomes record
diagnostics; a missing or invalid `[spec]` becomes spec problems that
disable cloning but not visualization. Returns the run path with
`source` `:recorded` and `record_path` set.
"""
function _read_record_file(path::AbstractString)::RunPath
    raw = try
        TOML.parsefile(path)
    catch err
        return RunPath(
            source = :recorded,
            state = JOB_WORKER_FAILED,
            diagnostics = ["[record] cannot load \"$path\": $(sprint(showerror, err))"],
            record_path = String(path),
        )
    end
    diagnostics = String[]
    spec_problems = String[]
    run = _read_run_table(raw, path, diagnostics)
    ticks, metrics = _read_metrics_table(raw, diagnostics)
    run.ticks_executed == length(ticks) || push!(
        diagnostics,
        "[run.ticks_executed] is $(run.ticks_executed) but \"tick\" has $(length(ticks)) entries",
    )
    spec = nothing
    ticks_requested = length(ticks)
    if !haskey(raw, "spec") || !(raw["spec"] isa AbstractDict)
        push!(spec_problems, "[spec] missing required table \"spec\"")
    else
        try
            spec = GN.parse_spec(raw["spec"])
            ticks_requested = spec.runtime.ticks
        catch err
            if err isa GN.RunSpecError
                append!(spec_problems, err.problems)
            else
                push!(spec_problems, "[spec] cannot parse: $(sprint(showerror, err))")
            end
        end
    end
    return RunPath(
        run_id = run.id,
        name = run.name,
        seed = run.seed,
        source = :recorded,
        state = run.state,
        started_at = run.started_at,
        finished_at = run.finished_at,
        ticks_requested = ticks_requested,
        ticks_executed = run.ticks_executed < 0 ? length(ticks) : run.ticks_executed,
        error = run.error,
        ticks = ticks,
        metrics = metrics,
        spec = spec,
        spec_problems = spec_problems,
        diagnostics = diagnostics,
        record_path = String(path),
    )
end

"""
    read_record(path::AbstractString, cache::RecordCache = RecordCache())::RunPath

Read one run record into a `RunPath`. Takes the path of a `run.toml`
and an optional `RecordCache`; cached results are reused while the file
size and modification time are unchanged. Returns an independent copy
of the validated run path; malformed records yield a run path whose
`diagnostics` or `spec_problems` describe the problems instead of
throwing.
"""
function read_record(
        path::AbstractString,
        cache::RecordCache = RecordCache(),
    )::RunPath
    key = abspath(path)
    if isfile(path)
        info = stat(path)
        cached = get(cache.entries, key, nothing)
        if cached !== nothing && cached[1] == info.size && cached[2] == info.mtime
            return copy_path(cached[3])
        end
    end
    record = _read_record_file(path)
    if isfile(path)
        info = stat(path)
        cache.entries[key] = (info.size, info.mtime, record)
    end
    return copy_path(record)
end

"""
    scan_records(root::AbstractString, cache::RecordCache = RecordCache())::RecordIndex

Discover the run records under one record root. Takes the runs root
directory and an optional shared `RecordCache`, and scans only direct
`runs/<id>/run.toml` children; dot-directories such as
`runs/.dashboard-staging` and entries without `run.toml` are ignored.
Malformed records appear with diagnostics and never abort the scan.
Returns the `RecordIndex` sorted by record directory name.
"""
function scan_records(
        root::AbstractString,
        cache::RecordCache = RecordCache(),
    )::RecordIndex
    problems = Dict{String, Vector{String}}()
    records = RunPath[]
    if !isdir(root)
        problems[String(root)] = ["[records] record root \"$root\" is not a directory"]
        return RecordIndex(String(root), Dates.now(), records, problems)
    end
    for entry in sort!(readdir(root))
        startswith(entry, ".") && continue
        directory = joinpath(root, entry)
        isdir(directory) || continue
        record_file = joinpath(directory, "run.toml")
        isfile(record_file) || continue
        push!(records, read_record(record_file, cache))
    end
    return RecordIndex(String(root), Dates.now(), records, problems)
end

"""
    catalog_signature(root::AbstractString)::UInt64

Lightweight signature of the record catalog under one record root.
Takes the runs root and hashes the name, size, and modification time of
every direct `runs/<id>/run.toml` child (dot-directories such as
`runs/.dashboard-staging` are ignored), without reading any record
content. Two equal signatures mean the catalog is unchanged, so a
caller can skip a full `scan_records` rescan; the signature changes when
a record appears, disappears, or is rewritten. Returns the signature
(zero for a missing root).
"""
function catalog_signature(root::AbstractString)::UInt64
    isdir(root) || return zero(UInt64)
    signature = zero(UInt64)
    for entry in sort!(readdir(root))
        startswith(entry, ".") && continue
        record_file = joinpath(root, entry, "run.toml")
        isfile(record_file) || continue
        info = stat(record_file)
        signature = hash((entry, info.size, info.mtime), signature)
    end
    return signature
end

"""
    _stage_record!(staged::AbstractString, hidden::AbstractString)

Move or copy one staged run directory onto the destination filesystem.
Takes the staged directory and the hidden destination-side directory (a
dot-directory `scan_records` ignores). Renames in one step when both
sides share a filesystem; otherwise copies into the hidden directory and
leaves the source in place, deferring its removal to `promote_record!`
after successful publication, so a failing source cleanup can never
destroy the only complete copy. A failed copy removes the partial hidden
directory and rethrows with the source untouched. Returns nothing.
Helper of `promote_record!`.
"""
function _stage_record!(staged::AbstractString, hidden::AbstractString)
    try
        Base.Filesystem.rename(staged, hidden)
    catch
        try
            cp(staged, hidden)
        catch
            ispath(hidden) && rm(hidden; recursive = true, force = true)
            rethrow()
        end
    end
    return nothing
end

"""
    promote_record!(staged::AbstractString, runs_root::AbstractString; rename::Function = Base.Filesystem.rename, diagnostics::Vector{String} = String[])::Union{String,Vector{String}}

Promote one staged run record into the catalog. Takes the staged run
directory holding `run.toml` and the record root, plus the `rename`
function used for the final visibility step (injectable for tests) and a
`diagnostics` sink for success-path notes. Validates the record with
`read_record` first: records with record-structure diagnostics
(including malformed ones) are left in staging, while complete success
and model-failure records are promoted. Promotion is atomic for catalog
scans: the staged directory is first moved into a hidden
`.promoting-<uuid>` directory under the record root (dot-directories are
invisible to `scan_records`, including the cross-filesystem copy
fallback), and that directory is renamed onto `runs/<run-id>/` in one
same-filesystem rename, so a scan either sees no record or the complete
one. A cross-filesystem source copy is removed only after successful
publication; when that deferred cleanup fails, the published record
stands and the leftover source location is appended to `diagnostics`.
Spec problems do not block promotion (they only disable cloning).
Promotion failures clean up their artifacts and return the problem
lines instead of throwing. Returns the promoted `run.toml` path, or the
problem lines when the record was not promoted.
"""
function promote_record!(
        staged::AbstractString,
        runs_root::AbstractString;
        rename::Function = Base.Filesystem.rename,
        diagnostics::Vector{String} = String[],
    )::Union{String, Vector{String}}
    record_file = joinpath(staged, "run.toml")
    isfile(record_file) ||
        return ["[record] missing \"$record_file\"; record not promoted"]
    record = read_record(record_file)
    if !isempty(record.diagnostics)
        return vcat(
            ["[record] \"$record_file\" failed validation; record not promoted"],
            record.diagnostics,
        )
    end
    destination = joinpath(runs_root, record.run_id)
    ispath(destination) &&
        return ["[record] destination \"$destination\" already exists; record not promoted"]
    hidden = joinpath(runs_root, ".promoting-$(UUIDs.uuid4())")
    try
        mkpath(runs_root)
        _stage_record!(staged, hidden)
    catch err
        ispath(hidden) && rm(hidden; recursive = true, force = true)
        return [
            "[record] cannot stage \"$staged\" under \"$runs_root\": " *
                "$(sprint(showerror, err)); record not promoted",
        ]
    end
    try
        rename(hidden, destination)
    catch err
        try
            mv(hidden, staged)
            hidden = ""
        catch
            # The record stays in the hidden directory as evidence; it is
            # invisible to catalog scans and the diagnostic names it below.
        end
        isempty(hidden) && return [
            "[record] cannot move \"$staged\" into place at \"$destination\": " *
                "$(sprint(showerror, err)); record restored to staging",
        ]
        return [
            "[record] cannot move \"$staged\" into place at \"$destination\": " *
                "$(sprint(showerror, err)); record left at \"$hidden\"",
        ]
    end
    if ispath(staged)
        try
            rm(staged; recursive = true)
        catch err
            push!(
                diagnostics,
                "[record] promoted but cannot remove the staging copy \"$staged\": " *
                    "$(sprint(showerror, err)); left in place",
            )
        end
    end
    return joinpath(destination, "run.toml")
end
