#  ask turtles [
#    set preference-difference current-working-time - preference-private
#    let current-preference-private preference-private
#    set preference-private (1 - lambda) * current-preference-private + lambda * current-working-time
#    set preference-private max list 0 (min list 1 preference-private)
#  ]

function update_preferences(world)
  for (e, lambda, preference_private, wt) in Ark.Query(world, (Lambda, PreferencePrivate, WorkingTime))
    @inbounds for i in eachindex(e)
      preference_private[i] = PreferencePrivate(
        (1 - lambda[i].amount) * preference_private[i].current + lambda[i].amount * wt[i].current,
        preference_private[i].pre,
      )
    end

  end
  return
end
