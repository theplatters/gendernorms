# scripts/format.jl
#
# Format the Julia sources of this repository with the Runic.jl
# formatter, or check formatting without modifying any file.
#
# Runic lives in its own Julia environment, @runic
# (~/.julia/environments/runic), so that this repository's Project.toml
# and Manifest.toml stay free of tooling dependencies. This script
# activates that environment and installs Runic there automatically on
# first use. See ADR-0027.
#
# Usage:
#   julia scripts/format.jl [<path>...]
#   julia scripts/format.jl --check [--diff] [<path>...]
#
# Paths default to the repository root; directories are searched
# recursively for *.jl files, skipping .git directories and symbolic
# links, so that a link can never make this script read or write a file
# outside the repository. Symlinks found by directory scans are skipped
# and reported in the summary. Paths named explicitly on the command
# line are used as given, symlinks included: naming a path is an
# explicit user action. In the default mode every file is formatted in
# place. With --check nothing is modified; every file that Runic would
# reformat is reported instead and the exit code is 1 if there is any
# such file. --diff additionally prints the diffs and implies --check.

import Pkg

const ROOT = dirname(@__DIR__)
const RUNIC_ENV = homedir() * "/.julia/environments/runic"

Pkg.activate(RUNIC_ENV; io = devnull)
try
    @eval import Runic
catch
    Pkg.add("Runic")
    @eval import Runic
end

function print_help()
    println(
        """
        usage: julia scripts/format.jl [--check] [--diff] [<path>...]

        Format all Julia files under the given paths (default: the
        repository root) in place with Runic. With --check nothing is
        modified: files that would be reformatted are reported and the
        exit code is 1 if there is any. --diff prints the diffs too and
        implies --check.

        Directory scans skip symbolic links (and report them in the
        summary) so that files outside the repository are never written
        through a link. Paths named explicitly on the command line are
        used as given, symlinks included.
        """
    )
    return
end

# Recursively collect *.jl files under root, skipping .git directories
# and symbolic links, mirroring the file set Runic accepts for a
# directory input. Skipped symlinks are returned separately so the
# summary can report them; following one could write to a file outside
# the repository.
function julia_files(root::AbstractString)
    files = String[]
    links = String[]
    for (dir, dirs, names) in walkdir(root; onerror = _ -> nothing)
        filter!(d -> d != ".git", dirs)
        for name in names
            endswith(name, ".jl") || continue
            path = joinpath(dir, name)
            if islink(path)
                push!(links, path)
            else
                push!(files, path)
            end
        end
    end
    return sort!(files), links
end

# Collect the files to process from the given paths. Directories are
# scanned automatically (symlinks skipped and counted); a path named
# explicitly is used as given, even when it is a symlink.
function collect_files(paths)
    files = String[]
    nlinks = 0
    for path in paths
        if isdir(path)
            found, links = julia_files(path)
            append!(files, found)
            nlinks += length(links)
        elseif isfile(path) || islink(path)
            push!(files, String(path))
        else
            println(stderr, "format.jl: no such file or directory: ", path)
            exit(2)
        end
    end
    return sort!(unique!(files)), nlinks
end

# Show paths inside the repository relative to its root; anything else
# (for example temporary files passed by the pre-commit hook) unchanged.
function display_path(path::AbstractString)
    root = abspath(ROOT) * "/"
    abs = abspath(path)
    return startswith(abs, root) ? relpath(abs, ROOT) : String(path)
end

function main(args)
    check = false
    diff = false
    paths = String[]
    for arg in args
        if arg == "--check"
            check = true
        elseif arg == "--diff"
            diff = true
        elseif arg == "--help" || arg == "-h"
            print_help()
            return 0
        elseif startswith(arg, "-")
            println(stderr, "format.jl: unknown option: ", arg)
            return 2
        else
            push!(paths, String(arg))
        end
    end
    check = check || diff
    isempty(paths) && push!(paths, ROOT)
    files, nlinks = collect_files(paths)
    note = nlinks == 0 ? "" : string("; skipped ", nlinks, " symlink(s)")
    if isempty(files)
        println("format.jl: no Julia files found", note)
        return 0
    end
    if check
        changed = String[]
        for file in files
            argv = String["--check"]
            diff && push!(argv, "--diff")
            push!(argv, file)
            Runic.main(argv) == 0 || push!(changed, file)
        end
        for file in changed
            println("would reformat ", display_path(file))
        end
        if isempty(changed)
            println("format.jl: all ", length(files), " Julia file(s) are formatted", note)
            return 0
        end
        println(
            "format.jl: ", length(changed), " of ", length(files),
            " Julia file(s) would be reformatted", note
        )
        return 1
    else
        rc = Runic.main(vcat(String["--inplace"], files))
        println("format.jl: formatted ", length(files), " Julia file(s) in place", note)
        return Int(rc)
    end
end

exit(main(ARGS))
