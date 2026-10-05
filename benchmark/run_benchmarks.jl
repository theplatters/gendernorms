# Benchmark driver comparing the NetLogo reference model
# (`gender_model_shocks_preferences.nlogox`) against the Julia port on a
# matched configuration matrix (see `MDR-0011` for the measurement
# methodology and `ADR-0013` for the harness structure).
#
# The driver is the single source of truth for the config matrix and the
# NetLogo-to-Julia configuration mapping. It generates BehaviorSpace
# experiment XML, runs the NetLogo model headless, times the Julia
# `create_world` + `step_model!` pipeline (see `ADR-0012`) on identical
# configurations, and writes raw per-run CSVs plus merged summaries
# under `benchmark/results/`.
#
# NetLogo timing (see `MDR-0011`): one BehaviorSpace experiment per
# config with `runMetricsEveryStep=true`, `timeLimit=<ticks>`, and the
# metrics `timer` and `run-time`. Each run emits one row per step
# including `[step] == 0`, and `timer` (seconds since `reset-timer` at
# the start of `setup`) decomposes the run from one invocation:
# `setup_s = timer[0]`, `tick_s[k] = timer[k] - timer[k-1]`,
# `total_s = timer[T]`. Julia timing: `create_world` and each
# `step_model!` call timed separately with `time_ns()`.
#
# Usage:
#   julia --project=. benchmark/run_benchmarks.jl [--quick] [--only netlogo|julia]
#                                                 [--force] [--analyse]
#                                                 [--cold-start] [--help]
#
# The prints below are the driver's intended program output, not debug
# output (same policy as `examples/run_example.jl`).

using GenderNorms
using Dates
using Printf
using Statistics
using TOML

const GN = GenderNorms

const REPO_ROOT = dirname(@__DIR__)
const RESULTS_DIR = joinpath(@__DIR__, "results")
const MODEL_FILE = joinpath(REPO_ROOT, "gender_model_shocks_preferences.nlogox")
const NETLOGO_HOME = get(ENV, "NETLOGO_HOME", "/opt/netlogo")

# Seeds: NetLogo uses the `fixed-rs` / `random-seed-fixed` path of ODD
# Initialization item 2, Julia uses the `[run] seed` of the run pipeline.
# The RNG streams differ, so trajectories are not bit-identical (see
# `MDR-0011`).
const NETLOGO_SEED = 1
const JULIA_SEED = 42

# Repetition policy (see `MDR-0011`): NetLogo runs `NETLOGO_REPETITIONS`
# runs per experiment and drops run 1 (JIT warmup, via `[run number] ==
# 1`), Julia runs `JULIA_WARMUPS` warmups (dropped) plus
# `JULIA_MEASURED` timed repetitions. Quick mode uses fewer repetitions
# for smoke testing.
const NETLOGO_REPETITIONS = 9
const NETLOGO_REPETITIONS_QUICK = 3
const JULIA_MEASURED = 8
const JULIA_MEASURED_QUICK = 2
const JULIA_WARMUPS = 2

# NetLogo `timer` resolution in seconds. `run-time` at the final step
# must match `timer` at the final step within this tolerance; a config
# disagreeing by more is flagged during analysis (see `MDR-0011`).
const TIMER_RESOLUTION_S = 0.002

# Cold-start probe (`--cold-start`, see `MDR-0011`): the base config is
# measured from `COLD_START_PROCESSES` fresh Julia processes; the
# NetLogo side is derived per invocation during analysis.
const COLD_START_CONFIG_ID = "pop_n100_t20"
const COLD_START_PROCESSES = 3

# Watts-Strogatz ring degree. NetLogo `nw:generate-watts-strogatz`
# (called from `setup`) takes `watts-strogatz-neighbors` as the
# neighborhood size on each side; Julia `WattsStrogatz.neighbors_per_side`
# maps to the `Graphs.watts_strogatz` ring degree k = 2 *
# `neighbors_per_side` in `src/resources/social_network.jl`. Both sides
# therefore give each node `v` neighbors per side (degree `2v`) and the
# equivalence is 1:1; see `MDR-0011` for the measurements. The value 2
# matches the shipped BehaviorSpace experiments of the model.
const WATTS_NEIGHBORS = 2

"""
    BenchConfig

One benchmark configuration (a row of the config matrix). Field `id` is
the config identifier used in all result file names, `group` is the
sweep group (`"pop"`, `"net"`, `"util"`, or `"conf"`), and the fields
`agents_per_gender`, `ticks`, `network`, `utility`, and `conformism`
carry the swept knobs in Julia run-specification spelling (`network` and
`utility` use the `src/runtime/gender_norms_model.jl` type names).
"""
struct BenchConfig
    id::String
    group::String
    agents_per_gender::Int
    ticks::Int
    network::String
    utility::String
    conformism::Float64
end

"""
    RepTiming

Timing of one Julia repetition. Field `setup_s` is the wall time of
`create_world`, `steps_s` the wall time of the `step_model!` loop,
`total_s` their sum, and `tick_s` the per-call seconds of the
`step_model!` calls (tick 0-based like `step_model!`, one entry per
tick). See `MDR-0011`.
"""
struct RepTiming
    setup_s::Float64
    steps_s::Float64
    total_s::Float64
    tick_s::Vector{Float64}
end

"""
    NetLogoRun

One repetition of a NetLogo config parsed from its per-step
BehaviorSpace series (see `MDR-0011`). Field `rep` is the `[run number]`
(run 1 is dropped as JIT warmup by the callers), `setup_s` is
`timer[0]`, `tick_s[k]` is `timer[k] - timer[k-1]` for `k = 1..T`,
`total_s` is `timer[T]`, and `drift_s` is `run-time` minus `timer` at
the final step (a consistency check; zero within the timer resolution
for healthy data).
"""
struct NetLogoRun
    rep::Int
    setup_s::Float64
    tick_s::Vector{Float64}
    total_s::Float64
    drift_s::Float64
end

"""
    Options

Parsed command line options. Field `quick` selects the smoke subset,
`only` is `"both"`, `"netlogo"`, or `"julia"`, `force` reruns configs
whose raw output is complete, `analyse` rebuilds the merged files from
the raw outputs without running anything, and `cold_start` measures
fresh-process startup for the base config.
"""
struct Options
    quick::Bool
    only::String
    force::Bool
    analyse::Bool
    cold_start::Bool
end

"""
    config_matrix()::Vector{BenchConfig}

Build the full benchmark config matrix (39 configs, single source of
truth for the sweep; see `MDR-0011`). Base configuration: 100 agents
per gender, 20 ticks, `watts_strogatz` network, `ces` utility,
conformism 10 for both genders. Groups: `pop` sweeps
`agents_per_gender` x `ticks` (24 configs), `net` sweeps the network
type (7), `util` sweeps the utility type (4), `conf` sweeps the
symmetric initial conformism (4). Returns the matrix in group order.
"""
function config_matrix()::Vector{BenchConfig}
    configs = BenchConfig[]
    for n in (25, 50, 100, 200, 400, 800), t in (1, 5, 20, 50)
        push!(configs, BenchConfig("pop_n$(n)_t$(t)", "pop", n, t, "watts_strogatz", "ces", 10.0))
    end
    for net in ("none", "watts_strogatz", "random", "preferential_attachment", "similarity", "homophily", "homogeneous_mixing")
        push!(configs, BenchConfig("net_$net", "net", 100, 20, net, "ces", 10.0))
    end
    for util in ("additive", "ces", "multiplicative", "multiplicative_weighted")
        push!(configs, BenchConfig("util_$util", "util", 100, 20, "watts_strogatz", util, 10.0))
    end
    for c in (0.0, 1.0, 10.0, 50.0)
        push!(configs, BenchConfig("conf_$(fmt_num(c))", "conf", 100, 20, "watts_strogatz", "ces", c))
    end
    return configs
end

"""
    selected_configs(quick::Bool)::Vector{BenchConfig}

Select the configs to run. Takes the quick-mode flag and returns the
whole `config_matrix` normally, or the smoke subset (`pop_n50_t5` and
`util_ces`) in quick mode; both ids are members of the full matrix, so
quick results are redone automatically by a later full run (the raw
file completeness check sees the different repetition counts).
"""
function selected_configs(quick::Bool)::Vector{BenchConfig}
    quick || return config_matrix()
    wanted = ("pop_n50_t5", "util_ces")
    return [c for c in config_matrix() if c.id in wanted]
end

"""
    fmt_num(x::Real)::String

Format a scalar for CSV output without a trailing `.0` on integers.
Takes the number and returns e.g. `"10"` or `"0.5"`.
"""
function fmt_num(x::Real)::String
    return isinteger(x) ? string(Int(x)) : string(x)
end

"""
    fmt_seconds(x::Float64)::String

Format a duration in seconds for CSV output with microsecond
resolution. Returns the `%.6f` fixed-point string.
"""
function fmt_seconds(x::Float64)::String
    return @sprintf("%.6f", x)
end

"""
    netlogo_network_name(network::String)::String

Map one Julia `network.type` value to its NetLogo `network-structure`
chooser string (see `MDR-0011`). Takes the Julia name and returns the
NetLogo name (`"preference-private"` for `similarity`, `"homogenous
mixing"` for `homogeneous_mixing`, the literal choice strings
otherwise).
"""
function netlogo_network_name(network::String)::String
    names = Dict(
        "none" => "none",
        "watts_strogatz" => "watts-strogatz",
        "random" => "random-network",
        "preferential_attachment" => "preferential-attachment",
        "similarity" => "preference-private",
        "homophily" => "homophily",
        "homogeneous_mixing" => "homogenous mixing",
    )
    return names[network]
end

"""
    netlogo_utility_name(utility::String)::String

Map one Julia `utility.type` value to its NetLogo `utility-function`
chooser string (see `MDR-0011`). Takes the Julia name and returns the
NetLogo name (`"CES"` for `ces`, `"multiplicative including weights"`
for `multiplicative_weighted`, the literal choice strings otherwise).
"""
function netlogo_utility_name(utility::String)::String
    names = Dict(
        "additive" => "additive",
        "ces" => "CES",
        "multiplicative" => "multiplicative",
        "multiplicative_weighted" => "multiplicative including weights",
    )
    return names[utility]
end

"""
    netlogo_string(value::String)::String

Encode one string-valued NetLogo global for a BehaviorSpace
`enumeratedValueSet` value attribute: the string is wrapped in NetLogo
quotes, XML-escaped as `&quot;...&quot;`.
"""
function netlogo_string(value::String)::String
    return "&quot;" * value * "&quot;"
end

"""
    netlogo_constants(config::BenchConfig)::Vector{Pair{String,String}}

Build the complete BehaviorSpace constant list for one config (see
`MDR-0011`). Every global the model reads is set explicitly, so no
widget default is relied upon (`convergence_epsilon`'s widget default
even lies outside its own slider range). The constant order follows the
mapping table in `MDR-0011`. Returns `(variable => value)` pairs with
the values already XML-encoded.
"""
function netlogo_constants(config::BenchConfig)::Vector{Pair{String, String}}
    return [
        "number-agents-each-type" => fmt_num(config.agents_per_gender),
        "network-structure" => netlogo_string(netlogo_network_name(config.network)),
        "random-network-prob" => "0.01",
        "watts-strogatz-neighbors" => fmt_num(WATTS_NEIGHBORS),
        "watts-strogatz-rewiring" => "0.1",
        "preferential-attachment-min-degree" => "2",
        "utility-function" => netlogo_string(netlogo_utility_name(config.utility)),
        "CES_beta" => "0.5",
        "weight-working-time-self" => "1",
        "weight-working-time-partner" => "1",
        "weight-transfer" => "1",
        "conformism-male" => fmt_num(config.conformism),
        "conformism-female" => fmt_num(config.conformism),
        "wage-male" => "1.0",
        "wage-female" => "0.9",
        "norm-paid-time-male" => "77",
        "norm-paid-time-female" => "36",
        "preference-private-mean-male" => "0.45",
        "preference-private-mean-female" => "0.48",
        "std-dev-values" => "0.2",
        "initial-transfer" => "0.0",
        "lambda" => "0.002",
        "convergence_epsilon" => "0.001",
        "fixed-rs" => "true",
        "random-seed-fixed" => fmt_num(NETLOGO_SEED),
        "shock" => netlogo_string("no"),
        "perc-affected-male" => "0",
        "perc-affected-female" => "0",
        "shock-start" => "60",
        "wage-growth-rate" => "0",
        "preference-private-shock-male" => "0",
        "preference-private-shock-female" => "0",
        "shock-depreciation" => "0.005",
        "import-csv" => "false",
        "specific-couple" => "false",
        "output-locations" => "false",
        "wage-female-in-question" => "2.0",
        "wage-male-in-question" => "2.0",
        "preference-private-female-in-question" => "0.5",
        "preference-private-male-in-question" => "0.5",
        "conformism-male-in-question" => "1.0",
        "conformism-female-in-question" => "1.0",
    ]
end

"""
    experiments_xml(config::BenchConfig, repetitions::Int)::String

Build the BehaviorSpace setup file for one config. Takes the config and
the repetition count and returns the XML document with one experiment
named `<config.id>`: `runMetricsEveryStep="true"` and
`timeLimit=<ticks>`, so each repetition emits one row per step
including `[step] == 0`, with the metrics `timer` and `run-time` (both
trivial global reads; the `[step]` column already gives the tick count).
The per-step `timer` series (seconds since `reset-timer` at the start of
`setup`) decomposes each run into setup, per-tick, and total times
within a single invocation (see `MDR-0011`).
"""
function experiments_xml(config::BenchConfig, repetitions::Int)::String
    constants = IOBuffer()
    for (name, value) in netlogo_constants(config)
        println(constants, "      <enumeratedValueSet variable=\"$name\">")
        println(constants, "        <value value=\"$value\"></value>")
        println(constants, "      </enumeratedValueSet>")
    end
    constants_block = String(take!(constants))
    return string(
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n",
        "<experiments>\n",
        "  <experiment name=\"$(config.id)\" repetitions=\"$repetitions\" " *
            "sequentialRunOrder=\"true\" runMetricsEveryStep=\"true\" " *
            "timeLimit=\"$(config.ticks)\">\n",
        "    <setup>setup</setup>\n",
        "    <go>go</go>\n",
        "    <metrics>\n",
        "      <metric>timer</metric>\n",
        "      <metric>run-time</metric>\n",
        "    </metrics>\n",
        "    <constants>\n",
        constants_block,
        "    </constants>\n",
        "  </experiment>\n",
        "</experiments>\n",
    )
end

"""
    julia_network_table(config::BenchConfig)::Dict{String,Any}

Build the `[model.network]` table for one config (the shape accepted by
`GenderNorms.parse_model_config`, see `ADR-0012`). Takes the config and
returns the per-type dictionary: `random` carries `p = 0.01`,
`watts_strogatz` carries `neighbors_per_side = 2` (the
value equivalent to NetLogo `watts-strogatz-neighbors`, see `MDR-0011`)
and `rewiring = 0.1`, `preferential_attachment`, `similarity`, and
`homophily` carry `m = 2` (NetLogo `preferential-attachment-min-degree`),
and `similarity` carries `trait = "preference_private"`.
"""
function julia_network_table(config::BenchConfig)::Dict{String, Any}
    net = config.network
    if net == "random"
        return Dict{String, Any}("type" => "random", "p" => 0.01)
    elseif net == "watts_strogatz"
        return Dict{String, Any}(
            "type" => "watts_strogatz",
            "neighbors_per_side" => WATTS_NEIGHBORS,
            "rewiring" => 0.1,
        )
    elseif net == "preferential_attachment"
        return Dict{String, Any}("type" => "preferential_attachment", "m" => 2)
    elseif net == "similarity"
        return Dict{String, Any}(
            "type" => "similarity", "m" => 2, "trait" => "preference_private"
        )
    elseif net == "homophily"
        return Dict{String, Any}("type" => "homophily", "m" => 2)
    elseif net == "none"
        return Dict{String, Any}("type" => "none")
    elseif net == "homogeneous_mixing"
        return Dict{String, Any}("type" => "homogeneous_mixing")
    end
    error("unknown network type \"$net\"")
end

"""
    julia_utility_table(config::BenchConfig)::Dict{String,Any}

Build the `[model.utility]` table for one config (the shape accepted by
`GenderNorms.parse_model_config`, see `ADR-0012`). Takes the config and
returns the dictionary with the `type` string and the weights
`w_self`/`w_partner`/`w_transfer` = 1.0 (NetLogo
`weight-working-time-self`/`-partner`/`weight-transfer`), plus
`beta = 0.5` for the `ces` type (NetLogo `CES_beta`).
"""
function julia_utility_table(config::BenchConfig)::Dict{String, Any}
    table = Dict{String, Any}(
        "type" => config.utility,
        "w_self" => 1.0,
        "w_partner" => 1.0,
        "w_transfer" => 1.0,
    )
    if config.utility == "ces"
        table["beta"] = 0.5
    end
    return table
end

"""
    julia_spec_dict(config::BenchConfig)::Dict{String,Any}

Build the complete run specification table for one config (the shape
accepted by `GenderNorms.parse_spec`, see `ADR-0012`). Takes the config
and returns the dictionary with `[run]` (name and seed 42), `[model]`
(the fixed trait tables plus the swept knobs; `initial_lambda = 0.002`
matches the NetLogo `lambda` slider), and `[runtime]`. Deliberately no
`[logging]` table: the timed scope is the core loop only, matching the
NetLogo `go` loop (see `MDR-0011`).
"""
function julia_spec_dict(config::BenchConfig)::Dict{String, Any}
    return Dict{String, Any}(
        "run" => Dict{String, Any}("name" => "benchmark-" * config.id, "seed" => JULIA_SEED),
        "model" => Dict{String, Any}(
            "name" => "gender_norms",
            "agents_per_gender" => config.agents_per_gender,
            "std_dev" => 0.2,
            "initial_transfer" => 0.0,
            "initial_lambda" => 0.002,
            "network" => julia_network_table(config),
            "paid_time" => Dict{String, Any}("men" => 0.77, "women" => 0.36),
            "mean_wage" => Dict{String, Any}("men" => 1.0, "women" => 0.9),
            "mean_preference" => Dict{String, Any}("men" => 0.45, "women" => 0.48),
            "initial_conformism" => Dict{String, Any}(
                "men" => config.conformism, "women" => config.conformism
            ),
            "utility" => julia_utility_table(config),
        ),
        "runtime" => Dict{String, Any}("ticks" => config.ticks),
    )
end

"""
    split_csv_line(line::AbstractString)::Vector{String}

Split one CSV line into fields, honoring double quotes (fields may
contain commas inside quotes; doubled quotes are unescaped). Returns the
field strings without surrounding quotes.
"""
function split_csv_line(line::AbstractString)::Vector{String}
    fields = String[]
    current = IOBuffer()
    quoted = false
    chars = collect(line)
    i = 1
    while i <= length(chars)
        c = chars[i]
        if quoted
            if c == '"'
                if i < length(chars) && chars[i + 1] == '"'
                    print(current, '"')
                    i += 1
                else
                    quoted = false
                end
            else
                print(current, c)
            end
        elseif c == '"'
            quoted = true
        elseif c == ','
            push!(fields, String(take!(current)))
        else
            print(current, c)
        end
        i += 1
    end
    push!(fields, String(take!(current)))
    return fields
end

"""
    behaviorspace_table(path::AbstractString)::Tuple{Vector{String},Vector{Vector{String}}}

Parse one BehaviorSpace table CSV. Takes the file path and returns the
`(columns, rows)` pair: the column names of the `"[run number]"` header
line (quotes stripped) and the data rows as string vectors. The six
comment header lines above the column header are skipped.
"""
function behaviorspace_table(path::AbstractString)::Tuple{Vector{String}, Vector{Vector{String}}}
    isfile(path) || error("BehaviorSpace table not found: $path")
    lines = readlines(path)
    header_idx = findfirst(l -> startswith(l, "\"[run number]\""), lines)
    header_idx === nothing && error("no \"[run number]\" header line in $path")
    columns = split_csv_line(lines[header_idx])
    rows = Vector{String}[]
    for line in lines[(header_idx + 1):end]
        isempty(strip(line)) && continue
        push!(rows, split_csv_line(line))
    end
    return columns, rows
end

"""
    behaviorspace_row_count(path::AbstractString)::Int

Count the data rows of one BehaviorSpace table CSV (all repetitions,
including the dropped run 1). Used by the raw-output completeness check
for resumability. Returns 0 for a missing file.
"""
function behaviorspace_row_count(path::AbstractString)::Int
    isfile(path) || return 0
    _, rows = behaviorspace_table(path)
    return length(rows)
end

"""
    netlogo_runs(path::AbstractString, ticks::Int)::Vector{NetLogoRun}

Parse the per-step series of one BehaviorSpace table CSV into per-run
decompositions (see `MDR-0011`). Takes the file path and the expected
tick count and returns one `NetLogoRun` per `[run number]`, in run
order. Each run's rows must carry the complete step sequence `0:ticks`
(this is asserted before the run is accepted); `setup_s = timer[0]`,
`tick_s[k] = timer[k] - timer[k-1]`, `total_s = timer[ticks]`, and
`drift_s` is `run-time` minus `timer` at the final step.
"""
function netlogo_runs(path::AbstractString, ticks::Int)::Vector{NetLogoRun}
    columns, rows = behaviorspace_table(path)
    i_run = findfirst(==("[run number]"), columns)
    i_step = findfirst(==("[step]"), columns)
    i_timer = findfirst(==("timer"), columns)
    i_rtime = findfirst(==("run-time"), columns)
    (i_run === nothing || i_step === nothing || i_timer === nothing || i_rtime === nothing) &&
        error("missing expected columns in $path (need [run number], [step], timer, run-time)")
    series = Dict{Int, Vector{Tuple{Int, Float64, Float64}}}()
    for row in rows
        length(row) >= length(columns) || error("short row in $path")
        rep = parse(Int, row[i_run])
        push!(
            get!(series, rep, Tuple{Int, Float64, Float64}[]),
            (parse(Int, row[i_step]), parse(Float64, row[i_timer]), parse(Float64, row[i_rtime])),
        )
    end
    out = NetLogoRun[]
    for rep in sort!(collect(keys(series)))
        entries = sort(series[rep]; by = first)
        steps = [e[1] for e in entries]
        steps == collect(0:ticks) || error(
            "incomplete step sequence for run $rep in $path: got $steps, expected 0:$ticks",
        )
        timer = Dict{Int, Float64}(e[1] => e[2] for e in entries)
        rtime = Dict{Int, Float64}(e[1] => e[3] for e in entries)
        tick_s = Float64[timer[k] - timer[k - 1] for k in 1:ticks]
        push!(
            out,
            NetLogoRun(rep, timer[0], tick_s, timer[ticks], rtime[ticks] - timer[ticks]),
        )
    end
    return out
end

"""
    check_timer_drift(config::BenchConfig, runs::Vector{NetLogoRun})

Flag a config when its `run-time` and `timer` final-step values
disagree by more than the timer resolution (a data integrity problem,
see `MDR-0011`). Takes the config and its measured runs and prints one
`[warn]` line per offending run (intended program output). Returns
nothing.
"""
function check_timer_drift(config::BenchConfig, runs::Vector{NetLogoRun})
    for r in runs
        abs(r.drift_s) <= TIMER_RESOLUTION_S && continue
        println(
            "[warn] $(config.id) run $(r.rep): run-time/timer disagree by ",
            @sprintf("%.4f", r.drift_s),
            " s (timer resolution $(TIMER_RESOLUTION_S) s)",
        )
    end
    return nothing
end

"""
    load_invocation_walls()::Dict{Tuple{String,String},Float64}

Load the NetLogo per-invocation process wall times from
`results/netlogo/invocations.csv` (written by `record_invocation_wall!`).
Returns a `(config_id, experiment) => wall_seconds` map, empty when the
file does not exist yet.
"""
function load_invocation_walls()::Dict{Tuple{String, String}, Float64}
    path = joinpath(RESULTS_DIR, "netlogo", "invocations.csv")
    walls = Dict{Tuple{String, String}, Float64}()
    isfile(path) || return walls
    for (i, line) in enumerate(readlines(path))
        i == 1 && continue
        fields = split(line, ',')
        length(fields) == 3 || continue
        walls[(fields[1], fields[2])] = parse(Float64, fields[3])
    end
    return walls
end

"""
    record_invocation_wall!(config_id::String, experiment::String, wall_s::Float64)

Record the process wall time of one NetLogo invocation in
`results/netlogo/invocations.csv` (used for the cold-start derivation:
wall minus the summed in-model `timer` series approximates JVM startup +
model load). Takes the config id, the experiment name, and the wall
seconds, updates the keyed table, and rewrites the file. Returns
nothing.
"""
function record_invocation_wall!(config_id::String, experiment::String, wall_s::Float64)
    walls = load_invocation_walls()
    walls[(config_id, experiment)] = wall_s
    path = joinpath(RESULTS_DIR, "netlogo", "invocations.csv")
    open(path, "w") do io
        println(io, "config_id,experiment,wall_s")
        for key in sort!(collect(keys(walls)))
            println(io, key[1], ",", key[2], ",", @sprintf("%.3f", walls[key]))
        end
    end
    return nothing
end

"""
    run_netlogo_invocation(config::BenchConfig, experiment::String, table_path::String, netlogo_home::String)

Run one headless NetLogo experiment and return its process wall time.
Takes the config (for progress output), the experiment name, the output
table path, and the NetLogo installation directory. Runs
`netlogo-headless.sh` with the generated setup file, absolute model
path, and `--threads 1` (see `MDR-0011`); stdout and stderr are
captured and only printed when the invocation fails. Returns the wall
seconds of the process.
"""
function run_netlogo_invocation(
        config::BenchConfig, experiment::String, table_path::String, netlogo_home::String
    )::Float64
    launcher = joinpath(netlogo_home, "netlogo-headless.sh")
    isfile(launcher) || error("NetLogo launcher not found: $launcher (set NETLOGO_HOME)")
    xml_path = joinpath(RESULTS_DIR, "experiments", config.id * ".xml")
    cmd = Cmd(
        `$launcher --model $MODEL_FILE --setup-file $xml_path --experiment $experiment --table $table_path --threads 1`;
        dir = REPO_ROOT,
    )
    out = IOBuffer()
    err = IOBuffer()
    t0 = time_ns()
    ok = success(pipeline(cmd; stdout = out, stderr = err))
    wall_s = (time_ns() - t0) / 1.0e9
    if !ok
        print(String(take!(out)))
        print(String(take!(err)))
        error("NetLogo experiment \"$experiment\" failed for config $(config.id)")
    end
    return wall_s
end

"""
    netlogo_config_done(config::BenchConfig, repetitions::Int)::Bool

Check whether the raw NetLogo output of one config is complete and can
be skipped (resumability). Takes the config and the expected repetition
count and returns true iff `results/netlogo/<id>.csv` exists and carries
exactly `repetitions * (ticks + 1)` data rows (per-step series: one row
per step `0:ticks` and repetition).
"""
function netlogo_config_done(config::BenchConfig, repetitions::Int)::Bool
    path = joinpath(RESULTS_DIR, "netlogo", config.id * ".csv")
    return behaviorspace_row_count(path) == repetitions * (config.ticks + 1)
end

"""
    run_netlogo_config(config::BenchConfig, repetitions::Int, force::Bool)

Benchmark one config on the NetLogo side. Takes the config, the
repetition count, and the force flag. Writes the BehaviorSpace setup
file (one experiment, per-step `timer` series, see `MDR-0011`) and runs
it into `results/netlogo/<id>.csv`, recording the process wall time in
`results/netlogo/invocations.csv`; a stale `<id>_steps.csv` from the
rejected two-invocation method is deleted. Skips complete raw output
unless `force`. Returns nothing.
"""
function run_netlogo_config(config::BenchConfig, repetitions::Int, force::Bool)
    if !force && netlogo_config_done(config, repetitions)
        println("[netlogo] $(config.id): complete, skipped")
        return nothing
    end
    dir = joinpath(RESULTS_DIR, "netlogo")
    rm(joinpath(dir, config.id * "_steps.csv"); force = true)
    xml_path = joinpath(RESULTS_DIR, "experiments", config.id * ".xml")
    write(xml_path, experiments_xml(config, repetitions))
    table = joinpath(dir, config.id * ".csv")
    println("[netlogo] $(config.id): running $(config.id) ($repetitions repetitions)")
    wall_s = run_netlogo_invocation(config, config.id, table, NETLOGO_HOME)
    record_invocation_wall!(config.id, config.id, wall_s)
    println("[netlogo] $(config.id): done in $(@sprintf("%.1f", wall_s)) s wall")
    return nothing
end

"""
    time_julia_rep(config::BenchConfig, spec)::RepTiming

Time one Julia repetition of one config. Takes the config and the
previously validated `RunSpec` and returns the `RepTiming`: `setup_s`
times `create_world(spec)` (the port of NetLogo `setup`), `steps_s`
times the `step_model!` loop for `tick in 0:(ticks - 1)` (the port of
NetLogo `go`, first call sees tick 0, see `MDR-0022`), `total_s` their
sum, and `tick_s` the per-call seconds of each `step_model!` call. No
GC is forced between repetitions (see `MDR-0011`).
"""
function time_julia_rep(config::BenchConfig, spec)::RepTiming
    ticks = spec.runtime.ticks
    t0 = time_ns()
    world = GN.create_world(spec)
    t1 = time_ns()
    tick_s = Vector{Float64}(undef, ticks)
    for tick in 0:(ticks - 1)
        s0 = time_ns()
        GN.step_model!(GN.GenderNormsModel, world, spec.model_config, tick)
        tick_s[tick + 1] = (time_ns() - s0) / 1.0e9
    end
    t2 = time_ns()
    return RepTiming((t1 - t0) / 1.0e9, (t2 - t1) / 1.0e9, (t2 - t0) / 1.0e9, tick_s)
end

"""
    julia_config_done(config::BenchConfig, measured::Int)::Bool

Check whether the raw Julia output of one config is complete and can be
skipped (resumability). Takes the config and the expected measured
repetition count and returns true iff `results/julia/<id>.csv` carries
exactly `measured` data rows and `results/julia/<id>_ticks.csv` carries
exactly `measured * ticks` rows.
"""
function julia_config_done(config::BenchConfig, measured::Int)::Bool
    path = joinpath(RESULTS_DIR, "julia", config.id * ".csv")
    ticks_path = joinpath(RESULTS_DIR, "julia", config.id * "_ticks.csv")
    (isfile(path) && isfile(ticks_path)) || return false
    return length(readlines(path)) - 1 == measured &&
        length(readlines(ticks_path)) - 1 == measured * config.ticks
end

"""
    run_julia_config(config::BenchConfig, measured::Int, force::Bool)

Benchmark one config on the Julia side. Takes the config, the measured
repetition count, and the force flag. Validates the run specification
with `GenderNorms.parse_spec`, runs `JULIA_WARMUPS` discarded warmup
runs, then `measured` timed repetitions, and writes the per-repetition
rows to `results/julia/<id>.csv` (`rep,setup_s,steps_s,total_s`) plus
the per-call series of every timed repetition to
`results/julia/<id>_ticks.csv` (`rep,tick,seconds`, tick 0-based). No
GC is forced between repetitions. Skips complete raw output unless
`force`. Returns nothing.
"""
function run_julia_config(config::BenchConfig, measured::Int, force::Bool)
    if !force && julia_config_done(config, measured)
        println("[julia] $(config.id): complete, skipped")
        return nothing
    end
    spec = GN.parse_spec(julia_spec_dict(config))
    for _ in 1:JULIA_WARMUPS
        time_julia_rep(config, spec)
    end
    println("[julia] $(config.id): $measured timed repetitions")
    timings = RepTiming[time_julia_rep(config, spec) for _ in 1:measured]
    path = joinpath(RESULTS_DIR, "julia", config.id * ".csv")
    open(path, "w") do io
        println(io, "rep,setup_s,steps_s,total_s")
        for (i, t) in enumerate(timings)
            println(
                io,
                i, ",",
                fmt_seconds(t.setup_s), ",",
                fmt_seconds(t.steps_s), ",",
                fmt_seconds(t.total_s),
            )
        end
    end
    ticks_path = joinpath(RESULTS_DIR, "julia", config.id * "_ticks.csv")
    open(ticks_path, "w") do io
        println(io, "rep,tick,seconds")
        for (i, t) in enumerate(timings)
            for (k, s) in enumerate(t.tick_s)
                println(io, i, ",", k - 1, ",", fmt_seconds(s))
            end
        end
    end
    return nothing
end

"""
    summarise(values::Vector{Float64})::Union{NamedTuple,Nothing}

Compute the distribution summary of one timing column. Takes the values
and returns `(median=, mean=, minimum=, maximum=, n=)` or `nothing` for
an empty vector (missing implementation side in the summary CSV).
"""
function summarise(values::Vector{Float64})::Union{NamedTuple, Nothing}
    isempty(values) && return nothing
    return (
        median = median(values),
        mean = mean(values),
        minimum = minimum(values),
        maximum = maximum(values),
        n = length(values),
    )
end

"""
    impl_cells(total, setup, per_tick, tick_first, tick_last)::Vector{String}

Build the nine per-implementation summary CSV cells of one config. Takes
the `summarise` results of the total, setup, per-tick, first-tick, and
last-tick columns (any may be `nothing` for a missing side) and returns
`median_total`, `median_setup`, `median_per_tick`, `median_tick_first`,
`median_tick_last`, `mean_total`, `min_total`, `max_total`, `n_reps`
(empty strings for a missing side).
"""
function impl_cells(total, setup, per_tick, tick_first, tick_last)::Vector{String}
    total === nothing && return ["", "", "", "", "", "", "", "", ""]
    return [
        fmt_seconds(total.median),
        setup === nothing ? "" : fmt_seconds(setup.median),
        per_tick === nothing ? "" : fmt_seconds(per_tick.median),
        tick_first === nothing ? "" : fmt_seconds(tick_first.median),
        tick_last === nothing ? "" : fmt_seconds(tick_last.median),
        fmt_seconds(total.mean),
        fmt_seconds(total.minimum),
        fmt_seconds(total.maximum),
        string(total.n),
    ]
end

"""
    julia_raw_reps(config::BenchConfig)::Vector{NamedTuple}

Read the timed Julia repetitions of one config from
`results/julia/<id>.csv`. Returns one tuple per repetition with `rep`,
`setup_s`, `steps_s`, and `total_s`. Empty when the raw file is absent.
"""
function julia_raw_reps(config::BenchConfig)::Vector{NamedTuple}
    path = joinpath(RESULTS_DIR, "julia", config.id * ".csv")
    isfile(path) || return NamedTuple[]
    out = NamedTuple[]
    for (i, line) in enumerate(readlines(path))
        i == 1 && continue
        fields = split(line, ',')
        length(fields) == 4 || continue
        push!(
            out,
            (
                rep = parse(Int, fields[1]),
                setup_s = parse(Float64, fields[2]),
                steps_s = parse(Float64, fields[3]),
                total_s = parse(Float64, fields[4]),
            ),
        )
    end
    return out
end

"""
    julia_raw_ticks(config::BenchConfig)::Dict{Int,Vector{Float64}}

Read the per-call Julia series of one config from
`results/julia/<id>_ticks.csv`. Returns a `rep => tick_seconds` map
with the per-tick vectors ordered by tick index (0-based). Empty when
the raw file is absent.
"""
function julia_raw_ticks(config::BenchConfig)::Dict{Int, Vector{Float64}}
    path = joinpath(RESULTS_DIR, "julia", config.id * "_ticks.csv")
    collected = Dict{Int, Vector{Tuple{Int, Float64}}}()
    isfile(path) || return Dict{Int, Vector{Float64}}()
    for (i, line) in enumerate(readlines(path))
        i == 1 && continue
        fields = split(line, ',')
        length(fields) == 3 || continue
        rep = parse(Int, fields[1])
        push!(get!(collected, rep, Tuple{Int, Float64}[]), (parse(Int, fields[2]), parse(Float64, fields[3])))
    end
    return Dict{Int, Vector{Float64}}(
        rep => Float64[s for (_, s) in sort(entries)] for (rep, entries) in collected
    )
end

"""
    config_columns(config::BenchConfig)::Vector{String}

Return the shared config-parameter CSV columns of one config:
`config_id`, `group`, `agents_per_gender`, `ticks`, `network`,
`utility`, `conformism` (used by the flattened tables and the summary).
"""
function config_columns(config::BenchConfig)::Vector{String}
    return [
        config.id,
        config.group,
        fmt_num(config.agents_per_gender),
        fmt_num(config.ticks),
        config.network,
        config.utility,
        fmt_num(config.conformism),
    ]
end

"""
    optional_seconds(value)::String

Format an optional duration for CSV output. Returns the `%.6f` string
for a `Float64` and `""` for `missing`.
"""
function optional_seconds(value)::String
    return value === missing ? "" : fmt_seconds(value)
end

"""
    update_cold_start_csv!(impl::String, rows::Vector{Tuple{String,Float64}})

Merge one implementation's cold-start rows into
`results/cold_start.csv` (`impl,detail,seconds`). Takes the
implementation name and `(detail, seconds)` rows, keeps the other
implementation's rows already in the file, replaces this
implementation's rows, and rewrites the file sorted by implementation
and detail. Returns nothing.
"""
function update_cold_start_csv!(impl::String, rows::Vector{Tuple{String, Float64}})
    path = joinpath(RESULTS_DIR, "cold_start.csv")
    kept = String[]
    if isfile(path)
        for (i, line) in enumerate(readlines(path))
            (i == 1 || isempty(strip(line))) && continue
            startswith(line, impl * ",") && continue
            push!(kept, line)
        end
    end
    for (detail, seconds) in rows
        push!(kept, join([impl, detail, @sprintf("%.3f", seconds)], ","))
    end
    sort!(kept)
    body = isempty(kept) ? "" : join(kept, "\n") * "\n"
    write(path, "impl,detail,seconds\n" * body)
    return nothing
end

"""
    analyse()::Nothing

Rebuild the merged result files from the raw outputs of every config in
the full `config_matrix` (see `ADR-0013`). Writes
`results/netlogo_runs.csv` and `results/julia_runs.csv` (one row per
measured repetition), `results/netlogo_ticks.csv` and
`results/julia_ticks.csv` (flattened per-tick series with config
parameters; NetLogo tick `k` is the `k`-th `go` call, Julia tick `j` is
the `(j+1)`-th `step_model!` call), `results/summary.csv` (per config
and implementation: median/mean/min/max totals, median setup, per-tick,
first-tick and last-tick seconds, repetition counts, and
`speedup_netlogo_over_julia`), and the NetLogo rows of
`results/cold_start.csv` (per invocation: process wall minus the summed
in-model `timer` series). Flags configs whose `run-time` and `timer`
final-step values disagree by more than the timer resolution. Prints
one progress line (intended program output). Returns nothing.
"""
function analyse()
    mkpath(RESULTS_DIR)
    walls = load_invocation_walls()
    netlogo_rows = String[]
    julia_rows = String[]
    netlogo_tick_rows = String[]
    julia_tick_rows = String[]
    summary_rows = String[]
    cold_rows = Tuple{String, Float64}[]
    for config in config_matrix()
        cols = config_columns(config)
        all_runs = NetLogoRun[]
        measured = NetLogoRun[]
        wall = get(walls, (config.id, config.id), missing)
        path = joinpath(RESULTS_DIR, "netlogo", config.id * ".csv")
        if isfile(path)
            all_runs = netlogo_runs(path, config.ticks)
            measured = NetLogoRun[r for r in all_runs if r.rep != 1]
            check_timer_drift(config, measured)
            if wall !== missing && !isempty(all_runs)
                push!(cold_rows, (config.id, wall - sum(r.total_s for r in all_runs)))
            end
        end
        jl_reps = julia_raw_reps(config)
        jl_ticks = julia_raw_ticks(config)
        for r in measured
            push!(
                netlogo_rows,
                join(
                    vcat(
                        cols, [
                            string(r.rep),
                            fmt_seconds(r.total_s),
                            fmt_seconds(r.total_s - r.setup_s),
                            fmt_seconds(r.setup_s),
                            fmt_seconds(r.drift_s),
                            optional_seconds(wall),
                        ]
                    ), ","
                ),
            )
            for (k, s) in enumerate(r.tick_s)
                push!(netlogo_tick_rows, join(vcat(cols, [string(r.rep), string(k), fmt_seconds(s)]), ","))
            end
        end
        for r in jl_reps
            push!(
                julia_rows,
                join(
                    vcat(
                        cols, [
                            string(r.rep),
                            fmt_seconds(r.setup_s),
                            fmt_seconds(r.steps_s),
                            fmt_seconds(r.total_s),
                        ]
                    ), ","
                ),
            )
        end
        for rep in sort!(collect(keys(jl_ticks)))
            for (k, s) in enumerate(jl_ticks[rep])
                push!(julia_tick_rows, join(vcat(cols, [string(rep), string(k - 1), fmt_seconds(s)]), ","))
            end
        end
        (isempty(measured) && isempty(jl_reps)) && continue
        nl_total = summarise(Float64[r.total_s for r in measured])
        jl_total = summarise(Float64[r.total_s for r in jl_reps])
        nl_cells = impl_cells(
            nl_total,
            summarise(Float64[r.setup_s for r in measured]),
            summarise(Float64[(r.total_s - r.setup_s) / config.ticks for r in measured]),
            summarise(Float64[r.tick_s[1] for r in measured]),
            summarise(Float64[r.tick_s[end] for r in measured]),
        )
        jl_cells = impl_cells(
            jl_total,
            summarise(Float64[r.setup_s for r in jl_reps]),
            summarise(Float64[r.steps_s / config.ticks for r in jl_reps]),
            summarise(Float64[v[1] for v in values(jl_ticks) if !isempty(v)]),
            summarise(Float64[v[end] for v in values(jl_ticks) if !isempty(v)]),
        )
        speedup = ""
        if nl_total !== nothing && jl_total !== nothing
            speedup = @sprintf("%.3f", nl_total.median / jl_total.median)
        end
        push!(summary_rows, join(vcat(cols, nl_cells, jl_cells, [speedup]), ","))
    end
    write(
        joinpath(RESULTS_DIR, "netlogo_runs.csv"),
        join(
            vcat(
                [
                    "config_id,group,agents_per_gender,ticks,network,utility,conformism,rep,total_s,steps_s,setup_s,timer_drift_s,invocation_wall_s",
                ], netlogo_rows
            ), "\n"
        ) * "\n",
    )
    write(
        joinpath(RESULTS_DIR, "julia_runs.csv"),
        join(
            vcat(
                [
                    "config_id,group,agents_per_gender,ticks,network,utility,conformism,rep,setup_s,steps_s,total_s",
                ], julia_rows
            ), "\n"
        ) * "\n",
    )
    write(
        joinpath(RESULTS_DIR, "netlogo_ticks.csv"),
        join(
            vcat(
                [
                    "config_id,group,agents_per_gender,ticks,network,utility,conformism,rep,tick,seconds",
                ], netlogo_tick_rows
            ), "\n"
        ) * "\n",
    )
    write(
        joinpath(RESULTS_DIR, "julia_ticks.csv"),
        join(
            vcat(
                [
                    "config_id,group,agents_per_gender,ticks,network,utility,conformism,rep,tick,seconds",
                ], julia_tick_rows
            ), "\n"
        ) * "\n",
    )
    write(
        joinpath(RESULTS_DIR, "summary.csv"),
        join(
            vcat(
                [
                    "config_id,group,agents_per_gender,ticks,network,utility,conformism," *
                        "netlogo_median_total_s,netlogo_median_setup_s,netlogo_median_per_tick_s," *
                        "netlogo_median_tick_first_s,netlogo_median_tick_last_s," *
                        "netlogo_mean_total_s,netlogo_min_total_s,netlogo_max_total_s,netlogo_n_reps," *
                        "julia_median_total_s,julia_median_setup_s,julia_median_per_tick_s," *
                        "julia_median_tick_first_s,julia_median_tick_last_s," *
                        "julia_mean_total_s,julia_min_total_s,julia_max_total_s,julia_n_reps," *
                        "speedup_netlogo_over_julia",
                ], summary_rows
            ), "\n"
        ) * "\n",
    )
    update_cold_start_csv!("netlogo", cold_rows)
    println(
        "analysis: wrote netlogo_runs.csv ($(length(netlogo_rows)) rows), " *
            "julia_runs.csv ($(length(julia_rows)) rows), " *
            "netlogo_ticks.csv ($(length(netlogo_tick_rows)) rows), " *
            "julia_ticks.csv ($(length(julia_tick_rows)) rows), " *
            "summary.csv ($(length(summary_rows)) rows)",
    )
    return nothing
end

"""
    run_cold_start()::Nothing

Measure "time to first result from a fresh process" for the base config
`pop_n100_t20` (see `MDR-0011`). Writes the base config's run
specification as TOML, then spawns `COLD_START_PROCESSES` fresh
`Base.julia_cmd()` processes (each running a tiny inline measurement
script of `parse_spec` + `create_world` + the `step_model!` loop) and
records the process wall seconds as `julia` rows in
`results/cold_start.csv`. The NetLogo rows are derived during
`analyse()`. Prints progress lines (intended program output). Returns
nothing.
"""
function run_cold_start()::Nothing
    mkpath(joinpath(RESULTS_DIR, "experiments"))
    configs = [c for c in config_matrix() if c.id == COLD_START_CONFIG_ID]
    length(configs) == 1 || error("cold-start config $COLD_START_CONFIG_ID not in the matrix")
    config = configs[1]
    spec_path = joinpath(RESULTS_DIR, "experiments", "cold_start_" * COLD_START_CONFIG_ID * ".toml")
    open(spec_path, "w") do io
        TOML.print(io, julia_spec_dict(config))
    end
    script = """
    using GenderNorms
    using TOML
    spec = GenderNorms.parse_spec(TOML.parsefile($(repr(spec_path))))
    world = GenderNorms.create_world(spec)
    for tick in 0:(spec.runtime.ticks-1)
        GenderNorms.step_model!(GenderNorms.GenderNormsModel, world, spec.model_config, tick)
    end
    """
    rows = Tuple{String, Float64}[]
    for i in 1:COLD_START_PROCESSES
        cmd = `$(Base.julia_cmd()) --project=$REPO_ROOT -e $script`
        println("[cold-start] julia $COLD_START_CONFIG_ID process $i/$(COLD_START_PROCESSES)")
        out = IOBuffer()
        err = IOBuffer()
        t0 = time_ns()
        ok = success(pipeline(cmd; stdout = out, stderr = err))
        wall_s = (time_ns() - t0) / 1.0e9
        if !ok
            print(String(take!(out)))
            print(String(take!(err)))
            error("cold-start julia process $i failed")
        end
        println("[cold-start] julia process $i done in $(@sprintf("%.1f", wall_s)) s wall")
        push!(rows, ("$COLD_START_CONFIG_ID-process-$i", wall_s))
    end
    update_cold_start_csv!("julia", rows)
    println("cold start: wrote cold_start.csv ($(length(rows)) julia rows)")
    return nothing
end

"""
    netlogo_version(netlogo_home::String)::String

Detect the NetLogo version of an installation. Takes the NetLogo home
directory and returns the version parsed from the `netlogo-<version>.jar`
file name under `lib/app` (which `netlogo-headless.sh` puts on the
classpath), or `"unknown"` when it cannot be determined.
"""
function netlogo_version(netlogo_home::String)::String
    for path in glob_netlogo_jars(netlogo_home)
        m = match(r"^netlogo-(.+)\.jar$", basename(path))
        m === nothing || return String(m.captures[1])
    end
    return "unknown"
end

"""
    glob_netlogo_jars(netlogo_home::String)::Vector{String}

List the `netlogo-*.jar` files in `<netlogo_home>/lib/app`. Returns the
sorted paths, empty when the directory does not exist.
"""
function glob_netlogo_jars(netlogo_home::String)::Vector{String}
    dir = joinpath(netlogo_home, "lib", "app")
    isdir(dir) || return String[]
    return sort!([joinpath(dir, f) for f in readdir(dir) if startswith(f, "netlogo-") && endswith(f, ".jar")])
end

"""
    first_match_line(path::String, prefix::String)::String

Return the first line of `path` that starts with `prefix`, stripped of
the prefix and surrounding whitespace; returns `"unknown"` when the
file or the line is missing. Used for `/proc/cpuinfo` and
`/proc/meminfo` fields in `collect_environment`.
"""
function first_match_line(path::String, prefix::String)::String
    isfile(path) || return "unknown"
    for line in readlines(path)
        startswith(line, prefix) || continue
        fields = split(line, ":", limit = 2)
        return length(fields) == 2 ? strip(fields[2]) : strip(line)
    end
    return "unknown"
end

"""
    command_output(cmd::Cmd)::String

Run `cmd` and return its combined stdout/stderr, or `"unavailable"` when
the command cannot run or fails. Used for `julia -v`, `java -version`,
and `uname` in `collect_environment`.
"""
function command_output(cmd::Cmd)::String
    out = IOBuffer()
    err = IOBuffer()
    try
        success(pipeline(cmd; stdout = out, stderr = err)) || return "unavailable"
    catch
        return "unavailable"
    end
    text = strip(String(take!(out)) * "\n" * String(take!(err)))
    return isempty(text) ? "unavailable" : replace(text, "\n" => " | ")
end

"""
    collect_environment(netlogo_home::String)::String

Assemble the benchmark environment record (see `ADR-0013`): capture
timestamp, CPU model from `/proc/cpuinfo`, core count, total RAM from
`/proc/meminfo`, OS, `julia -v`, the NetLogo version of
`NETLOGO_HOME`, and `java -version`. Returns the ready-to-write text.
"""
function collect_environment(netlogo_home::String)::String
    io = IOBuffer()
    println(io, "benchmark environment")
    println(io, "captured: ", Dates.format(Dates.now(), "yyyy-mm-ddTHH:MM:SS"))
    println(io, "cpu: ", first_match_line("/proc/cpuinfo", "model name"))
    println(io, "cores: ", Sys.CPU_THREADS)
    println(io, "ram: ", first_match_line("/proc/meminfo", "MemTotal"))
    println(io, "os: ", command_output(`uname -sr`))
    println(io, "julia: ", command_output(`$(Base.julia_cmd().exec[1]) -v`))
    println(io, "netlogo: ", netlogo_version(netlogo_home))
    println(io, "java: ", command_output(`java -version`))
    return String(take!(io))
end

"""
    parse_options(args::Vector{String})::Options

Parse the driver command line. Accepts `--quick`, `--only netlogo` or
`--only julia`, `--force`, `--analyse`, `--cold-start`, and `--help`;
unknown arguments abort with an error. Returns the `Options` (`only`
defaults to `"both"`).
"""
function parse_options(args::Vector{String})::Options
    quick = false
    only = "both"
    force = false
    analyse_only = false
    cold_start = false
    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "--quick"
            quick = true
        elseif arg == "--force"
            force = true
        elseif arg == "--analyse"
            analyse_only = true
        elseif arg == "--cold-start"
            cold_start = true
        elseif arg == "--help" || arg == "-h"
            print_usage()
            exit(0)
        elseif arg == "--only"
            i < length(args) || error("--only requires netlogo or julia")
            i += 1
            args[i] in ("netlogo", "julia") || error("--only requires netlogo or julia")
            only = args[i]
        else
            error("unknown argument \"$arg\"")
        end
        i += 1
    end
    return Options(quick, only, force, analyse_only, cold_start)
end

"""
    print_usage()

Print the driver usage text (intended program output). Returns nothing.
"""
function print_usage()
    println("usage: julia --project=. benchmark/run_benchmarks.jl [options]")
    println("  --quick             smoke subset (pop_n50_t5, util_ces; fewer repetitions)")
    println("  --only netlogo|julia  run one implementation side only")
    println("  --force             redo configs whose raw output is complete")
    println("  --analyse           rebuild the merged CSVs from raw outputs only")
    println("  --cold-start        measure fresh-process startup (base config) and exit")
    println("  --help              print this text")
    println("environment: NETLOGO_HOME (default /opt/netlogo)")
    return nothing
end

"""
    main(args::Vector{String})::Int

Run the benchmark driver (see the file header and `MDR-0011`). Parses
the options; `--cold-start` measures fresh-process startup and
`--analyse` rebuilds the merged files (either mode exits without
running benchmarks), otherwise the selected config subset runs on the
selected implementation sides (skipping complete raw output unless
`--force`), `results/environment.txt` is refreshed, and the merged
files are built at the end. Returns the process exit code (0 on
success).
"""
function main(args::Vector{String})::Int
    opts = parse_options(args)
    if opts.cold_start
        run_cold_start()
    end
    if opts.analyse
        analyse()
    end
    (opts.cold_start || opts.analyse) && return 0
    netlogo_reps = opts.quick ? NETLOGO_REPETITIONS_QUICK : NETLOGO_REPETITIONS
    julia_measured = opts.quick ? JULIA_MEASURED_QUICK : JULIA_MEASURED
    configs = selected_configs(opts.quick)
    println(
        "benchmark: $(length(configs)) config(s), ",
        "netlogo $netlogo_reps repetitions, julia $julia_measured measured repetitions",
    )
    mkpath(joinpath(RESULTS_DIR, "netlogo"))
    mkpath(joinpath(RESULTS_DIR, "julia"))
    mkpath(joinpath(RESULTS_DIR, "experiments"))
    write(joinpath(RESULTS_DIR, "environment.txt"), collect_environment(NETLOGO_HOME))
    if opts.only != "netlogo" && Threads.nthreads() != 1
        println("warning: Julia runs with $(Threads.nthreads()) threads; use one thread (JULIA_NUM_THREADS=1)")
    end
    for config in configs
        if opts.only != "julia"
            run_netlogo_config(config, netlogo_reps, opts.force)
        end
        if opts.only != "netlogo"
            run_julia_config(config, julia_measured, opts.force)
        end
    end
    analyse()
    return 0
end

exit(main(ARGS))
