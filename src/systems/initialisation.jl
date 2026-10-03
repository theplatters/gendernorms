# Initialisation of the model (`setup`, `set-initials-women`, `set-initials-men`,
# `generate-network` and `generate-homophilic-network` in the NetLogo model).

# Normal draw with zero variance handled as a point mass (`Normal` requires sigma > 0).
"""
    draw_normal(mu::Float64, sigma::Float64, rng)

Draw one sample from `Normal(mu, sigma)` with `rng`, returning `mu` unchanged
when `sigma <= 0` because `Normal` requires a positive scale. Helper of the
`set-initials-*` trait draws in the NetLogo model (NetLogo
`set-initials-women` and `set-initials-men`, ODD section Initialization
(`setup`, `set-initials-*`)). The `rng` argument drives the stochastic setup
draws, corresponding to the `random-seed random-seed-fixed` seeding under
`fixed-rs` in ODD section Initialization. Returns the drawn value.
"""
draw_normal(mu::Float64, sigma::Float64, rng) = sigma > 0 ? rand(rng, Normal(mu, sigma)) : mu

"""
    initialize_household(world, rng)

Create `ModelProperties.agents_per_gender` women and men, give them their
initial traits (drawn from the truncated normals in `set-initials-*`) and pair
each woman with one man. Port of NetLogo `setup` (ODD section Initialization
(`setup`, `set-initials-*`)). The network specification is read from the
world's `ModelProperties` resource (see `ADR-0010`). The `rng` argument drives
the stochastic setup draws (trait draws and network generation),
corresponding to the `random-seed random-seed-fixed` seeding under `fixed-rs`
in ODD section Initialization. Returns the `(women, men)` entity vectors.
"""
function initialize_household(world, rng)
  properties = Ark.get_resource(world, ModelProperties)
  n = properties.agents_per_gender

  women = Vector{Ark.Entity}(undef, n)
  men = Vector{Ark.Entity}(undef, n)

  for i in 1:n
    woman = Ark.new_entity!(world, get_woman(world, rng))
    transfer, = Ark.get_components(world, woman, (TransferToWoman,))

    # the man inherits the initial transfer from his spouse
    man = Ark.new_entity!(world, (get_men(world, rng)..., transfer))

    Ark.set_components!(world, woman, (Spouse(man),))
    Ark.set_components!(world, man, (Spouse(woman),))

    women[i] = woman
    men[i] = man
  end

  return women, men
end

"""
    get_agent(world, gender, rng)

Build the initial component tuple for one agent of `gender`: working time at
the gender mean plus wage, conformism, and private preference drawn from the
truncated normals in `set-initials-*`. Port of NetLogo `set-initials-women`
and `set-initials-men` (ODD section Initialization (`setup`,
`set-initials-*`)). The `rng` argument drives the stochastic setup draws,
corresponding to the `random-seed random-seed-fixed` seeding under `fixed-rs`
in ODD section Initialization. Returns the component tuple.
"""
function get_agent(world::Ark.World, gender::Gender, rng)

  properties = Ark.get_resource(world, ModelProperties)

  mean_working_time = for_gender(Ark.get_resource(world, PaidTime), gender)

  mean_wage = Ark.get_resource(world, MeanWage)
  mean_preference = Ark.get_resource(world, MeanPreference)
  mean_conformism = Ark.get_resource(world, InitialConformism)

  working_time = WorkingTime(mean_working_time, mean_working_time)

  wage_draw = max(
    0.0,
    draw_normal(
      for_gender(mean_wage, gender),
      gender_mean(mean_wage) * properties.std_dev,
      rng,
    ),
  )
  wage = Wage(wage_draw, wage_draw)

  conformism = max(
    0.0,
    draw_normal(
      for_gender(mean_conformism, gender),
      properties.std_dev * gender_mean(mean_conformism),
      rng,
    ),
  ) |> Conformism

  private_preference_draw = clamp(
    draw_normal(
      for_gender(mean_preference, gender),
      properties.std_dev * gender_mean(mean_preference),
      rng,
    ),
    0.01, 0.99,
  )
  private_preference = PreferencePrivate(private_preference_draw, private_preference_draw)

  return (
    gender,
    working_time,
    wage,
    conformism,
    private_preference,
    NormParameter(0.0),
    PerceptionNormDivisionOfLabor(0.0),
    Lambda(properties.initial_lambda),
    Spouse(Ark.zero_entity),
  )
end

"""
    get_woman(world, rng)

Build the initial component tuple for one woman: the `get_agent` components
for `Female()` plus the initial transfer to the woman. Port of NetLogo
`set-initials-women` (ODD section Initialization (`setup`,
`set-initials-*`)). The `rng` argument drives the stochastic setup draws,
corresponding to the `random-seed random-seed-fixed` seeding under `fixed-rs`
in ODD section Initialization. Returns the component tuple.
"""
function get_woman(world, rng)
  components = get_agent(world, Female(), rng)

  properties = Ark.get_resource(world, ModelProperties)

  transfer_draw = clamp(
    draw_normal(
      properties.initial_transfer,
      properties.initial_transfer * properties.std_dev,
      rng,
    ),
    0.0, 1.0,
  )
  transfer_to_woman = TransferToWoman(transfer_draw, transfer_draw)
  return (components..., transfer_to_woman)
end

"""
    get_men(world, rng)

Build the initial component tuple for one man via `get_agent` with `Male()`.
Port of NetLogo `set-initials-men` (ODD section Initialization (`setup`,
`set-initials-*`)). The `rng` argument drives the stochastic setup draws,
corresponding to the `random-seed random-seed-fixed` seeding under `fixed-rs`
in ODD section Initialization. Returns the component tuple.
"""
get_men(world, rng) = get_agent(world, Male(), rng)

"""
    generate_social_network(world, rng)

Build the same-sex networks with `network_graph`: agents have to be created
first (similarity networks are weighted by agent traits). Port of NetLogo
`setup` with `generate-network` and `generate-homophilic-network` (ODD section
Initialization). The `rng` argument drives the stochastic setup draws
(network generation), corresponding to the `random-seed random-seed-fixed`
seeding under `fixed-rs` in ODD section Initialization. Adds the
`SocialNetwork` resource to the world and returns it. Throws `ArgumentError`
when either sex misses its expected agents: run `initialize_household` first.
"""
function generate_social_network(world, rng)

  properties = Ark.get_resource(world, ModelProperties)
  n = properties.agents_per_gender

  women = entities_with(world, Female)
  men = entities_with(world, Male)

  length(women) == n ||
    throw(ArgumentError("expected $n women, found $(length(women)): run initialize_household first"))
  length(men) == n ||
    throw(ArgumentError("expected $n men, found $(length(men)): run initialize_household first"))

  women_graph = network_graph(world, properties.network, women, rng)
  men_graph = network_graph(world, properties.network, men, rng)

  return Ark.add_resource!(world, SocialNetwork(men_graph, women_graph, men, women))
end

network_graph(_, spec::NetworkSpec, entities, rng) = generate(spec, length(entities), rng)

function network_graph(world, spec::SimilarityNetwork, entities, rng)
  values = trait_values(world, entities, spec.trait)
  return generate_similarity(spec, values, rng)
end

function network_graph(world, spec::HomophilyNetwork, entities, rng)
  conformism = trait_values(world, entities, :conformism)
  wage = trait_values(world, entities, :wage)
  preference = trait_values(world, entities, :preference_private)
  return generate_homophily(spec, conformism, wage, preference, rng)
end

trait_values(world, entities::AbstractArray, trait::Symbol) =
  [trait_value(world, entity, trait) for entity in entities]

function trait_value(world, entity, trait::Symbol)
  if trait === :wage
    return Ark.get_components(world, entity, (Wage,))[1].current
  elseif trait === :conformism
    return Ark.get_components(world, entity, (Conformism,))[1].amount
  elseif trait === :preference_private
    return Ark.get_components(world, entity, (PreferencePrivate,))[1].current
  end
  throw(ArgumentError("unknown similarity trait $trait"))
end

function entities_with(world, ::Type{T}) where {T}
  entities = Ark.Entity[]
  for (batch,) in Ark.Query(world, (); with=(T,))
    append!(entities, batch)
  end
  return entities
end
