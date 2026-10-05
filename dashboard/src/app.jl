# Genie application of the dashboard UI layer.
#
# `start_app!` binds the shared `DashboardRuntime.RunManager`, registers
# the routes (the single page, the stylesheet, and the `/healthz`
# status endpoint), and starts the Genie server; `stop_app!` detaches
# the per-page presentation tasks and stops the server. `page_ready` is
# the page-load hook that turns each page request into a dashboard
# session, and `dashboard_layout` carries the client-side
# resubscription hook that requests a full view-state resync on every
# channel (re)subscription. `bin/serve.jl` is the command-line entry
# point.

"""
    DASHBOARD_CSS

Filesystem path of the dashboard stylesheet, served at
`/dashboard.css` (see `register_routes!`).
"""
const DASHBOARD_CSS = normpath(joinpath(@__DIR__, "..", "public", "dashboard.css"))

"""
    DASHBOARD_VERSION

Dashboard version reported by `/healthz`, read from the dashboard
`Project.toml` so it has a single source.
"""
const DASHBOARD_VERSION = String(TOML.parsefile(joinpath(DR.DASHBOARD_ROOT, "Project.toml"))["version"])

"""
    APP_MANAGER

Run manager of the running dashboard app, set by `start_app!` and read
by the page-load hook and `/healthz`.
"""
const APP_MANAGER = Ref{Union{Nothing, DR.RunManager}}(nothing)

"""
    ROUTES_REGISTERED

Whether the Genie routes are registered in this process; `up`/`down`
cycles reuse them without re-registering.
"""
const ROUTES_REGISTERED = Ref(false)

"""
    health_status()::Dict{String,Any}

Build the `/healthz` response. Takes no arguments and returns the
dashboard name, `DASHBOARD_VERSION`, and the current queue depth and
job count of the run manager.
"""
function health_status()::Dict{String, Any}
    manager = APP_MANAGER[]
    summaries = manager === nothing ? DR.JobSummary[] : DR.job_summaries(manager)
    return Dict{String, Any}(
        "name" => "gendernorms-dashboard",
        "version" => DASHBOARD_VERSION,
        "queue_depth" => count(summary -> summary.state == DR.JOB_QUEUED, summaries),
        "jobs" => length(summaries),
    )
end

"""
    dashboard_theme()::Vector{String}

Stylesheet links of the dashboard head: the Stipple core theme, the
registered themes (`THEMES[]`, incl. the StippleUI Quasar stylesheet),
and the default Stipple color theme. Takes no arguments and returns the
link tags. This is `Stipple.Layout.theme` without its theme-dotfile
watcher, which would drop a `.theme` marker into the working directory.
"""
function dashboard_theme()::Vector{String}
    links = String[]
    sources = Function[
        Stipple.Layout.coretheme,
        Stipple.Theme.to_asset(:default),
        Stipple.Layout.THEMES[]...,
    ]
    for entry in sources
        value = entry()
        if value isa Union{Vector, Tuple}
            append!(links, String[String(item) for item in value])
        else
            push!(links, String(value))
        end
    end
    return unique!(links)
end

"""
    dashboard_layout()::String

Page layout of the dashboard: the Stipple app root and its asset
scripts, the `dashboard_theme` stylesheets and the
`/dashboard.css` stylesheet, the session token, the resubscription
hook, and no footer. The hook registers a Genie subscription handler
(see `handle_client_resync!`): Genie runs it on the first channel
subscription and again after every reconnect, so a browser that missed
the updates of a disconnect window asks the server for a full
view-state resync. Takes no arguments and returns the layout template.
"""
function dashboard_layout()::String
    theme_links = join(dashboard_theme(), "\n    ")
    return """
    <!DOCTYPE html>
    <html>
      <head>
        <meta charset="utf-8">
        <% Stipple.sesstoken() %>
        <title>GenderNorms dashboard</title>
        $theme_links
        $(stylesheet("/dashboard.css"))
        <style>[v-cloak] { display: none; }</style>
      </head>
      <body>
        <div class="gn-page">
          <% Stipple.page(model, partial = true, v__cloak = true,
              [Stipple.Genie.Renderer.Html.@yield],
              Stipple.@if(:isready),
              core_theme = true,
              include_themes = false,
              include_deps = true
            ) %>
        </div>
        <script>
          // Resubscription hook: Genie runs every subscription handler
          // on the first channel subscription and again on every
          // reconnect. Each run sends the client_resync event, so the
          // server pushes the full view state to a browser that missed
          // the updates of a disconnect window.
          document.addEventListener('DOMContentLoaded', function () {
            Genie.WebChannels.subscriptionHandlers.push(function () {
              var app = window.GENIEMODEL;
              if (app && typeof app.handle_event === 'function') {
                app.handle_event({}, 'client_resync');
              }
            });
          });
        </script>
      </body>
    </html>
    """
end

"""
    page_ready(model::DashboardModel)

Page-load hook of the dashboard page. Takes the freshly created page
model, attaches the run manager of the running app, fills the form with
`DashboardRuntime.default_form`, refreshes the record catalog, and
starts the per-page presentation task. Returns `nothing` so the page
renders normally.
"""
function page_ready(model::DashboardModel)
    manager = APP_MANAGER[]
    manager === nothing && return nothing
    apply_form!(model, DR.default_form())
    session = SessionState(model, manager)
    session.records = DR.refresh_records!(manager)
    model.manager[] = manager
    model.session[] = session
    register_session!(session)
    start_presentation!(session)
    return nothing
end

"""
    register_routes!()

Register the Genie routes of the dashboard: the page at `/` with the
`DashboardModel` and `page_ready` hook, the stylesheet at
`/dashboard.css`, and the JSON status at `/healthz`. Takes no arguments
and returns nothing; registration is idempotent per process and runs at
start time (never during precompilation).
"""
function register_routes!()
    ROUTES_REGISTERED[] && return nothing
    Genie.Router.route("/dashboard.css") do
        Genie.Renderer.WebRenderable(read(DASHBOARD_CSS, String), :css) |> Genie.Renderer.respond
    end
    Genie.Router.route("/healthz") do
        Genie.Renderer.Json.json(health_status())
    end
    @page(
        "/",
        ui;
        model = DashboardModel,
        layout = dashboard_layout(),
        post = page_ready
    )
    ROUTES_REGISTERED[] = true
    return nothing
end

"""
    start_app!(manager::DashboardRuntime.RunManager; host = "127.0.0.1", port = 8000)

Start the dashboard app. Takes the run manager and the bind host and
port, stores the manager for the page sessions and `/healthz`,
registers the routes, and starts the Genie server asynchronously
without opening a browser. Returns nothing.
"""
function start_app!(
        manager::DR.RunManager;
        host::AbstractString = "127.0.0.1",
        port::Integer = 8000,
    )
    APP_MANAGER[] = manager
    register_routes!()
    Genie.up(Int(port), String(host); async = true, open_browser = false)
    return nothing
end

"""
    stop_app!()

Stop the dashboard app. Takes no arguments, detaches every page session
(`stop_sessions!`, so no presentation task outlives the app), and stops
the Genie server. Queued and running jobs are untouched; `bin/serve.jl`
shuts the run manager down separately. Returns nothing.
"""
function stop_app!()
    stop_sessions!()
    Genie.down()
    return nothing
end
