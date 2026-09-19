# scripts/registry_check.jl
#
# Registry validator for the GenderNorms repository.
#
# Enforces the mechanically-checkable subset of the registry contract
# (see registry/code/conventions.md and ADR-0004): required paths exist,
# decision records (MDR/ADR) carry valid frontmatter and headings, every
# file under src/ is registered in registry/code/architecture.md, the
# include list in src/GenderNorms.jl is intact, formatting is clean
# (ASCII only, no tabs, no trailing whitespace, exactly one trailing
# newline), and skill frontmatter is valid. Top-level definitions that
# are never mentioned in registry/** are advisory warnings only.
#
# The validator uses only the Julia standard library (Base) and runs
# under a bare julia with no project activated. The repository root is
# resolved as the parent of this script's own directory.
#
# Usage:
#   julia --project=. scripts/registry_check.jl [--strict] [--quiet]
# The exit code is 0 iff there are no errors (and, under --strict, no
# warnings); otherwise it is 1.

const VALID_STATUSES = ("proposed", "accepted", "rejected", "superseded", "deprecated")

const REQUIRED_PATHS = (
    "AGENTS.md",
    "opencode.json",
    "registry/README.md",
    "registry/templates/decision.md",
    "registry/model/README.md",
    "registry/model/entities.md",
    "registry/model/parameters.md",
    "registry/model/processes.md",
    "registry/code/README.md",
    "registry/code/architecture.md",
    "registry/code/conventions.md",
)

const REQUIRED_HEADINGS = ("## Context", "## Decision", "## Consequences")

const REQUIRED_RECORD_KEYS = ("id", "title", "status", "date")

const DEF_PATTERNS = (
    r"^function\s+([A-Za-z_]\w*)",
    r"^mutable struct\s+([A-Za-z_]\w*)",
    r"^struct\s+([A-Za-z_]\w*)",
    r"^abstract type\s+([A-Za-z_]\w*)",
    r"^Base\.@kwdef struct\s+([A-Za-z_]\w*)",
)

const INCLUDE_PATTERN = r"include\s*\(\s*\"([^\"]+)\"\s*\)"
const FILENAME_ID_PATTERN = r"^([A-Z]+-\d{4})-"
const DATE_PATTERN = r"^\d{4}-\d{2}-\d{2}$"
const TRAILING_WS_PATTERN = r"[ \t\r]+$"
const EXCLUDED_MARKER = "Excluded from module:"

# Mutable counters plus CLI flags shared by every check.
mutable struct CheckState
    strict::Bool
    quiet::Bool
    n_ok::Int
    n_warn::Int
    n_err::Int
end

function report_ok!(st::CheckState, msg::String)
    st.n_ok += 1
    st.quiet || println("[OK] " * msg)
    return nothing
end

function report_warn!(st::CheckState, msg::String)
    st.n_warn += 1
    println("[WARN] " * msg)
    return nothing
end

function report_error!(st::CheckState, msg::String)
    st.n_err += 1
    println("[ERROR] " * msg)
    return nothing
end

# Read a file as text; return nothing when it cannot be read.
function try_read_text(path::String)::Union{String,Nothing}
    try
        return read(path, String)
    catch
        return nothing
    end
end

# Collect repo-relative paths (forward slashes, sorted) under a directory.
function list_files(root::String, dir::String, ext::String)::Vector{String}
    out = String[]
    base = joinpath(root, dir)
    isdir(base) || return out
    for (dp, _, fns) in walkdir(base)
        for f in fns
            endswith(f, ext) || continue
            rel = relpath(joinpath(dp, f), root)
            push!(out, replace(rel, "\\" => "/"))
        end
    end
    sort!(out)
    return out
end

function skill_files(root::String)::Vector{String}
    base = joinpath(root, ".opencode", "skills")
    out = String[]
    isdir(base) || return out
    for d in sort(readdir(base))
        if isfile(joinpath(base, d, "SKILL.md"))
            push!(out, ".opencode/skills/" * d * "/SKILL.md")
        end
    end
    return out
end

function decision_files(root::String)::Vector{String}
    out = String[]
    for d in ("registry/model/decisions", "registry/code/decisions")
        dir = joinpath(root, d)
        isdir(dir) || continue
        for f in sort(readdir(dir))
            if endswith(f, ".md") && (startswith(f, "MDR-") || startswith(f, "ADR-"))
                push!(out, d * "/" * f)
            end
        end
    end
    sort!(out)
    return out
end

# A frontmatter value counts as empty when blank or trivially quoted.
function is_empty_value(v::String)::Bool
    s = strip(v)
    return s == "" || s == "\"\"" || s == "''"
end

# Parsed frontmatter (flat key/value map), body lines, and parse errors.
struct ParsedRecord
    front::Dict{String,String}
    body::Vector{String}
    errors::Vector{String}
end

# Split raw text into lines without keeping endings. A single trailing
# newline leaves a sentinel empty element that is not a real line.
function text_lines(content::String)::Vector{String}
    lines = String.(split(content, "\n"))
    if endswith(content, "\n")
        pop!(lines)
    end
    return lines
end

# Parse flat `key: value` frontmatter between `---` delimiters. Never
# throws: malformed input is reported through the errors vector.
function parse_record(content::String)::ParsedRecord
    front = Dict{String,String}()
    errors = String[]
    raw = String.(split(content, "\n"))
    if isempty(raw) || strip(raw[1]) != "---"
        push!(errors, "missing opening `---` frontmatter delimiter on line 1")
        return ParsedRecord(front, raw, errors)
    end
    closing = 0
    for i in 2:length(raw)
        if strip(raw[i]) == "---"
            closing = i
            break
        end
    end
    if closing == 0
        push!(errors, "missing closing `---` frontmatter delimiter")
    end
    front_lines = closing == 0 ? raw[2:end] : raw[2:closing-1]
    body = closing == 0 ? String[] : raw[closing+1:end]
    for (k, line) in enumerate(front_lines)
        s = strip(line)
        isempty(s) && continue
        parts = split(s, ":", limit = 2)
        if length(parts) < 2
            push!(errors, "frontmatter line $(k + 1) is not a flat `key: value` line")
            continue
        end
        key = String(strip(parts[1]))
        value = String(strip(parts[2]))
        if isempty(key)
            push!(errors, "frontmatter line $(k + 1) has an empty key")
            continue
        end
        front[key] = value
    end
    return ParsedRecord(front, body, errors)
end

# Extract `<PREFIX>-<NNNN>` record identifiers from a frontmatter value.
function record_ids_in(value::String)::Vector{String}
    return String[m.match for m in eachmatch(r"[A-Z]+-\d{4}", value)]
end

# A required level-2 heading counts when a body line starts with it and
# continues with nothing, a space, or a tab.
function has_heading(body::Vector{String}, heading::String)::Bool
    for line in body
        if line == heading || startswith(line, heading * " ") || startswith(line, heading * "\t")
            return true
        end
    end
    return false
end

function check_required_paths(st::CheckState, root::String)
    for rel in REQUIRED_PATHS
        if isfile(joinpath(root, rel))
            report_ok!(st, rel * ": required path exists")
        else
            report_error!(st, rel * ": required path is missing")
        end
    end
    skills = skill_files(root)
    if isempty(skills)
        report_error!(st, ".opencode/skills: no `*/SKILL.md` file found")
    else
        report_ok!(st, ".opencode/skills: found $(length(skills)) `*/SKILL.md` file(s)")
    end
    return nothing
end

function check_decision_records(st::CheckState, root::String)
    rels = decision_files(root)
    parsed = Dict{String,ParsedRecord}()
    for rel in rels
        content = try_read_text(joinpath(root, rel))
        if content === nothing
            rec = ParsedRecord(Dict{String,String}(), String[], String["cannot read file"])
            parsed[rel] = rec
        else
            rec = try
                parse_record(content)
            catch
                ParsedRecord(Dict{String,String}(), String[], String["cannot parse frontmatter"])
            end
            parsed[rel] = rec
        end
    end
    file_errors = Dict{String,Vector{String}}()
    for rel in rels
        errs = copy(parsed[rel].errors)
        front = parsed[rel].front
        body = parsed[rel].body
        for key in REQUIRED_RECORD_KEYS
            if !haskey(front, key) || is_empty_value(front[key])
                push!(errs, "missing or empty required frontmatter key `" * key * "`")
            end
        end
        status = haskey(front, "status") ? String(strip(front["status"])) : ""
        if !is_empty_value(status) && !(status in VALID_STATUSES)
            push!(errs, "invalid status `" * status * "` (expected one of: proposed, accepted, rejected, superseded, deprecated)")
        end
        rid = haskey(front, "id") ? String(strip(front["id"])) : ""
        m = match(FILENAME_ID_PATTERN, split(rel, "/")[end])
        if m === nothing || m.captures[1] === nothing
            push!(errs, "filename does not match `<PREFIX>-<NNNN>-<slug>.md`")
        elseif !is_empty_value(rid) && rid != String(m.captures[1])
            push!(errs, "`id` `" * rid * "` does not match filename prefix `" * String(m.captures[1]) * "`")
        end
        date = haskey(front, "date") ? String(strip(front["date"])) : ""
        if !is_empty_value(date) && match(DATE_PATTERN, date) === nothing
            push!(errs, "invalid date `" * date * "` (expected YYYY-MM-DD)")
        end
        for h in REQUIRED_HEADINGS
            if !has_heading(body, h)
                push!(errs, "body is missing heading `" * h * "`")
            end
        end
        file_errors[rel] = errs
    end
    owners = Dict{String,Vector{String}}()
    for rel in rels
        rid = haskey(parsed[rel].front, "id") ? String(strip(parsed[rel].front["id"])) : ""
        is_empty_value(rid) && continue
        push!(get!(owners, rid, String[]), rel)
    end
    for rel in rels
        rid = haskey(parsed[rel].front, "id") ? String(strip(parsed[rel].front["id"])) : ""
        is_empty_value(rid) && continue
        if length(owners[rid]) > 1
            others = join(filter(x -> x != rel, owners[rid]), ", ")
            push!(file_errors[rel], "duplicate `id` `" * rid * "` (also in " * others * ")")
        end
    end
    all_ids = Set(keys(owners))
    for rel in rels
        front = parsed[rel].front
        status = haskey(front, "status") ? String(strip(front["status"])) : ""
        sb = haskey(front, "superseded_by") ? String(strip(front["superseded_by"])) : ""
        sb_ids = record_ids_in(sb)
        if status == "superseded"
            if is_empty_value(sb) || isempty(sb_ids)
                push!(file_errors[rel], "status `superseded` requires a non-empty `superseded_by` naming a record id")
            else
                unknown = filter(id -> !(id in all_ids), sb_ids)
                if !isempty(unknown)
                    push!(file_errors[rel], "`superseded_by` `" * sb * "` names unknown record id(s) " * join(unknown, ", "))
                end
            end
        elseif !is_empty_value(sb)
            push!(file_errors[rel], "`superseded_by` is non-empty but status is `" * status * "` (expected `superseded`)")
        end
        supersedes = haskey(front, "supersedes") ? String(strip(front["supersedes"])) : ""
        unknown_sup = filter(id -> !(id in all_ids), record_ids_in(supersedes))
        if !isempty(unknown_sup)
            push!(file_errors[rel], "`supersedes` `" * supersedes * "` names unknown record id(s) " * join(unknown_sup, ", "))
        end
    end
    for rel in rels
        errs = file_errors[rel]
        if isempty(errs)
            report_ok!(st, rel * ": valid decision record")
        else
            for e in errs
                report_error!(st, rel * ": " * e)
            end
        end
    end
    return nothing
end

function check_coverage(st::CheckState, jl_files::Vector{String}, arch_text::String)
    for rel in jl_files
        needle = "`" * rel * "`"
        if occursin(needle, arch_text)
            report_ok!(st, rel * ": referenced in registry/code/architecture.md")
        else
            report_error!(st, rel * ": not referenced in registry/code/architecture.md")
        end
    end
    return nothing
end

function check_includes(st::CheckState, root::String, jl_files::Vector{String}, arch_text::String)
    mod_rel = "src/GenderNorms.jl"
    content = try_read_text(joinpath(root, mod_rel))
    if content === nothing
        report_error!(st, mod_rel * ": cannot read module file")
        return nothing
    end
    targets = String[]
    for m in eachmatch(INCLUDE_PATTERN, content)
        push!(targets, String(m.captures[1]))
    end
    counts = Dict{String,Int}()
    for t in targets
        norm = replace(joinpath("src", t), "\\" => "/")
        counts[norm] = get(counts, norm, 0) + 1
        if isfile(joinpath(root, norm))
            report_ok!(st, mod_rel * ": include \"" * t * "\" resolves to existing " * norm)
        else
            report_error!(st, mod_rel * ": include \"" * t * "\" target " * norm * " does not exist")
        end
    end
    dups = sort(collect(filter(p -> p.second > 1, counts)))
    if isempty(dups)
        report_ok!(st, mod_rel * ": no duplicate includes")
    else
        for (norm, n) in dups
            report_error!(st, mod_rel * ": " * norm * " is included $(n) times")
        end
    end
    included = Set(keys(counts))
    arch_lines = split(arch_text, "\n")
    for rel in jl_files
        if rel == mod_rel || rel == "src/main.jl"
            continue
        end
        if rel in included
            report_ok!(st, rel * ": included by " * mod_rel)
        else
            excluded = any(l -> occursin(EXCLUDED_MARKER, l) && occursin("`" * rel * "`", l), arch_lines)
            if excluded
                report_ok!(st, rel * ": documented as `" * EXCLUDED_MARKER * "` in registry/code/architecture.md")
            else
                report_error!(st, rel * ": neither included by " * mod_rel * " nor documented as `" * EXCLUDED_MARKER * "` in registry/code/architecture.md")
            end
        end
    end
    return nothing
end

function check_formatting(st::CheckState, root::String, jl_files::Vector{String}, md_files::Vector{String})
    rels = sort!(vcat(jl_files, md_files, skill_files(root), ["AGENTS.md"]))
    for rel in rels
        content = try_read_text(joinpath(root, rel))
        if content === nothing
            report_error!(st, rel * ": cannot read file")
            continue
        end
        # An intentional empty placeholder file (for example `src/main.jl`)
        # has no lines, so the trailing-newline rule does not apply.
        if isempty(content)
            report_ok!(st, rel * ": empty file, formatting rules exempt")
            continue
        end
        errs = String[]
        lines = text_lines(content)
        for (i, line) in enumerate(lines)
            if occursin("\t", line)
                push!(errs, "line $i contains a tab character")
            end
            if match(TRAILING_WS_PATTERN, line) !== nothing
                push!(errs, "line $i has trailing whitespace")
            end
        end
        if !isascii(content)
            bad = Int[]
            for (i, line) in enumerate(lines)
                if !isascii(line)
                    push!(bad, i)
                end
            end
            push!(errs, "contains non-ASCII characters on line(s) " * join(bad, ", "))
        end
        if !endswith(content, "\n")
            push!(errs, "does not end with a newline")
        elseif endswith(content, "\n\n")
            push!(errs, "ends with more than one newline")
        end
        if isempty(errs)
            report_ok!(st, rel * ": formatting clean")
        else
            for e in errs
                report_error!(st, rel * ": " * e)
            end
        end
    end
    return nothing
end

function check_skills(st::CheckState, root::String)
    for rel in skill_files(root)
        parent = split(rel, "/")[end-1]
        content = try_read_text(joinpath(root, rel))
        if content === nothing
            report_error!(st, rel * ": cannot read file")
            continue
        end
        rec = try
            parse_record(content)
        catch
            ParsedRecord(Dict{String,String}(), String[], String["cannot parse frontmatter"])
        end
        errs = copy(rec.errors)
        name = haskey(rec.front, "name") ? String(strip(rec.front["name"])) : ""
        desc = haskey(rec.front, "description") ? String(strip(rec.front["description"])) : ""
        if is_empty_value(name)
            push!(errs, "missing or empty frontmatter key `name`")
        elseif name != parent
            push!(errs, "`name` `" * name * "` does not match parent directory `" * parent * "`")
        end
        if is_empty_value(desc)
            push!(errs, "missing or empty frontmatter key `description`")
        end
        if isempty(errs)
            report_ok!(st, rel * ": valid skill frontmatter")
        else
            for e in errs
                report_error!(st, rel * ": " * e)
            end
        end
    end
    return nothing
end

# Collect top-level (column-zero) definitions from source files.
function collect_definitions(root::String, jl_files::Vector{String})::Vector{Tuple{String,String}}
    defs = Tuple{String,String}[]
    seen = Set{Tuple{String,String}}()
    for rel in jl_files
        content = try_read_text(joinpath(root, rel))
        content === nothing && continue
        for line in text_lines(content)
            for pat in DEF_PATTERNS
                m = match(pat, line)
                m === nothing && continue
                m.captures[1] === nothing && continue
                key = (rel, String(m.captures[1]))
                if !(key in seen)
                    push!(seen, key)
                    push!(defs, key)
                end
                break
            end
        end
    end
    sort!(defs)
    return defs
end

function check_unregistered_definitions(st::CheckState, root::String, jl_files::Vector{String}, md_files::Vector{String})
    regtext = ""
    for rel in md_files
        content = try_read_text(joinpath(root, rel))
        content === nothing && continue
        regtext *= content * "\n"
    end
    for (rel, name) in collect_definitions(root, jl_files)
        if !occursin(name, regtext)
            report_warn!(st, rel * ": top-level definition `" * name * "` is not mentioned in any registry/**/*.md")
        end
    end
    return nothing
end

"""
    main(argv) -> Int

Run every registry check against the repository root (the parent of this
script's directory) and print a `[OK]` / `[WARN]` / `[ERROR]` report with
a final summary line. Returns the process exit code: 0 iff there are no
errors (and, under `--strict`, no warnings); otherwise 1.
"""
function main(argv::Vector{String})::Int
    st = CheckState(false, false, 0, 0, 0)
    for a in argv
        if a == "--strict"
            st.strict = true
        elseif a == "--quiet"
            st.quiet = true
        else
            println("[ERROR] unknown argument `" * a * "`")
            println("usage: julia --project=. scripts/registry_check.jl [--strict] [--quiet]")
            return 1
        end
    end
    root = dirname(@__DIR__)
    try
        check_required_paths(st, root)
        check_decision_records(st, root)
        jl_files = list_files(root, "src", ".jl")
        md_files = list_files(root, "registry", ".md")
        arch_text = try_read_text(joinpath(root, "registry/code/architecture.md"))
        if arch_text === nothing
            report_error!(st, "registry/code/architecture.md: cannot read file")
            arch_text = ""
        else
            check_coverage(st, jl_files, arch_text)
        end
        check_includes(st, root, jl_files, arch_text)
        check_formatting(st, root, jl_files, md_files)
        check_skills(st, root)
        check_unregistered_definitions(st, root, jl_files, md_files)
    catch e
        report_error!(st, "internal validator failure: " * string(typeof(e)))
    end
    println("Summary: $(st.n_ok) OK, $(st.n_warn) warnings, $(st.n_err) errors")
    if st.n_err > 0
        return 1
    end
    if st.strict && st.n_warn > 0
        return 1
    end
    return 0
end

exit(main(ARGS))
