# choose_bundle(m,w,theta):
#    change[w] <- 1;  change[m] <- 1
#    memory[w] <- []; memory[m] <- []          # solver scratch, persists across sweeps
#
#    while change[w] + change[m] > eps:
#
#        for i in (w, m):                     # sequential (Gauss-Seidel), each sees
#                                             # the partner's latest h; order unspecified
#            h0 <- h_i
#            u0 <- U_i(h_i, h_j, theta)            # current-utility (reference value)
#
#            S <- 1
#            if memory[i] is non-empty:
#                S <- |sum(memory[w])| + |sum(memory[m])|
#
#            delta <- -d
#            while delta <= d:                     # only delta = -d and delta = +d ever run
#                while h_i + delta in [0,1] and S != 0:
#                    u' <- U_i(h_i + delta, h_j, theta)
#                    if u' - u0 <= 0: break    # requires strict improvement
#                    h_i <- clamp(h_i + delta, 0, 1)
#                    u0 <- u'
#                    push_front(memory[i], delta)
#                    if length(memory[i]) > 10: pop_back(memory[i])
#                delta <- delta + 2d                   # executes exactly twice: -d, +d
#
#            change[i] <- |h_i - h0|
#
#    return (h_w, h_m)

function mutual_best_response(
        hw_init::Float64, hm_init::Float64, theta::Float64, pw::AgentPayoffParams,
        pm::AgentPayoffParams, config::UtilityConfig; eps = 1.0e-3, max_sweeps = 100
    )
    hw = clamp(hw_init, 0.0, 1.0)
    hm = clamp(hm_init, 0.0, 1.0)
    for _ in 1:max_sweeps
        hw_new = best_response_1d(h -> individual_utility(h, hm, theta, pw, config))
        hm_new = best_response_1d(h -> individual_utility(h, hw_new, theta, pm, config))
        change = abs(hw_new - hw) + abs(hm_new - hm)
        hw = clamp(hw_new, 0, 1)
        hm = clamp(hm_new, 0, 1)
        change <= eps && break
    end
    return (hw, hm)
end

# Alias kept so the earlier stub name keeps resolving.
gauss_seidel(args...; kwargs...) = mutual_best_response(args...; kwargs...)

function choose_bundles(world)
    for (e, wage, working_time, transfer, conformism, preference, spouse) in Ark.Query(world, (Wage, WorkingTime, TransferToWoman, Conformism, PreferencePrivate, Spouse), with = Female)
        @inbounds for f in eachindex(e)

            wage_m, working_time_m, conformism_m, preference_m = Ark.get_components(world, spouse.entity, (Wage, WorkingTime, Conformism, PreferencePrivate))
            pw = AgentPayoffParams(
                wage_self = wage[f].current,
                wage_spouse = wage_m.current,
                alpha = preference[f].current,
                conformism = conformism[f].current,
                is_woman = true

            )

        end


    end
    return
end
