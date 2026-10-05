# Test double for `bin/run_worker.jl`, driven by `test_run_manager.jl`.
#
# Speaks the real worker protocol (via `DashboardRuntime`) but replaces
# the model run with scripted behavior so supervision, cancellation,
# record promotion, corrupt streams, and hung teardowns can be tested
# deterministically and quickly. The behavior is selected by the
# `run.name` of the spec dict on stdin; a consistent worker emits
# exactly `ticks_requested` rows (the real worker's contract):
#   "fake-ok"                      -> staged success record + finished(success)
#   "fake-model-failure"           -> staged failure record + finished(model_failure)
#   "fake-hang"                    -> started + rows, then sleeps until killed
#   "fake-crash"                   -> handshake only, then exits 1
#   "fake-infrastructure"          -> failed message
#   "fake-garbage"                 -> started + rows, then endless malformed output
#   "fake-finished-then-garbage"   -> success record + finished, then malformed output
#   "fake-wrong-job-id"            -> handshake with a foreign job id, then sleeps
#   "fake-wrong-run-id"            -> finished with a foreign run id, then sleeps
#   "fake-tick-mismatch"           -> finished tick count disagrees with the rows
#   "fake-empty-run-id"            -> started with an empty run id, then sleeps
#   "fake-invalid-run-id"          -> started with a non-UUID run id, then sleeps
#   "fake-duplicate-started"       -> two started messages, then sleeps
#   "fake-rows-before-started"     -> rows before the started message, then sleeps
#   "fake-missing-column"          -> rows missing a declared metric, then sleeps
#   "fake-decreasing-ticks"        -> rows with out-of-order ticks, then sleeps
#   "fake-finished-then-hang-closed"  -> finished, then hangs with stdout closed
#   "fake-finished-then-hang-writing" -> finished, then hangs while writing blanks
# Protocol messages go to stdout, diagnostics to stderr.

include(joinpath(@__DIR__, "..", "src", "runtime.jl"))

import Dates
import JSON
import TOML
import UUIDs

using .DashboardRuntime

const DR = DashboardRuntime

function write_staged_record(staging_dir, run_id, spec_dict, status, ticks, metrics)
    directory = joinpath(staging_dir, run_id)
    mkpath(directory)
    run_table = Dict{String, Any}(
        "id" => run_id,
        "name" => spec_dict["run"]["name"],
        "model" => spec_dict["model"]["name"],
        "status" => status,
        "seed" => spec_dict["run"]["seed"],
        "started_at" => Dates.format(Dates.now(), Dates.ISODateTimeFormat),
        "finished_at" => Dates.format(Dates.now(), Dates.ISODateTimeFormat),
        "ticks_executed" => length(ticks),
    )
    status == "failure" && (run_table["error"] = "ErrorException: scripted model failure")
    metric_table = Dict{String, Any}("tick" => copy(ticks))
    for (name, values) in metrics
        metric_table[name] = values
    end
    record = Dict{String, Any}(
        "run" => run_table,
        "spec" => spec_dict,
        "metrics" => metric_table,
    )
    open(joinpath(directory, "run.toml"), "w") do io
        TOML.print(io, record)
    end
    return nothing
end

function write_garbage_forever(out)
    while true
        println(out, "this line is not valid protocol json {{{")
        flush(out)
    end
    return nothing
end

function write_blanks_forever(out)
    while true
        println(out)
        flush(out)
        sleep(0.01)
    end
    return nothing
end

function main(args, input, out, err)
    options = DR.parse_worker_options(args)
    spec_dict = JSON.parse(read(input, String))
    run_id = string(UUIDs.uuid4())
    name = spec_dict["run"]["name"]
    model_name = spec_dict["model"]["name"]
    ticks_requested = spec_dict["runtime"]["ticks"]
    metrics = Dict{String, Vector{Float64}}(
        metric => Float64[] for metric in spec_dict["logging"]["metrics"]
    )
    ticks = collect(0:(ticks_requested - 1))
    for (metric, values) in metrics
        append!(values, [0.5 * tick for tick in ticks])
    end

    if name == "fake-wrong-job-id"
        DR.write_message!(out, DR.handshake_message(string(UUIDs.uuid4())))
        sleep(3600.0)
        return 0
    end
    DR.write_message!(out, DR.handshake_message(options["job_id"]))

    if name == "fake-crash"
        println(err, "fake worker crashing")
        return 1
    end
    if name == "fake-infrastructure"
        DR.write_message!(out, DR.failed_message("scripted setup failure", "setup"))
        return 1
    end
    if name == "fake-empty-run-id" || name == "fake-invalid-run-id"
        bad_id = name == "fake-empty-run-id" ? "" : "not-a-uuid"
        DR.write_message!(
            out,
            DR.started_message(
                bad_id,
                name,
                model_name,
                sort!(collect(keys(metrics))),
                Dates.format(Dates.now(), Dates.ISODateTimeFormat),
                ticks_requested,
            ),
        )
        sleep(3600.0)
        return 0
    end
    if name == "fake-rows-before-started"
        DR.write_message!(out, DR.rows_message(ticks, metrics))
        sleep(3600.0)
        return 0
    end

    DR.write_message!(
        out,
        DR.started_message(
            run_id,
            spec_dict["run"]["name"],
            model_name,
            sort!(collect(keys(metrics))),
            Dates.format(Dates.now(), Dates.ISODateTimeFormat),
            ticks_requested,
        ),
    )

    if name == "fake-hang"
        DR.write_message!(out, DR.rows_message(ticks, metrics))
        sleep(3600.0)
        return 0
    end
    if name == "fake-missing-column"
        kept = first(sort!(collect(keys(metrics))))
        DR.write_message!(out, DR.rows_message(ticks, Dict(kept => metrics[kept])))
        sleep(3600.0)
        return 0
    end
    if name == "fake-decreasing-ticks"
        bad_metrics = Dict(name => [0.5, 0.0] for name in keys(metrics))
        DR.write_message!(out, DR.rows_message([1, 0], bad_metrics))
        sleep(3600.0)
        return 0
    end
    if name == "fake-duplicate-started"
        DR.write_message!(out, DR.rows_message(ticks, metrics))
        DR.write_message!(
            out,
            DR.started_message(
                string(UUIDs.uuid4()),
                "renamed-by-duplicate-started",
                model_name,
                sort!(collect(keys(metrics))),
                Dates.format(Dates.now(), Dates.ISODateTimeFormat),
                ticks_requested,
            ),
        )
        sleep(3600.0)
        return 0
    end

    DR.write_message!(out, DR.rows_message(ticks, metrics))
    if name == "fake-garbage"
        write_garbage_forever(out)
    end
    if name == "fake-model-failure"
        options["record"] == "true" &&
            write_staged_record(options["staging_dir"], run_id, spec_dict, "failure", ticks, metrics)
        DR.write_message!(
            out,
            DR.finished_message(
                run_id,
                "model_failure",
                "ErrorException: scripted model failure",
                length(ticks),
                Dates.format(Dates.now(), Dates.ISODateTimeFormat),
            ),
        )
        return 2
    end
    options["record"] == "true" &&
        write_staged_record(options["staging_dir"], run_id, spec_dict, "success", ticks, metrics)
    if name == "fake-wrong-run-id"
        DR.write_message!(
            out,
            DR.finished_message(
                string(UUIDs.uuid4()),
                "success",
                "",
                length(ticks),
                Dates.format(Dates.now(), Dates.ISODateTimeFormat),
            ),
        )
        sleep(3600.0)
        return 0
    end
    if name == "fake-tick-mismatch"
        DR.write_message!(
            out,
            DR.finished_message(
                run_id,
                "success",
                "",
                length(ticks) - 1,
                Dates.format(Dates.now(), Dates.ISODateTimeFormat),
            ),
        )
        sleep(3600.0)
        return 0
    end
    DR.write_message!(
        out,
        DR.finished_message(
            run_id,
            "success",
            "",
            length(ticks),
            Dates.format(Dates.now(), Dates.ISODateTimeFormat),
        ),
    )
    if name == "fake-finished-then-garbage"
        write_garbage_forever(out)
    end
    if name == "fake-finished-then-hang-closed"
        close(out)
        sleep(3600.0)
    end
    if name == "fake-finished-then-hang-writing"
        write_blanks_forever(out)
    end
    return 0
end

exit(main(ARGS, stdin, stdout, stderr))
