function generate_social_network(world)
end

function initialize_household(world)

  properties = Ark.get_resource(world, ModelProperties)
  for i in 1:properties.agents_per_gender
    w = Ark.new_entity!(world, get_woman(world))
    m = Ark.new_entity!(world, get_men(world))
    Ark.set_component

    world[w][Spouse] = Spouse[m]
    world[m][Spouse] = Spouse[w]

  end
  return Ark.new_entities(world)
end

function get_agent(world::Ark.World, gender::Gender)

  properties = Ark.get_resource(world, ModelProperties)

  mean_working_time = for_gender(
    Ark.get_resource(world, PaidTime),
    gender
  )


  mean_wage = Ark.get_resource(world, MeanWage)
  mean_wage_gender = for_gender(mean_wage, gender)

  mean_preference = Ark.get_resource(world, MeanPreference)
  mean_preference_gender = for_gender(mean_preference, gender)


  initial_conformism = Ark.get_resource(world, InitialCConformism)
  initial_conformism_gender = for_gender(initial_conformism, gender)

  working_time = WorkingTime(mean_working_time, mean_working_time)


  wage_draw = clamp(
    rand(Normal(mean_wage_gender, gender_mean(mean_wage))),
    0.0, 1.0
  )

  wage = Wage(wage_draw, wage_draw)

  conformism = clamp(
    rand(Normal(initial_conformism_gender, gender_mean(initial_conformism) * properties.std_dev)),
    0.0, 1.0
  ) |> Conformism

  private_preference = clamp(
    rand(Normal(mean_preference_gender, gender_mean(mean_preference) * properties.std_dev)),
    0.0, 1.0
  ) |> PreferencePrivate

  return (working_time, wage, conformism, private_preference, Spouse(Ark.zero_entity))
end

function get_woman(world)
  components = get_agent(world, Female())

  properties = Ark.get_resource(world, ModelProperties)

  transfer_draw = clamp(rand(Normal(properties.initial_transfer, properties.initial_transfer * properties.std_dev)), 0.0, 1.0)
  transfer_to_woman = TransferToWoman(transfer_draw, transfer_draw)
  return (components..., transfer_to_woman)
end

get_men(world) = get_agent(world, Male())
