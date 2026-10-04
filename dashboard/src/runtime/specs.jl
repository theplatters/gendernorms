# Form-to-spec construction of the dashboard runtime.
#
# The UI layer submits flat form dictionaries; `build_spec_dict` turns
# one into the nested run specification shape, assembling the
# `[model.network]` and `[model.utility]` tables from the ACTIVE form
# controls only so stale hidden keys never reach the model.
# `validate_form` validates through `GenderNorms.parse_spec` and
# surfaces `RunSpecError.problems` unchanged; `default_form` and
# `clone_form` derive form dictionaries from validated specifications
# without duplicating model defaults.

"""
    DEFAULT_RECORD_DIRECTORY

Dashboard-managed record directory `"runs/.dashboard-staging"` used by
`clone_form` as the staging directory of cloned runs. The run manager
replaces every spec logging output with the per-job staging directory
at execution time, so recorded output directories are never reused.
"""
const DEFAULT_RECORD_DIRECTORY = "runs/.dashboard-staging"

"""
    NETWORK_PARAMS

Per-type parameters of the `[model.network]` table, keyed by the
`network_type` form value. `build_spec_dict` copies only the listed
parameters of the active type into the spec dictionary; the type
strings match the ones `GenderNorms` accepts.
"""
const NETWORK_PARAMS = Dict{String,Vector{String}}(
    "random" => ["p"],
    "watts_strogatz" => ["neighbors_per_side", "rewiring"],
    "preferential_attachment" => ["m"],
    "similarity" => ["m", "trait"],
    "homophily" => ["m"],
    "none" => String[],
    "homogeneous_mixing" => String[],
)

"""
    NETWORK_PARAM_KINDS

Form coercion kinds of the `[model.network]` parameters: `:int` for
`neighbors_per_side` and `m`, `:string` for `trait`, and `:float` for
`p` and `rewiring`. See `build_spec_dict`.
"""
const NETWORK_PARAM_KINDS = Dict{String,Symbol}(
    "p" => :float,
    "neighbors_per_side" => :int,
    "rewiring" => :float,
    "m" => :int,
    "trait" => :string,
)

"""
    UTILITY_PARAMS

Per-type parameters of the `[model.utility]` table, keyed by the
`utility_type` form value. `beta` is active only for `"ces"`; the
weights are active for every type.
"""
const UTILITY_PARAMS = Dict{String,Vector{String}}(
    "additive" => ["w_self", "w_partner", "w_transfer"],
    "ces" => ["w_self", "w_partner", "w_transfer", "beta"],
    "multiplicative" => ["w_self", "w_partner", "w_transfer"],
    "multiplicative_weighted" => ["w_self", "w_partner", "w_transfer"],
)

"""
    GENDER_PAIR_TABLES

Model tables carrying `men`/`women` pairs with their form key prefixes:
`paid_time`, `mean_wage`, `mean_preference`, and `initial_conformism`.
"""
const GENDER_PAIR_TABLES = (
    ("paid_time", "paid_time"),
    ("mean_wage", "mean_wage"),
    ("mean_preference", "mean_preference"),
    ("initial_conformism", "initial_conformism"),
)

"""
    _form_value(form::AbstractDict, key::String, kind::Symbol)

Coerce one flat form value to its spec-dict kind. Takes the form, the
form key, and the target kind (`:int`, `:float`, or `:string`). String
values are parsed server-side with `tryparse`; an empty or blank string
returns `nothing` so the key is omitted. A value that cannot be parsed
is returned unchanged so `GenderNorms.parse_spec` reports the problem
against the spec key. Returns the coerced value, the raw value, or
`nothing`.
"""
function _form_value(form::AbstractDict, key::String, kind::Symbol)
    value = get(form, key, nothing)
    value === nothing && return nothing
    if value isa AbstractString
        text = strip(value)
        isempty(text) && return nothing
        kind === :string && return String(text)
        kind === :int && return something(tryparse(Int, text), String(text))
        return something(tryparse(Float64, text), String(text))
    end
    if kind === :int
        return value isa Integer && !(value isa Bool) ? Int(value) : value
    elseif kind === :float
        return value isa Real && !(value isa Bool) ? Float64(value) : value
    end
    return value
end

"""
    _assign!(table::Dict{String,Any}, target::String, form::AbstractDict, key::String, kind::Symbol)

Copy one coerced form value into a spec-dict table. Takes the target
table, the target key, the form, the form key, and the coercion kind of
`_form_value`. Assigns only when the form carries a value; empty
strings and missing keys leave the target unset. Returns nothing.
"""
function _assign!(
    table::Dict{String,Any},
    target::String,
    form::AbstractDict,
    key::String,
    kind::Symbol,
)
    value = _form_value(form, key, kind)
    value === nothing || (table[target] = value)
    return nothing
end

"""
    build_spec_dict(form::AbstractDict)::Dict{String,Any}

Convert one flat UI form into the nested run spec dictionary. Takes
the form with keys `name`, `seed`, `ticks`, `agents_per_gender`,
`std_dev`, `initial_transfer`, `initial_lambda`, `network_type`,
`network_*` parameters, `utility_type`, `utility_*` parameters,
`paid_time_*`, `mean_wage_*`, `mean_preference_*`,
`initial_conformism_*`, `metrics`, and `record_directory`, all
optional. Numeric strings are parsed server-side; blank values are
omitted; values that cannot be parsed are passed through so
`GenderNorms.parse_spec` reports them. The `network` and `utility`
tables are built from the active controls of the selected types only
(see `NETWORK_PARAMS` and `UTILITY_PARAMS`), so stale hidden keys never
reach the model. `[logging] outputs` carries the dashboard-managed
`toml` policy into `record_directory` when that key is set (see
`clone_form`), and no outputs otherwise. Unknown form keys are
ignored. Returns the dictionary accepted by `GenderNorms.parse_spec`.
"""
function build_spec_dict(form::AbstractDict)::Dict{String,Any}
    flat = Dict{String,Any}(string(key) => value for (key, value) in form)

    run = Dict{String,Any}()
    _assign!(run, "name", flat, "name", :string)
    _assign!(run, "seed", flat, "seed", :int)

    model = Dict{String,Any}("name" => "gender_norms")
    _assign!(model, "agents_per_gender", flat, "agents_per_gender", :int)
    _assign!(model, "std_dev", flat, "std_dev", :float)
    _assign!(model, "initial_transfer", flat, "initial_transfer", :float)
    _assign!(model, "initial_lambda", flat, "initial_lambda", :float)

    network = Dict{String,Any}()
    _assign!(network, "type", flat, "network_type", :string)
    if get(network, "type", nothing) isa AbstractString
        for param in get(NETWORK_PARAMS, network["type"], String[])
            _assign!(network, param, flat, "network_" * param, NETWORK_PARAM_KINDS[param])
        end
    end
    isempty(network) || (model["network"] = network)

    utility = Dict{String,Any}()
    _assign!(utility, "type", flat, "utility_type", :string)
    if get(utility, "type", nothing) isa AbstractString
        for param in get(UTILITY_PARAMS, utility["type"], String[])
            _assign!(utility, param, flat, "utility_" * param, :float)
        end
    end
    isempty(utility) || (model["utility"] = utility)

    for (table_name, prefix) in GENDER_PAIR_TABLES
        pair = Dict{String,Any}()
        _assign!(pair, "men", flat, prefix * "_men", :float)
        _assign!(pair, "women", flat, prefix * "_women", :float)
        isempty(pair) || (model[table_name] = pair)
    end

    logging = Dict{String,Any}()
    if haskey(flat, "metrics")
        metrics = flat["metrics"]
        logging["metrics"] = metrics isa AbstractVector ? Any[entry for entry in metrics] : metrics
    end
    directory = _form_value(flat, "record_directory", :string)
    logging["outputs"] = if directory === nothing
        Any[]
    else
        Any[Dict{String,Any}("type" => "toml", "directory" => directory)]
    end

    runtime = Dict{String,Any}()
    _assign!(runtime, "ticks", flat, "ticks", :int)

    return Dict{String,Any}(
        "run" => run,
        "model" => model,
        "runtime" => runtime,
        "logging" => logging,
    )
end

"""
    validate_form(form::AbstractDict)::Union{GenderNorms.RunSpec,Vector{String}}

Validate one flat UI form. Takes the form, builds the spec dictionary
with `build_spec_dict`, and validates it with
`GenderNorms.parse_spec`. Returns the validated `GenderNorms.RunSpec`
on valid input, or the aggregated `RunSpecError.problems` vector
unchanged on invalid input. Other exceptions propagate.
"""
function validate_form(form::AbstractDict)::Union{GN.RunSpec,Vector{String}}
    try
        return GN.parse_spec(build_spec_dict(form))
    catch err
        err isa GN.RunSpecError || rethrow()
        return copy(err.problems)
    end
end

"""
    form_from_spec(spec::GenderNorms.RunSpec)::Dict{String,Any}

Flatten a validated run spec back into a UI form. Takes the `RunSpec`
and returns the flat dictionary with the keys of `build_spec_dict`,
taken from the `GenderNorms.spec_to_dict` echo so model defaults are
never duplicated here. The `record_directory` key is set only when the
spec carries a `toml` logging output, holding that output's directory;
otherwise the key is absent and `build_spec_dict` emits no outputs.
The result re-validates to an equivalent spec through
`build_spec_dict`.
"""
function form_from_spec(spec::GN.RunSpec)::Dict{String,Any}
    dict = GN.spec_to_dict(spec)
    model = dict["model"]
    form = Dict{String,Any}()
    form["name"] = String(dict["run"]["name"])
    form["seed"] = Int(dict["run"]["seed"])
    form["ticks"] = Int(dict["runtime"]["ticks"])
    form["agents_per_gender"] = Int(model["agents_per_gender"])
    form["std_dev"] = Float64(model["std_dev"])
    form["initial_transfer"] = Float64(model["initial_transfer"])
    form["initial_lambda"] = Float64(model["initial_lambda"])

    network = model["network"]
    form["network_type"] = String(network["type"])
    for param in NETWORK_PARAMS[form["network_type"]]
        kind = NETWORK_PARAM_KINDS[param]
        value = network[param]
        form["network_" * param] =
            kind === :int ? Int(value) : kind === :string ? String(value) : Float64(value)
    end

    utility = model["utility"]
    form["utility_type"] = String(utility["type"])
    for param in UTILITY_PARAMS[form["utility_type"]]
        form["utility_" * param] = Float64(utility[param])
    end

    for (table_name, prefix) in GENDER_PAIR_TABLES
        pair = model[table_name]
        form[prefix * "_men"] = Float64(pair["men"])
        form[prefix * "_women"] = Float64(pair["women"])
    end

    logging = dict["logging"]
    form["metrics"] = String[String(entry) for entry in logging["metrics"]]
    for output in logging["outputs"]
        if output["type"] == "toml"
            form["record_directory"] = String(get(output, "directory", "runs"))
        end
    end
    return form
end

"""
    default_form()::Dict{String,Any}

Build the default UI form. Takes no arguments and derives the form
from a minimal valid spec (run name, seed, model name, and tick budget
only) through `GenderNorms.parse_spec`, `GenderNorms.spec_to_dict`,
and `form_from_spec`, so all model defaults come from `GenderNorms`.
Returns the flat form dictionary, which validates with `validate_form`.
"""
function default_form()::Dict{String,Any}
    minimal = Dict{String,Any}(
        "run" => Dict{String,Any}("name" => "dashboard-run", "seed" => 0),
        "model" => Dict{String,Any}("name" => "gender_norms"),
        "runtime" => Dict{String,Any}("ticks" => 50),
    )
    return form_from_spec(GN.parse_spec(minimal))
end

"""
    copy_name(name::AbstractString)::String

Propose the name of a cloned run. Takes the source run name and
returns it with `" copy"` appended, or `"copy"` when the source name is
empty.
"""
function copy_name(name::AbstractString)::String
    text = strip(name)
    return isempty(text) ? "copy" : string(text, " copy")
end

"""
    clone_form(source; staging_dir::AbstractString = DEFAULT_RECORD_DIRECTORY)::Dict{String,Any}

Clone the model settings of one run into a new UI form. Takes a
`RunPath` or the path of a `run.toml` record and the staging directory
for the cloned run's record policy. Copies the model configuration,
seed, and metric selection from the run's validated spec via
`form_from_spec`, proposes a copied name with `copy_name`, and replaces
`[logging] outputs` with the dashboard-managed policy into `staging_dir`
so recorded output directories are never reused. Throws `ArgumentError`
when the run has no valid spec (cloning disabled). Returns the flat
form dictionary.
"""
function clone_form(
    source;
    staging_dir::AbstractString = DEFAULT_RECORD_DIRECTORY,
)::Dict{String,Any}
    path = source isa RunPath ? source : read_record(String(source))
    if path.spec === nothing
        detail =
            isempty(path.spec_problems) ? "no specification on record" :
            join(path.spec_problems, "; ")
        label = isempty(path.run_id) ? path.record_path : path.run_id
        throw(ArgumentError("run \"$label\" has no valid specification ($detail); cloning is disabled"))
    end
    form = form_from_spec(path.spec)
    form["name"] = copy_name(path.name)
    form["record_directory"] = String(staging_dir)
    return form
end
