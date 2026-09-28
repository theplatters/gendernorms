# Subprocess driver for the cross-thread-count determinism test in
# `test/test_threading.jl` (see `ADR-0014`): runs one full deterministic
# model run and prints only deterministic values at full Float64
# precision, so two invocations with different thread counts must print
# byte-identical output. The prints below are the driver's intended
# program output, not debug output. Not included in `test/runtests.jl`;
# run it directly with `julia --project=. test/threading_driver.jl`.

using Ark
using GenderNorms

const GN = GenderNorms

function main()
    raw = Dict{String,Any}(
        "run" => Dict{String,Any}("name" => "threading-driver", "seed" => 1),
        "model" => Dict{String,Any}(
            "name" => "gender_norms",
            "agents_per_gender" => 8,
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
    for tick in result.ticks
        println("tick ", repr(tick))
    end
    for name in sort(collect(keys(result.metrics)))
        for value in result.metrics[name]
            println("metric ", name, " ", repr(value))
        end
    end
    women = GN.entities_with(world, GN.Female)
    men = GN.entities_with(world, GN.Male)
    agents = vcat(women, men)
    totals = zeros(Float64, 6)
    for entity in agents
        time, transfer, param, percept = Ark.get_components(
            world, entity,
            (GN.WorkingTime, GN.TransferToWoman, GN.NormParameter, GN.PerceptionNormDivisionOfLabor),
        )
        totals[1] += time.current
        totals[2] += time.old
        totals[3] += transfer.current
        totals[4] += transfer.old
        totals[5] += param.amount
        totals[6] += percept.amount
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
        println("mean ", name, " ", repr(total / length(agents)))
    end
    return nothing
end

main()
