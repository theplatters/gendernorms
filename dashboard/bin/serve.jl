# Dashboard server of GenderNorms runs.
#
# Starts a `DashboardRuntime.RunManager` with the repository's `runs/`
# record root and serves the Genie/Stipple dashboard on 127.0.0.1.
# Usage:
#   julia --project=dashboard dashboard/bin/serve.jl [--host=HOST] [--port=PORT] [--runs-root=DIR]
# Stop with Ctrl-C (or SIGTERM): shutdown cancels and reaps all jobs and
# stops the presentation tasks.

using GenderNormsDashboard

const UI = GenderNormsDashboard.DashboardUI
const DR = GenderNormsDashboard.DashboardRuntime

"""
    USAGE

Usage line printed on option errors and `--help`.
"""
const USAGE =
    "usage: julia --project=dashboard dashboard/bin/serve.jl [--host=HOST] [--port=PORT] [--runs-root=DIR]"

"""
    SHUTDOWN_WAKE

`uv_async` handle pointer woken by `shutdown_signal_handler`, or
`C_NULL` before the handlers are installed. Only the handle pointer is
read from the signal handler, which must stay allocation-free.
"""
const SHUTDOWN_WAKE = Ref{Ptr{Cvoid}}(C_NULL)

"""
    ServerOptions

Parsed command-line options of `serve.jl`. Field `host` is the bind
address (default `127.0.0.1`), field `port` the bind port (default
8000), and field `runs_root` the run record root (default `<repo>/runs`).
"""
struct ServerOptions
    host::String
    port::Int
    runs_root::String
end

"""
    parse_options(args::Vector{String})::ServerOptions

Parse the command-line options of `serve.jl`. Takes the argument list
and returns the `ServerOptions`; `--host=`, `--port=`, and `--runs-root=`
override the defaults. Throws `ArgumentError` on unknown options or an
unparseable port.
"""
function parse_options(args::Vector{String})::ServerOptions
    host = "127.0.0.1"
    port = 8000
    runs_root = normpath(joinpath(@__DIR__, "..", "..", "runs"))
    for arg in args
        if startswith(arg, "--host=")
            host = String(split(arg, '='; limit = 2)[2])
        elseif startswith(arg, "--port=")
            parsed = tryparse(Int, split(arg, '='; limit = 2)[2])
            parsed === nothing && throw(ArgumentError("cannot parse port from \"$arg\""))
            port = parsed
        elseif startswith(arg, "--runs-root=")
            runs_root = String(split(arg, '='; limit = 2)[2])
        else
            throw(ArgumentError("unknown option \"$arg\""))
        end
    end
    (1 <= port <= 65535) || throw(ArgumentError("port must be in 1..65535, got $port"))
    return ServerOptions(host, port, normpath(runs_root))
end

"""
    shutdown_signal_handler(sig::Cint)

Async-signal-safe SIGINT/SIGTERM handler of `serve.jl`. Takes the
signal number and wakes the `SHUTDOWN_WAKE` uv async handle so the main
task leaves `wait` and shuts down gracefully; no memory is allocated
here. Returns nothing.
"""
function shutdown_signal_handler(sig::Cint)
    wake = SHUTDOWN_WAKE[]
    wake == C_NULL || ccall(:uv_async_send, Cvoid, (Ptr{Cvoid},), wake)
    return nothing
end

"""
    install_shutdown_handlers!(wake::Base.AsyncCondition)

Install the graceful-shutdown signal handlers. Takes the async
condition the main task waits on, stores its uv handle in
`SHUTDOWN_WAKE`, and replaces the default SIGINT and SIGTERM handlers
with `shutdown_signal_handler`. Julia's own interrupt delivery is not
used here: with an IO worker pool it does not reliably reach the main
task. Returns nothing.
"""
function install_shutdown_handlers!(wake::Base.AsyncCondition)
    SHUTDOWN_WAKE[] = Base.unsafe_convert(Ptr{Cvoid}, wake)
    handler = @cfunction(shutdown_signal_handler, Cvoid, (Cint,))
    ccall(:signal, Ptr{Cvoid}, (Cint, Ptr{Cvoid}), 2, handler)   # SIGINT
    ccall(:signal, Ptr{Cvoid}, (Cint, Ptr{Cvoid}), 15, handler)  # SIGTERM
    return nothing
end

"""
    main(args::Vector{String} = ARGS)::Int

Run the dashboard server. Parses the options, installs the graceful
shutdown handlers, starts the run manager and the app, prints the URL
once, and blocks until SIGINT or SIGTERM. Shutdown runs exactly once
(from the signal path or the `finally`): the app stops (presentation
tasks detached, server down) and `shutdown!` cancels and reaps every
job. Returns 0 on a clean stop and 2 on option errors.
"""
function main(args::Vector{String} = ARGS)::Int
    options = try
        parse_options(args)
    catch err
        err isa ArgumentError || rethrow()
        println(stderr, err.msg)
        println(stderr, USAGE)
        return 2
    end
    manager = DR.RunManager(; runs_root = options.runs_root)
    wake = Base.AsyncCondition()
    install_shutdown_handlers!(wake)
    cleaned = Ref(false)
    cleanup = function ()
        cleaned[] && return nothing
        cleaned[] = true
        UI.stop_app!()
        DR.shutdown!(manager)
        println("GenderNorms dashboard stopped")
        flush(stdout)
        return nothing
    end
    try
        UI.start_app!(manager; host = options.host, port = options.port)
        println("GenderNorms dashboard listening at http://$(options.host):$(options.port)/")
        println("record root: $(manager.runs_root)")
        flush(stdout)
        wait(wake)
    finally
        cleanup()
    end
    return 0
end

exit(main())
