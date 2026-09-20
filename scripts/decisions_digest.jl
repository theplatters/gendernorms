# scripts/decisions_digest.jl
#
# Print a compact digest of all code (ADR) and model (MDR) decision
# records: id, status, date, title, and the first paragraph of the
# Decision section. Read-only: nothing is written, so no derived file has
# to be kept in sync (see ADR-0008).
#
# Usage:
#   julia scripts/decisions_digest.jl

const ROOT = dirname(@__DIR__)

const RECORD_DIRS = (
    ("ADR", "Code decisions (ADR)", "registry/code/decisions"),
    ("MDR", "Model decisions (MDR)", "registry/model/decisions"),
)

# Flat `key: value` frontmatter of a decision record.
function frontmatter(path::String)::Dict{String,String}
    values = Dict{String,String}()
    lines = readlines(path)
    (isempty(lines) || strip(lines[1]) != "---") && return values
    for line in lines[2:end]
        strip(line) == "---" && break
        parts = split(strip(line), ":", limit = 2)
        length(parts) == 2 || continue
        values[strip(parts[1])] = strip(parts[2])
    end
    return values
end

# First paragraph of the `## Decision` section, collapsed to one line.
function decision_paragraph(path::String)::String
    lines = readlines(path)
    start = findfirst(line -> startswith(line, "## Decision"), lines)
    start === nothing && return ""
    i = start + 1
    while i <= length(lines) && strip(lines[i]) == ""
        i += 1
    end
    paragraph = String[]
    while i <= length(lines)
        line = strip(lines[i])
        (isempty(line) || startswith(line, "## ")) && break
        push!(paragraph, line)
        i += 1
    end
    return join(paragraph, " ")
end

for (prefix, heading, dir) in RECORD_DIRS
    path = joinpath(ROOT, dir)
    isdir(path) || continue
    records = sort(filter(f -> startswith(f, prefix * "-") && endswith(f, ".md"), readdir(path)))
    isempty(records) && continue
    println("# " * heading)
    println()
    for f in records
        file = joinpath(path, f)
        front = frontmatter(file)
        id = get(front, "id", f)
        status = get(front, "status", "?")
        date = get(front, "date", "")
        title = get(front, "title", "")
        println(rpad(id, 9) * rpad(status, 11) * rpad(date, 12) * title)
        paragraph = decision_paragraph(file)
        isempty(paragraph) || println("    " * paragraph)
        println()
    end
end
