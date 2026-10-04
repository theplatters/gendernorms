# Child-process entry point of the dashboard worker.
#
# Runs one dashboard job: options come from `argv` (`--job-id`,
# `--staging-dir`, `--record`), the spec dict from stdin. Protocol
# messages are written to stdout, diagnostics to stderr. The runtime is
# included directly (not loaded as a package) so the worker never
# touches the Genie/Stipple UI stack.

include(joinpath(@__DIR__, "..", "src", "runtime.jl"))

import JSON

using .DashboardRuntime

exit(DashboardRuntime.worker_main(ARGS, stdin, stdout, stderr))
