# Interactive dashboard for GenderNorms runs.
#
# `DashboardRuntime` (see `src/runtime.jl`) is the web-independent
# runtime layer: job/run state types, form-to-spec construction, run
# record catalog, worker protocol, live metric streaming, and the run
# manager. It depends only on `GenderNorms` and lightweight non-web
# packages so worker processes load it cheaply.
#
# The UI layer (module `DashboardUI`, see `src/plotting.jl`,
# `src/presentation.jl`, `src/reactive_model.jl`, `src/ui.jl`, and
# `src/app.jl`) builds on top of `DashboardRuntime` and must not be
# imported by it. `bin/run_worker.jl` includes `src/runtime.jl`
# directly instead of loading this package, so the worker never touches
# the web stack.

module GenderNormsDashboard

include("runtime.jl")

"""
    DashboardUI

Genie/Stipple/StipplePlotly UI layer of the dashboard (see `ADR-0025`):
metric metadata and per-plot line construction (`build_plot`,
`METRIC_META`), the presentation cursor and publish throttle
(`PresentationCursor`, `PublishGate`), the per-page reactive model and
its handlers (`DashboardModel`), the single-page view (`ui`), and the
Genie application (`start_app!`, `stop_app!`).
"""
module DashboardUI

    import Dates
    import GenderNorms
    import TOML
    import UUIDs

    using Genie
    using PlotlyBase
    using Stipple
    using Stipple.ReactiveTools
    using StipplePlotly
    using StippleUI

    # Explicit tag imports resolve the exported-name ambiguities between
    # Genie, Stipple, and PlotlyBase (`table` in particular).
    import Genie.Renderer.Html:
        button, h1, h2, h4, input, li, p, span, table, tbody, td, th, thead, tr, ul

    using ..GenderNormsDashboard: DashboardRuntime

    const DR = DashboardRuntime
    const GN = GenderNorms

    function __init__()
        # The model is not serializable (it carries the run manager and the
        # presentation task in private fields) and every page load builds a
        # fresh per-page session, so Stipple's session model storage stays
        # off. Channels are then also isolated per window.
        Stipple.enable_model_storage(false)
        return nothing
    end

    include("plotting.jl")
    include("presentation.jl")
    include("reactive_model.jl")
    include("ui.jl")
    include("app.jl")

end

end
