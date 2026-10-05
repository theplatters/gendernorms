# Zero-transfer search diagnosis

Investigation on 2026-09-29 of `TASK-0014`, under the semantics in
`MDR-0002` and `MDR-0005`. Sources: ODD sections Labour best response
and Transfer bargaining; NetLogo `set-theta`, `choose-bundle`, and
`calculate-payoff`. This records evidence, not a solver change.

## Root cause

The previous claim that the Nash objective is finite only at exactly
zero is false. All sampled values being infeasible does not establish
that all nonzero transfers are infeasible.

The unseeded Brent transfer search begins at approximately -0.236068
and +0.236068. When every sample returns `-Inf`, its internal minimized
values are all `Inf`; the `fu <= fx` tie branch repeatedly moves right.
Its 17 samples on the observed all-infeasible path are:

```
-0.2360679774997898, 0.23606797749978958, 0.5278640450004205,
0.708203932499369, 0.8196601125010514, 0.8885438199983176,
0.931116292502734, 0.9574275274955837, 0.9736887650071504,
0.9837387624884334, 0.9899500025187171, 0.9937887599697164,
0.9961612425490008, 0.9976275174207156, 0.9986275174207156,
-1.0, 1.0
```

None samples the interior near zero. Brent is a local scalar optimizer,
not a feasibility-discovery or global-search algorithm. Its tolerance
does not guarantee that intervals of that width are examined. The
separately evaluated status quo supplies a fallback but does not seed
the transfer search. This is the missed-feasible-band limitation already
acknowledged by `MDR-0005`, now reproduced on the benchmark population.

## Population evidence

Julia 1.12.7, seed 1, 500 agents/gender, Watts-Strogatz with two
neighbors per side and rewiring 0.1, CES beta 0.5, other package defaults.
For each household, compute the original outside options and status-quo
hours; evaluate `equilibrium_payoff` directly (bypassing the pruning
certificate) on `-0.02:0.0001:0.02`. Tick 0 means before the first tick;
later states follow the existing model trajectory.

| State | Households with positive grid payoff | Positive payoff at -0.001 or +0.001 |
| --- | --- | --- |
| Initial state | 3 / 500 | 1 / 500 |
| After one tick | 0 / 500 | 0 / 500 |
| After five ticks | 0 / 500 | 0 / 500 |

At initialization, women at positions 85, 100, and 387 in
`SocialNetwork.women_entities` have positive sampled payoffs at theta
0.0009, 0.0007, and 0.0001, respectively. Household 85 also has payoff
2.1406731321933553e-9 at theta 0.001. All still commit zero under the
current search. These are sampled values, not proven global maxima.

Control: set every agent's `Conformism.amount` to zero immediately
after the same setup, retaining all other draws and configuration.
At initialization 226 / 500 households have positive grid payoffs;
73 / 500 have positive payoffs at -0.001 or +0.001. This supports a
substantial role for conformity in suppressing the feasible region.
It does not prove economic uniqueness or eliminate numerical artifacts
from the finite-tolerance labour solver.

Zero initial transfers also imply zero initial transfer norms: setup
uses a standard deviation proportional to `initial_transfer`, so its
default zero produces no dispersion. The transfer norm penalty is then
`-conformism * w_transfer * theta^2`. Both partners must beat their
zero-transfer outside utilities; a payer's material loss and the norm
penalty make large sampled transfers unattractive. Falling back to zero
keeps subsequent lagged transfer norms at zero.

## Minimal counterexample from household 100

Run with `julia --project=.`. The parameters below are the recorded
initial household, not an invented out-of-regime solver input. The
snippet is historical: its last line reproduces the superseded search
of `MDR-0005`, one unseeded `maximize_1d` (Brent) run over `[-1, 1]`
with the search tolerance `TRANSFER_TOL = 1.0e-3` that `MDR-0012`
removed (its value folds into `TRANSFER_COARSE_STEP`). The
`maximize_1d` Brent core is unchanged, so the line still runs against
current code and still shows the OLD search failing (construction lines
migrated to the post-`ADR-0029` keyword form, values unchanged); the superseded
search driver also survives frozen as `bargain_transfer_reference` with
its local `TRANSFER_TOL` in `test/reference_bargaining.jl`.

```julia
using GenderNorms
G = GenderNorms
pw = G.AgentPayoffParams{G.Female}(; wage_self=1.076522981086081, wage_spouse=1.2622098937756323,
    alpha=0.6807684879583694, conformism=7.364448780533483, N_h=0.36, N_theta=0.0, N_h_spouse=0.77)
pm = G.AgentPayoffParams{G.Male}(; wage_self=1.2622098937756323, wage_spouse=1.076522981086081,
    alpha=0.25119563157565356, conformism=9.829866291370688, N_h=0.77, N_theta=0.0, N_h_spouse=0.36)
config = G.UtilityConfig()
hw, hm = 0.4260828134491813, 0.7428832411904329
uw, um = 0.5447587065544779, 0.8152834480045269
objective(t) = first(G.equilibrium_payoff(t, hw, hm, uw, um, pw, pm, config))
@show objective(0.0)       # 0.0
@show objective(0.0007)    # 1.1554486667771662e-8
# 1.0e-3 is the historical (pre-`MDR-0012`, superseded) search
# tolerance `TRANSFER_TOL` of `MDR-0005`, used here to reproduce the
# original miss.
@show G.maximize_1d(objective, -1.0, 1.0, 1.0e-3) # NaN
```

The positive objective is much smaller than ordinary utility levels.
Its robustness to tighter labour convergence needs separate testing:
this demonstrates a missed positive value of the implemented objective,
not an exact mathematical equilibrium with proven gains from trade.

## NetLogo comparison and next decision

NetLogo `set-theta` starts from the current transfer and probes +0.001
and -0.001, rather than beginning at +/-0.236. It can therefore examine
the region Julia misses. A full matched-state NetLogo run is still
needed: NetLogo also rounds utilities to eight decimals, uses a
discrete labour search, randomizes partner update order, and mutates
current hours during `choose-bundle` (search-history-dependent starts).
The positive Julia payoff at +0.001 is not proof of a NetLogo outcome.

Any change to feasible-point discovery, bracketing, or status-quo-local
search changes recorded solver behavior and needs a successor MDR to
`MDR-0005`. Keep `TASK-0014` open for this decision and the matched-state
reference comparison. Do not encode zero transfer as a model invariant.

## Correction implemented

The successor record is `MDR-0012` (superseding `MDR-0005`, with
`ADR-0016`): `bargain_transfer` now runs a staged feasibility-discovery
search (anchors, anchor-neighbourhood grids at 1.0e-4, the 1.0e-3
coarse grid, and bounded refinement of sampled weak local maxima) and
commits the demonstrated bands of households 85, 100, and 387
(regression fixtures in `test/fixtures/transfer_feasibility_households.toml`).
The findings above stay as recorded evidence; the matched-state NetLogo
comparison, the labour-tolerance artifact assessment of the tiny gains,
and search-cost reduction remain open under `TASK-0014`.

Follow-up: the validation package
`benchmark/transfer_search_validation.md` closes the matched-state
NetLogo comparison and the labour-tolerance artifact assessment and
measures the search cost; its NetLogo probe drives the shipped
`set-theta` on states whose parameters match households 85, 100, and
387 exactly. Search-cost reduction and recording the comparison
outcome as an MDR remain open under `TASK-0014`.
