# choose_bundle(m,w,θ):
#    change[w] ← 1;  change[m] ← 1
#    memory[w] ← []; memory[m] ← []          # solver scratch, persists across sweeps
#
#    while change[w] + change[m] > ε:
#
#        for i in (w, m):                     # sequential (Gauss–Seidel), each sees
#                                             # the partner's latest h; order unspecified
#            h0 ← h_i
#            u0 ← U_i(h_i, h_j, θ)            # current-utility (reference value)
#
#            S ← 1
#            if memory[i] is non-empty:
#                S ← |sum(memory[w])| + |sum(memory[m])|
#
#            δ ← -d
#            while δ ≤ d:                     # only δ = -d and δ = +d ever run
#                while h_i + δ ∈ [0,1] and S ≠ 0:
#                    u' ← U_i(h_i + δ, h_j, θ)
#                    if u' - u0 ≤ 0: break    # requires strict improvement
#                    h_i ← clamp(h_i + δ, 0, 1)
#                    u0 ← u'
#                    push_front(memory[i], δ)
#                    if length(memory[i]) > 10: pop_back(memory[i])
#                δ ← δ + 2d                   # executes exactly twice: -d, +d
#
#            change[i] ← |h_i - h0|
#
#    return (h_w, h_m)

function choose_bundles(world)
  for (e,) in Ark.Query(world, (Spuse,), with=Female)
  end
  return
end
