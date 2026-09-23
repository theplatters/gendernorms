# GenderNorms model binding of the run execution pipeline (see `ADR-0012`).
#
# `GenderNormsModel` (registered as `"gender_norms"`) adapts the ported
# systems to the six `AbstractModel` hooks: specification parsing into
# `GenderNormsConfig`, world setup (port of NetLogo `setup`, ODD section
# Initialization (`setup`, `set-initials-*`)), the per-tick `step_model!`
# (port of NetLogo `to go`, ODD section Process overview and scheduling,
# see `MDR-0010`), working-time metrics, and the configuration echo.

"""
    GenderNormsModel <: AbstractModel

Model binding of this package for the run execution pipeline (see
`ADR-0012`). Implements the six `AbstractModel` hooks
(`model_name`, `parse_model_config`, `setup_world`, `step_model!`,
`model_metrics`, `config_to_dict`) and is registered in
`MODEL_REGISTRY` under `"gender_norms"`.
"""
struct GenderNormsModel <: AbstractModel end

"""
    GenderNormsConfig

Validated model-specific configuration of the `GenderNormsModel`
binding (see `ADR-0012`). Field `properties` carries the household
and network setup, fields `paid_time`, `mean_wage`, `mean_preference`,
and `initial_conformism` carry the gendered trait means, and field
`utility` carries the bargaining payoff weights. Built by
`parse_model_config` and echoed back by `config_to_dict`.
"""
struct GenderNormsConfig
    properties::ModelProperties
    paid_time::PaidTime
    mean_wage::MeanWage
    mean_preference::MeanPreference
    initial_conformism::InitialConformism
    utility::UtilityConfig
end

"""
    model_name(::Type{GenderNormsModel})::String

Specification name of the `GenderNormsModel` binding (see `ADR-0012`).
Takes the model type and returns `"gender_norms"`, the key the
binding is registered under in `MODEL_REGISTRY`.
"""
function model_name(::Type{GenderNormsModel})::String
    return "gender_norms"
end

"""
    _parse_gender_pair(raw::AbstractDict, problems::Vector{String}, path::String, default_men::Float64, default_women::Float64, lo::Float64, hi::Float64)::Tuple{Float64,Float64}

Parse one `men`/`women` specification table of the `GenderNormsModel`
binding (see `ADR-0012`). Takes the raw table, the shared problem
list, the key path used in messages, the defaults, and the inclusive
`[lo, hi]` range (`hi` may be `Inf` for a one-sided bound). Rejects
unknown keys with `_key_problems` and non-numeric, non-finite, or
out-of-range entries. Returns the `(men, women)` pair, keeping defaults for
missing or invalid entries so every problem is collected.
"""
function _parse_gender_pair(
    raw::AbstractDict,
    problems::Vector{String},
    path::String,
    default_men::Float64,
    default_women::Float64,
    lo::Float64,
    hi::Float64,
)::Tuple{Float64,Float64}
    append!(problems, _key_problems(raw, ("men", "women"), path))
    range = isinf(hi) ? "a number >= $lo" : "a number in [$lo, $hi]"
    men = default_men
    if haskey(raw, "men")
        value = raw["men"]
        if value isa Bool || !(value isa Real) || !isfinite(Float64(value)) || !(lo <= Float64(value) <= hi)
            push!(problems, "[$path.men] must be $range, got $(repr(value))")
        else
            men = Float64(value)
        end
    end
    women = default_women
    if haskey(raw, "women")
        value = raw["women"]
        if value isa Bool || !(value isa Real) || !isfinite(Float64(value)) || !(lo <= Float64(value) <= hi)
            push!(problems, "[$path.women] must be $range, got $(repr(value))")
        else
            women = Float64(value)
        end
    end
    return men, women
end

"""
    _parse_network_table(raw::AbstractDict, problems::Vector{String})::NetworkSpec

Parse one `[model.network]` table of the `GenderNormsModel` binding
into a `NetworkSpec` (see `ADR-0012`). Takes the raw table and the
shared problem list. Requires the `type` string naming one of
`random`, `watts_strogatz`, `preferential_attachment`, `similarity`,
`homophily`, `none`, or `homogeneous_mixing`, rejects keys that do
not belong to the selected type, and validates the per-type values.
Returns the specification, keeping the `WattsStrogatz()` default on
missing or invalid input so every problem is collected.
"""
function _parse_network_table(raw::AbstractDict, problems::Vector{String})::NetworkSpec
    allowed = (
        "random",
        "watts_strogatz",
        "preferential_attachment",
        "similarity",
        "homophily",
        "none",
        "homogeneous_mixing",
    )
    shared = ("type", "p", "neighbors_per_side", "rewiring", "m", "trait")
    if !haskey(raw, "type")
        push!(problems, "[model.network] missing required key \"type\"")
        append!(problems, _key_problems(raw, shared, "model.network"))
        return WattsStrogatz()
    end
    kind = raw["type"]
    if !(kind isa String)
        push!(problems, "[model.network.type] must be a string, got $(repr(kind))")
        append!(problems, _key_problems(raw, shared, "model.network"))
        return WattsStrogatz()
    end
    if !(kind in allowed)
        push!(
            problems,
            "[model.network.type] must be one of \"random\", \"watts_strogatz\", " *
            "\"preferential_attachment\", \"similarity\", \"homophily\", \"none\", " *
            "\"homogeneous_mixing\", got $(repr(kind))",
        )
        append!(problems, _key_problems(raw, shared, "model.network"))
        return WattsStrogatz()
    end
    if kind == "random"
        append!(problems, _key_problems(raw, ("type", "p"), "model.network"))
        p = 0.01
        if haskey(raw, "p")
            value = raw["p"]
            if value isa Bool || !(value isa Real) || !isfinite(Float64(value)) || !(0.0 <= Float64(value) <= 1.0)
                push!(problems, "[model.network.p] must be a number in [0.0, 1.0], got $(repr(value))")
            else
                p = Float64(value)
            end
        end
        return RandomNetwork(p = p)
    end
    if kind == "watts_strogatz"
        append!(
            problems,
            _key_problems(raw, ("type", "neighbors_per_side", "rewiring"), "model.network"),
        )
        neighbors_per_side = 1
        if haskey(raw, "neighbors_per_side")
            value = raw["neighbors_per_side"]
            if value isa Bool || !(value isa Integer) || value < 1
                push!(
                    problems,
                    "[model.network.neighbors_per_side] must be an integer >= 1, got $(repr(value))",
                )
            else
                neighbors_per_side = Int(value)
            end
        end
        rewiring = 0.1
        if haskey(raw, "rewiring")
            value = raw["rewiring"]
            if value isa Bool || !(value isa Real) || !isfinite(Float64(value)) || !(0.0 <= Float64(value) <= 1.0)
                push!(
                    problems,
                    "[model.network.rewiring] must be a number in [0.0, 1.0], got $(repr(value))",
                )
            else
                rewiring = Float64(value)
            end
        end
        return WattsStrogatz(neighbors_per_side = neighbors_per_side, rewiring = rewiring)
    end
    if kind == "preferential_attachment"
        append!(problems, _key_problems(raw, ("type", "m"), "model.network"))
        m = 1
        if haskey(raw, "m")
            value = raw["m"]
            if value isa Bool || !(value isa Integer) || value < 1
                push!(problems, "[model.network.m] must be an integer >= 1, got $(repr(value))")
            else
                m = Int(value)
            end
        end
        return PreferentialAttachment(m = m)
    end
    if kind == "similarity"
        append!(problems, _key_problems(raw, ("type", "m", "trait"), "model.network"))
        m = 1
        if haskey(raw, "m")
            value = raw["m"]
            if value isa Bool || !(value isa Integer) || value < 1
                push!(problems, "[model.network.m] must be an integer >= 1, got $(repr(value))")
            else
                m = Int(value)
            end
        end
        trait = :preference_private
        if haskey(raw, "trait")
            value = raw["trait"]
            if !(value isa String) ||
               !(value in ("wage", "conformism", "preference_private"))
                push!(
                    problems,
                    "[model.network.trait] must be one of \"wage\", \"conformism\", " *
                    "\"preference_private\", got $(repr(value))",
                )
            else
                trait = Symbol(value)
            end
        end
        return SimilarityNetwork(m = m, trait = trait)
    end
    if kind == "homophily"
        append!(problems, _key_problems(raw, ("type", "m"), "model.network"))
        m = 1
        if haskey(raw, "m")
            value = raw["m"]
            if value isa Bool || !(value isa Integer) || value < 1
                push!(problems, "[model.network.m] must be an integer >= 1, got $(repr(value))")
            else
                m = Int(value)
            end
        end
        return HomophilyNetwork(m = m)
    end
    if kind == "homogeneous_mixing"
        append!(problems, _key_problems(raw, ("type",), "model.network"))
        return HomogeneousMixing()
    end
    append!(problems, _key_problems(raw, ("type",), "model.network"))
    return NoNetwork()
end

"""
    _parse_utility_table(raw::AbstractDict, problems::Vector{String})::UtilityConfig

Parse one `[model.utility]` table of the `GenderNormsModel` binding
into a `UtilityConfig` (see `ADR-0012`). Takes the raw table and the
shared problem list. Requires the `type` string naming one of
`additive`, `ces`, `multiplicative`, or `multiplicative_weighted`,
validates the `w_self`, `w_partner`, and `w_transfer` weights, and
only accepts `beta` for the `ces` type. Returns the configuration,
keeping defaults on missing or invalid input so every problem is
collected.
"""
function _parse_utility_table(raw::AbstractDict, problems::Vector{String})::UtilityConfig
    allowed = ("additive", "ces", "multiplicative", "multiplicative_weighted")
    append!(
        problems,
        _key_problems(raw, ("type", "w_self", "w_partner", "w_transfer", "beta"), "model.utility"),
    )
    kind = nothing
    if !haskey(raw, "type")
        push!(problems, "[model.utility] missing required key \"type\"")
    else
        value = raw["type"]
        if !(value isa String)
            push!(problems, "[model.utility.type] must be a string, got $(repr(value))")
        elseif !(value in allowed)
            push!(
                problems,
                "[model.utility.type] must be one of \"additive\", \"ces\", " *
                "\"multiplicative\", \"multiplicative_weighted\", got $(repr(value))",
            )
        else
            kind = value
        end
    end
    weights = Dict{String,Float64}("w_self" => 1.0, "w_partner" => 1.0, "w_transfer" => 1.0)
    for key in ("w_self", "w_partner", "w_transfer")
        if haskey(raw, key)
            value = raw[key]
            if value isa Bool || !(value isa Real) || !isfinite(Float64(value)) || Float64(value) < 0.0
                push!(problems, "[model.utility.$key] must be a number >= 0.0, got $(repr(value))")
            else
                weights[key] = Float64(value)
            end
        end
    end
    beta = 0.5
    if haskey(raw, "beta")
        value = raw["beta"]
        if kind !== "ces"
            push!(
                problems,
                "[model.utility.beta] only allowed when type is \"ces\", got $(repr(value))",
            )
        elseif value isa Bool || !(value isa Real) || !isfinite(Float64(value))
            push!(problems, "[model.utility.beta] must be a number, got $(repr(value))")
        else
            beta = Float64(value)
        end
    end
    w_self = weights["w_self"]
    w_partner = weights["w_partner"]
    w_transfer = weights["w_transfer"]
    if kind == "additive"
        return UtilityConfig(func = Additive(), w_self = w_self, w_partner = w_partner, w_transfer = w_transfer)
    end
    if kind == "multiplicative"
        return UtilityConfig(
            func = Multiplicative(), w_self = w_self, w_partner = w_partner, w_transfer = w_transfer
        )
    end
    if kind == "multiplicative_weighted"
        return UtilityConfig(
            func = MultiplicativeWeighted(),
            w_self = w_self,
            w_partner = w_partner,
            w_transfer = w_transfer,
        )
    end
    return UtilityConfig(
        func = CES(beta = beta), w_self = w_self, w_partner = w_partner, w_transfer = w_transfer
    )
end

"""
    parse_model_config(::Type{GenderNormsModel}, raw::Dict{String,Any})::GenderNormsConfig

Validate the model-specific keys of the `[model]` specification table
for the `GenderNormsModel` binding (see `ADR-0012`). Takes the model
type and the raw `[model]` keys without `name`. Accepts the scalar
keys `agents_per_gender`, `std_dev`, `initial_transfer`, and
`initial_lambda`, the `network` table parsed by
`_parse_network_table`, the `paid_time`, `mean_wage`,
`mean_preference`, and `initial_conformism` tables parsed by
`_parse_gender_pair` (spec key `women` maps to the struct field
`woman`), and the `utility` table parsed by `_parse_utility_table`.
Collects every missing key, wrong type, non-finite or out-of-range
value, and unknown key into one `RunSpecError`. Returns the validated
`GenderNormsConfig` on valid input.
"""
function parse_model_config(::Type{GenderNormsModel}, raw::Dict{String,Any})
    problems = String[]
    append!(
        problems,
        _key_problems(
            raw,
            (
                "agents_per_gender",
                "std_dev",
                "initial_transfer",
                "initial_lambda",
                "network",
                "paid_time",
                "mean_wage",
                "mean_preference",
                "initial_conformism",
                "utility",
            ),
            "model",
        ),
    )
    agents_per_gender = Int64(400)
    if haskey(raw, "agents_per_gender")
        value = raw["agents_per_gender"]
        if value isa Bool || !(value isa Integer) || value < 1
            push!(
                problems,
                "[model.agents_per_gender] must be an integer >= 1, got $(repr(value))",
            )
        else
            agents_per_gender = Int64(value)
        end
    end
    std_dev = 0.2
    if haskey(raw, "std_dev")
        value = raw["std_dev"]
        if value isa Bool || !(value isa Real) || !isfinite(Float64(value)) || Float64(value) < 0.0
            push!(problems, "[model.std_dev] must be a number >= 0.0, got $(repr(value))")
        else
            std_dev = Float64(value)
        end
    end
    initial_transfer = 0.0
    if haskey(raw, "initial_transfer")
        value = raw["initial_transfer"]
        if value isa Bool || !(value isa Real) || !isfinite(Float64(value)) || !(0.0 <= Float64(value) <= 1.0)
            push!(
                problems,
                "[model.initial_transfer] must be a number in [0.0, 1.0], got $(repr(value))",
            )
        else
            initial_transfer = Float64(value)
        end
    end
    initial_lambda = 0.5
    if haskey(raw, "initial_lambda")
        value = raw["initial_lambda"]
        if value isa Bool || !(value isa Real) || !isfinite(Float64(value)) || !(0.0 <= Float64(value) <= 1.0)
            push!(
                problems,
                "[model.initial_lambda] must be a number in [0.0, 1.0], got $(repr(value))",
            )
        else
            initial_lambda = Float64(value)
        end
    end
    network::NetworkSpec = WattsStrogatz()
    if haskey(raw, "network")
        value = raw["network"]
        if !(value isa AbstractDict)
            push!(problems, "[model.network] must be a table, got $(repr(value))")
        else
            network = _parse_network_table(value, problems)
        end
    end
    paid_defaults = PaidTime()
    paid_time = paid_defaults
    if haskey(raw, "paid_time")
        value = raw["paid_time"]
        if !(value isa AbstractDict)
            push!(problems, "[model.paid_time] must be a table, got $(repr(value))")
        else
            men, women = _parse_gender_pair(
                value, problems, "model.paid_time", paid_defaults.men, paid_defaults.woman, 0.0, Inf
            )
            paid_time = PaidTime(men = men, woman = women)
        end
    end
    wage_defaults = MeanWage()
    mean_wage = wage_defaults
    if haskey(raw, "mean_wage")
        value = raw["mean_wage"]
        if !(value isa AbstractDict)
            push!(problems, "[model.mean_wage] must be a table, got $(repr(value))")
        else
            men, women = _parse_gender_pair(
                value, problems, "model.mean_wage", wage_defaults.men, wage_defaults.woman, 0.0, Inf
            )
            mean_wage = MeanWage(men = men, woman = women)
        end
    end
    preference_defaults = MeanPreference()
    mean_preference = preference_defaults
    if haskey(raw, "mean_preference")
        value = raw["mean_preference"]
        if !(value isa AbstractDict)
            push!(problems, "[model.mean_preference] must be a table, got $(repr(value))")
        else
            men, women = _parse_gender_pair(
                value,
                problems,
                "model.mean_preference",
                preference_defaults.men,
                preference_defaults.woman,
                0.0,
                1.0,
            )
            mean_preference = MeanPreference(men = men, woman = women)
        end
    end
    conformism_defaults = InitialConformism()
    initial_conformism = conformism_defaults
    if haskey(raw, "initial_conformism")
        value = raw["initial_conformism"]
        if !(value isa AbstractDict)
            push!(problems, "[model.initial_conformism] must be a table, got $(repr(value))")
        else
            men, women = _parse_gender_pair(
                value,
                problems,
                "model.initial_conformism",
                conformism_defaults.men,
                conformism_defaults.woman,
                0.0,
                Inf,
            )
            initial_conformism = InitialConformism(men = men, woman = women)
        end
    end
    utility = UtilityConfig()
    if haskey(raw, "utility")
        value = raw["utility"]
        if !(value isa AbstractDict)
            push!(problems, "[model.utility] must be a table, got $(repr(value))")
        else
            utility = _parse_utility_table(value, problems)
        end
    end
    isempty(problems) || throw(RunSpecError(problems))
    properties = ModelProperties(
        agents_per_gender = agents_per_gender,
        std_dev = std_dev,
        initial_transfer = initial_transfer,
        network = network,
        initial_lambda = initial_lambda,
    )
    return GenderNormsConfig(properties, paid_time, mean_wage, mean_preference, initial_conformism, utility)
end

"""
    setup_world(::Type{GenderNormsModel}, config::GenderNormsConfig, rng)::Ark.World

Construct and fully initialize a runnable world for the
`GenderNormsModel` binding (see `ADR-0012`). Takes the model type,
the validated configuration from `parse_model_config`, and the
seeded run RNG. Registers the household components, adds the
`ModelProperties`, `PaidTime`, `MeanWage`, `MeanPreference`,
`InitialConformism`, and `WorkingTimeStats` resources, then runs
`initialize_household` and `generate_social_network` with the RNG.
Port of NetLogo `setup` (ODD section Initialization (`setup`,
`set-initials-*`)) with the seed-driven draws of ODD Initialization
item 2. Returns the initialized world.
"""
function setup_world(::Type{GenderNormsModel}, config::GenderNormsConfig, rng)::Ark.World
    world = Ark.World(
        Male,
        Female,
        WorkingTime,
        TransferToWoman,
        Spouse,
        Wage,
        PreferencePrivate,
        Conformism,
        CurrentUtility,
        NormParameter,
        PerceptionNormDivisionOfLabor,
        Lambda,
        DirectlyAffected,
    )
    Ark.add_resource!(world, config.properties)
    Ark.add_resource!(world, config.paid_time)
    Ark.add_resource!(world, config.mean_wage)
    Ark.add_resource!(world, config.mean_preference)
    Ark.add_resource!(world, config.initial_conformism)
    Ark.add_resource!(world, WorkingTimeStats(0.0, 0.0, 0.0))
    initialize_household(world, rng)
    generate_social_network(world, rng)
    return world
end

"""
    step_model!(::Type{GenderNormsModel}, world, config::GenderNormsConfig, tick::Int)

Execute one tick of the `GenderNormsModel` binding (see `ADR-0012`).
Takes the model type, the world, the validated configuration, and the
tick count, which counts like the NetLogo `ticks` reporter at `go`
entry: the first call sees 0. Runs, in order, `update_shocks!`
(shock block), `calculate_norm_perception!`, `set_theta!`,
`update_old_working_time_and_transfer!` and
`update_global_working_times!` (the `update-statistics` core), and
`update_preferences`. Port of NetLogo `to go` (ODD section Process
overview and scheduling); see `MDR-0010`. `update_wages!` stays
unscheduled (see `MDR-0009`) and quirk 11 stays deferred under
`TASK-0010`. Returns nothing.
"""
function step_model!(::Type{GenderNormsModel}, world, config::GenderNormsConfig, tick::Int)
    update_shocks!(world, tick)
    calculate_norm_perception!(world, config.utility)
    set_theta!(world, config.utility)
    update_old_working_time_and_transfer!(world)
    update_global_working_times!(world)
    update_preferences(world)
    return nothing
end

"""
    model_metrics(::Type{GenderNormsModel})::Dict{String,Function}

Per-tick metric functions of the `GenderNormsModel` binding (see
`ADR-0012`). Takes the model type and returns the `working_time_men`,
`working_time_women`, and `working_time_gap` mapping, each reading
its field of the world's `WorkingTimeStats` resource. The runner
evaluates the configured subset after every tick.
"""
function model_metrics(::Type{GenderNormsModel})::Dict{String,Function}
    return Dict{String,Function}(
        "working_time_men" => world -> Ark.get_resource(world, WorkingTimeStats).men,
        "working_time_women" => world -> Ark.get_resource(world, WorkingTimeStats).women,
        "working_time_gap" => world -> Ark.get_resource(world, WorkingTimeStats).gap,
    )
end

"""
    _network_to_dict(spec::NetworkSpec)::Dict{String,Any}

Echo one `NetworkSpec` of the `GenderNormsModel` binding as the
`[model.network]` table shape accepted by `_parse_network_table`
(see `ADR-0012`). Takes the specification and returns the plain
dictionary with its `type` string and per-type values, using the
`men`/`women` key names of the specification. Helper of
`config_to_dict`.
"""
function _network_to_dict(spec::NetworkSpec)::Dict{String,Any}
    if spec isa RandomNetwork
        return Dict{String,Any}("type" => "random", "p" => Float64(spec.p))
    end
    if spec isa WattsStrogatz
        return Dict{String,Any}(
            "type" => "watts_strogatz",
            "neighbors_per_side" => Int(spec.neighbors_per_side),
            "rewiring" => Float64(spec.rewiring),
        )
    end
    if spec isa PreferentialAttachment
        return Dict{String,Any}("type" => "preferential_attachment", "m" => Int(spec.m))
    end
    if spec isa SimilarityNetwork
        return Dict{String,Any}(
            "type" => "similarity", "m" => Int(spec.m), "trait" => string(spec.trait)
        )
    end
    if spec isa HomophilyNetwork
        return Dict{String,Any}("type" => "homophily", "m" => Int(spec.m))
    end
    if spec isa NoNetwork
        return Dict{String,Any}("type" => "none")
    end
    if spec isa HomogeneousMixing
        return Dict{String,Any}("type" => "homogeneous_mixing")
    end
    throw(ArgumentError("unknown NetworkSpec $(typeof(spec))"))
end

"""
    _utility_to_dict(config::UtilityConfig)::Dict{String,Any}

Echo one `UtilityConfig` of the `GenderNormsModel` binding as the
`[model.utility]` table shape accepted by `_parse_utility_table`
(see `ADR-0012`). Takes the configuration and returns the plain
dictionary with its `type` string, the `w_self`, `w_partner`, and
`w_transfer` weights, and `beta` for the `ces` type. Helper of
`config_to_dict`.
"""
function _utility_to_dict(config::UtilityConfig)::Dict{String,Any}
    out = Dict{String,Any}(
        "w_self" => Float64(config.w_self),
        "w_partner" => Float64(config.w_partner),
        "w_transfer" => Float64(config.w_transfer),
    )
    func = config.func
    if func isa Additive
        out["type"] = "additive"
        return out
    end
    if func isa CES
        out["type"] = "ces"
        out["beta"] = Float64(func.beta)
        return out
    end
    if func isa Multiplicative
        out["type"] = "multiplicative"
        return out
    end
    if func isa MultiplicativeWeighted
        out["type"] = "multiplicative_weighted"
        return out
    end
    throw(ArgumentError("unknown UtilitySpec $(typeof(func))"))
end

"""
    config_to_dict(::Type{GenderNormsModel}, config::GenderNormsConfig)::Dict{String,Any}

TOML-compatible echo of the resolved `GenderNormsModel` configuration
(see `ADR-0012`). Takes the model type and the validated
configuration and returns a plain dictionary in the exact `[model]`
shape accepted by `parse_model_config`, with the `network` table
from `_network_to_dict`, the `utility` table from
`_utility_to_dict`, and the `men`/`women` key names, so the run
record can recover the configuration.
"""
function config_to_dict(::Type{GenderNormsModel}, config::GenderNormsConfig)::Dict{String,Any}
    properties = config.properties
    return Dict{String,Any}(
        "agents_per_gender" => Int(properties.agents_per_gender),
        "std_dev" => Float64(properties.std_dev),
        "initial_transfer" => Float64(properties.initial_transfer),
        "initial_lambda" => Float64(properties.initial_lambda),
        "network" => _network_to_dict(properties.network),
        "paid_time" => Dict{String,Any}(
            "men" => Float64(config.paid_time.men), "women" => Float64(config.paid_time.woman)
        ),
        "mean_wage" => Dict{String,Any}(
            "men" => Float64(config.mean_wage.men), "women" => Float64(config.mean_wage.woman)
        ),
        "mean_preference" => Dict{String,Any}(
            "men" => Float64(config.mean_preference.men),
            "women" => Float64(config.mean_preference.woman),
        ),
        "initial_conformism" => Dict{String,Any}(
            "men" => Float64(config.initial_conformism.men),
            "women" => Float64(config.initial_conformism.woman),
        ),
        "utility" => _utility_to_dict(config.utility),
    )
end

MODEL_REGISTRY["gender_norms"] = GenderNormsModel
