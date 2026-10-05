# Test suite of the GenderNorms dashboard (`dashboard/`).
#
# Covers the web-independent `DashboardRuntime` foundation: form-to-spec
# construction, the run record catalog, the worker protocol, live metric
# streaming, run manager supervision, and one end-to-end worker
# integration run against the real `bin/run_worker.jl`. Also covers the
# UI layer of `GenderNormsDashboard.DashboardUI`: per-plot line
# construction and metric metadata, plot management (switcher, plus
# button, per-plot selections), the presentation cursor and publish
# throttle, and a headless HTTP smoke of the Genie app. The helpers
# below are shared by the included suites.

using Dates
using GenderNormsDashboard
using JSON
using Sockets
using Test
using TOML
using UUIDs

import GenderNorms
import Genie
import Stipple

const DR = GenderNormsDashboard.DashboardRuntime
const UI = GenderNormsDashboard.DashboardUI
const GN = GenderNorms

"""
    tiny_form(; name, seed, ticks, agents_per_gender, kwargs...)

Build a minimal valid flat dashboard form for tests. Numeric values are
submitted as strings to exercise the server-side parsing. Extra
keyword arguments override form keys verbatim. Returns the form.
"""
function tiny_form(;
        name = "test-run",
        seed = 1,
        ticks = 3,
        agents_per_gender = 5,
        kwargs...,
    )
    form = DR.default_form()
    form["name"] = name
    form["seed"] = string(seed)
    form["ticks"] = string(ticks)
    form["agents_per_gender"] = string(agents_per_gender)
    for (key, value) in kwargs
        form[string(key)] = value
    end
    return form
end

"""
    tiny_spec(; kwargs...)

Build the validated `RunSpec` of `tiny_form`. Throws when the form is
invalid. Returns the spec.
"""
function tiny_spec(; kwargs...)
    result = DR.validate_form(tiny_form(; kwargs...))
    result isa GN.RunSpec || error("tiny form invalid: $(join(result, "; "))")
    return result
end

"""
    wait_for_job(manager, job_id; timeout = 120.0)

Poll `job_summaries` until the job reaches a terminal state. Returns
the terminal `JobSummary` or throws after `timeout` seconds.
"""
function wait_for_job(manager, job_id; timeout = 120.0)
    deadline = time() + timeout
    while time() < deadline
        for summary in DR.job_summaries(manager)
            summary.job_id == job_id || continue
            DR.is_terminal_state(summary.state) && return summary
        end
        sleep(0.02)
    end
    error("timed out waiting for job $job_id")
end

"""
    fixture_spec_dict(; name, seed, ticks, metrics, outputs)

Build the spec-dict echo used in record fixtures. Returns a plain
dictionary in the `GenderNorms.spec_to_dict` shape.
"""
function fixture_spec_dict(;
        name = "fixture-run",
        seed = 1,
        ticks = 2,
        metrics = ["working_time_gap"],
        outputs = [Dict{String, Any}("type" => "toml", "directory" => "runs")],
    )
    return Dict{String, Any}(
        "run" => Dict{String, Any}("name" => name, "seed" => seed),
        "model" => Dict{String, Any}(
            "name" => "gender_norms",
            "agents_per_gender" => 5,
            "std_dev" => 0.2,
            "initial_transfer" => 0.0,
            "initial_lambda" => 0.5,
            "network" => Dict{String, Any}(
                "type" => "watts_strogatz",
                "neighbors_per_side" => 1,
                "rewiring" => 0.1,
            ),
            "paid_time" => Dict{String, Any}("men" => 0.77, "women" => 0.36),
            "mean_wage" => Dict{String, Any}("men" => 1.0, "women" => 0.9),
            "mean_preference" => Dict{String, Any}("men" => 0.45, "women" => 0.48),
            "initial_conformism" => Dict{String, Any}("men" => 10.0, "women" => 10.0),
            "utility" => Dict{String, Any}(
                "type" => "ces",
                "w_self" => 1.0,
                "w_partner" => 1.0,
                "w_transfer" => 1.0,
                "beta" => 0.5,
            ),
        ),
        "runtime" => Dict{String, Any}("ticks" => ticks),
        "logging" => Dict{String, Any}(
            "metrics" => metrics,
            "outputs" => outputs,
        ),
    )
end

"""
    write_record_fixture(root, run_id; kwargs...)

Write one synthetic `run.toml` record for tests. Takes the record root
and the run UUID and the optional `[run]` values `name`, `model`,
`status`, `seed`, `started_at`, `finished_at`, `error`, `ticks`,
`metrics`, `ticks_executed`, `spec`, and `directory_name` (the
directory the record is written under, which defaults to `run_id`).
Returns the record file path.
"""
function write_record_fixture(
        root::AbstractString,
        run_id::AbstractString;
        name = "fixture-run",
        model = "gender_norms",
        status = "success",
        seed = 1,
        started_at = "2026-01-02T03:04:05",
        finished_at = "2026-01-02T03:04:06.5",
        ticks = [0, 1],
        metrics = Dict{String, Any}("working_time_gap" => [0.1, 0.2]),
        ticks_executed = length(ticks),
        spec = fixture_spec_dict(),
        error = nothing,
        directory_name = run_id,
    )
    directory = joinpath(root, directory_name)
    mkpath(directory)
    run_table = Dict{String, Any}(
        "id" => String(run_id),
        "name" => name,
        "model" => model,
        "status" => status,
        "seed" => seed,
        "started_at" => started_at,
        "finished_at" => finished_at,
        "ticks_executed" => ticks_executed,
    )
    error === nothing || (run_table["error"] = error)
    metric_table = Dict{String, Any}("tick" => ticks)
    for (metric, values) in metrics
        metric_table[metric] = values
    end
    record = Dict{String, Any}("run" => run_table, "metrics" => metric_table)
    spec === nothing || (record["spec"] = spec)
    path = joinpath(directory, "run.toml")
    open(path, "w") do io
        TOML.print(io, record)
    end
    return path
end

include("test_specs.jl")
include("test_protocol.jl")
include("test_records.jl")
include("test_live_logger.jl")
include("test_run_manager.jl")
include("test_worker_integration.jl")
include("test_plotting.jl")
include("test_plot_state.jl")
include("test_presentation.jl")
include("test_app.jl")
