# scripts/registry_digest.jl
#
# Print a compact digest of the registry: the task ledger
# (registry/tasks.md) plus all code (ADR) and model (MDR) decision
# records with id, status, date, title, and the first paragraph of their
# Decision section. Read-only: nothing is written, so no derived file has
# to be kept in sync (see ADR-0008 and ADR-0009).
#
# Usage:
#   julia scripts/registry_digest.jl

const ROOT = dirname(@__DIR__)

const TASKS_FILE = "registry/tasks.md"

const RECORD_DIRS = (
    ("ADR", "Code decisions (ADR)", "registry/code/decisions"),
    ("MDR", "Model decisions (MDR)", "registry/model/decisions"),
)

# Flat `key: value` frontmatter of a decision record.
function frontmatter(path::String)::Dict{String, String}
    values = Dict{String, String}()
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

# Task ledger rows as `(id, status, task)` triples.
function task_rows(path::String)
    rows = Tuple{String, String, String}[]
    for line in readlines(path)
        startswith(strip(line), "|") || continue
        cells = strip.(split(strip(line), "|"))
        length(cells) >= 4 || continue
        occursin(r"^`TASK-\d{4}`$", cells[2]) || continue
        push!(rows, (replace(cells[2], "`" => ""), cells[3], cells[4]))
    end
    return rows
end

tasks_path = joinpath(ROOT, TASKS_FILE)
if isfile(tasks_path)
    println("# Tasks (" * TASKS_FILE * ")")
    println()
    for (id, status, task) in task_rows(tasks_path)
        println(rpad(id, 11) * rpad(status, 12) * task)
    end
    println()
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
