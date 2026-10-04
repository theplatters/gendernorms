# Web-independent runtime layer of the dashboard.
#
# Module `DashboardRuntime` owns the job/run state types, form-to-spec
# construction, the run record catalog, the worker protocol, live metric
# streaming, the worker entry logic, and the run manager. It depends
# only on `GenderNorms`, `JSON`, and stdlibs (Dates, TOML, UUIDs) so a
# worker process can load it cheaply; the Genie/Stipple UI layer stays
# outside this module. `bin/run_worker.jl` includes this file directly,
# so both the package and the standalone worker share one definition.

module DashboardRuntime

import Dates
import GenderNorms
import JSON
import TOML
import UUIDs

const GN = GenderNorms

include("runtime/types.jl")
include("runtime/protocol.jl")
include("runtime/specs.jl")
include("runtime/records.jl")
include("runtime/live_logger.jl")
include("runtime/worker.jl")
include("runtime/run_manager.jl")

end
