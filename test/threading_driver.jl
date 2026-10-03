# Subprocess driver for the determinism tests in
# `test/test_threading.jl` (see `ADR-0014`, `ADR-0023`, and
# `ADR-0024`): runs one
# full deterministic model run, the same-seed repeat of that run, and
# three identically seeded bargaining segments driven through
# `calculate_norm_perception!` and `set_theta!` with `chunk = 3` and
# forced `schedule`
# `:serial`, `:parallel`, and `:auto`, and prints only deterministic
# values at full Float64 precision. Two invocations with different
# thread counts must print byte-identical output; within one invocation
# the repeat block must be byte-identical to the run block and the three
# forced-schedule segment blocks must be byte-identical to each other.
# The run and repeat blocks print one `agent` final-state row per agent
# in the same row format as the segment rows, so the byte-identity
# covers individual agents and not only aggregate means. The prints
# below are the driver's intended program output, not debug output. Not
# included in `test/runtests.jl`; run it directly with
# `julia --project=. test/threading_driver.jl`.

using Ark
using GenderNorms

const GN = GenderNorms

# Deterministic per-agent final state row shared by the run blocks and
# the forced-schedule segments: the full-precision Float64 state tuple
# printed for every agent.
function agent_state_row(world, entity)
    time, transfer, param, percept = Ark.get_components(
        world,
        entity,
        (GN.WorkingTime, GN.TransferToWoman, GN.NormParameter, GN.PerceptionNormDivisionOfLabor),
    )
    return (time.current, time.old, transfer.current, transfer.old, param.amount, percept.amount)
end

function print_run_block(prefix::String, result, world)
    for tick in result.ticks
        println(prefix, "tick ", repr(tick))
    end
    for name in sort(collect(keys(result.metrics)))
        for value in result.metrics[name]
            println(prefix, "metric ", name, " ", repr(value))
        end
    end
    women = GN.entities_with(world, GN.Female)
    men = GN.entities_with(world, GN.Male)
    agents = vcat(women, men)
    rows = map(entity -> agent_state_row(world, entity), agents)
    totals = zeros(Float64, 6)
    for row in rows
        for (index, value) in enumerate(row)
            totals[index] += value
        end
    end
    names = (
        "working_time_current",
        "working_time_old",
        "transfer_current",
        "transfer_old",
        "norm_parameter",
        "norm_percept",
    )
    for (name, total) in zip(names, totals)
        println(prefix, "mean ", name, " ", repr(total / length(agents)))
    end
    for row in rows
        println(prefix, "agent ", repr(row))
    end
    return nothing
end

function print_segment_block(label::String, world)
    women = GN.entities_with(world, GN.Female)
    men = GN.entities_with(world, GN.Male)
    for entity in vcat(women, men)
        println("segment ", label, " ", repr(agent_state_row(world, entity)))
    end
    return nothing
end

function main()
    raw = Dict{String,Any}(
        "run" => Dict{String,Any}("name" => "threading-driver", "seed" => 1),
        "model" => Dict{String,Any}(
            "name" => "gender_norms",
            "agents_per_gender" => 64,
            "network" => Dict{String,Any}(
                "type" => "watts_strogatz", "neighbors_per_side" => 2, "rewiring" => 0.1
            ),
        ),
        "runtime" => Dict{String,Any}("ticks" => 3),
    )
    spec = GN.parse_spec(raw)
    world = GN.create_world(spec)
    result = GN.run(world)
    GN.is_success(result) || error("run failed: $(result.error)")
    print_run_block("", result, world)
    # Same-seed repeat of the full run: `create_world` seeds from the
    # spec, so the repeat must reproduce the run block byte for byte.
    repeat_world = GN.create_world(spec)
    repeat_result = GN.run(repeat_world)
    GN.is_success(repeat_result) || error("repeat run failed: $(repeat_result.error)")
    print_run_block("repeat ", repeat_result, repeat_world)
    # Forced-schedule bargaining segments (see `ADR-0023` and
    # `ADR-0024`): identical worlds driven through three ticks of
    # `calculate_norm_perception!` plus `set_theta!`, both with
    # `chunk = 3` (22 chunks for 64 agents/households, an incomplete
    # final chunk included) and `schedule` forced to `:serial`,
    # `:parallel`, and `:auto`; the printed rows must be byte-identical
    # across labels and across thread counts.
    config = spec.model_config.utility
    for (label, schedule) in (("serial", :serial), ("parallel", :parallel), ("auto", :auto))
        segment_world = GN.create_world(spec)
        for _ in 1:3
            GN.calculate_norm_perception!(segment_world, config; chunk=3, schedule=schedule)
            GN.set_theta!(segment_world, config; chunk=3, schedule=schedule)
        end
        print_segment_block(label, segment_world)
    end
    return nothing
end

main()
