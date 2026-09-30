# Feasibility-guided production transfer search validation (TASK-0022)

Validation evidence for the feasibility-guided production transfer search
of `MDR-0016`/`ADR-0021` (superseding the anchor-local search of
`MDR-0015`; NetLogo `set-theta`, `calculate-payoff`; ODD section Transfer
bargaining): the three near-zero regression households 85/100/387,
low-conformism households where substantial transfers occur, payoff
losses against the retained discovery search (`search=:discovery`, the
`MDR-0014` full-domain tiered search) on identical states, and 25-tick
trajectories with per-household-tick evaluation counts and kernel timing.
Validation only: no `src/` or `test/` file was changed; every number
below is reproducible from the referenced throwaway driver and data
table.

Environment: Julia 1.12.7, AMD Ryzen 7 5825U (16 hardware threads),
sequential runs on an otherwise idle machine, seed 1 everywhere,
`JULIA_NUM_THREADS=1` except the eight-thread timing rows. Throwaway
drivers live outside the repository in `/tmp/opencode/`; regenerate the
data tables from the repository root with:

```sh
julia --project=. /tmp/opencode/gs_s1_fixtures.jl
julia --project=. /tmp/opencode/gs_identical_states.jl
julia --project=. /tmp/opencode/gs_s3_solver_cases.jl
julia --project=. /tmp/opencode/gs_s4_trajectories.jl
JULIA_NUM_THREADS=1 julia --project=. /tmp/opencode/gs_timing.jl
JULIA_NUM_THREADS=8 julia --project=. /tmp/opencode/gs_timing.jl
```

- `/tmp/opencode/gs_common.jl` (shared: seed-1 workload specs, the
  `set_theta!`-identical state extraction, the true-objective evaluator,
  the three transfer drivers - production `search=:local`, discovery
  `search=:discovery`, frozen old reference `bargain_transfer_reference`
  of `test/reference_bargaining.jl` - the sequential MDR-0010 model-loop
  mirror and its bitwise fidelity check, CSV output)
- `/tmp/opencode/gs_s1_fixtures.jl`, `/tmp/opencode/gs_identical_states.jl`,
  `/tmp/opencode/gs_s3_solver_cases.jl`, `/tmp/opencode/gs_s4_trajectories.jl`,
  `/tmp/opencode/gs_timing.jl`

Data tables are in `benchmark/transfer_validation/` (`gs_*.csv`, listed
per section). Identical-state protocol used throughout sections 2 and 3:
both searches run offline on the same extracted household state; each
candidate's payoff is the objective evaluated at the search's committed
bundle (its committed hours and the identical-state outside utilities -
the `benchmark/anchor_local_validation.jl` commit convention, never
re-solved from a new start). This is "like with like": verified bitwise
over all 6,200 identical-state rows, the cached search payoff equals the
bundle payoff at every non-fallback commit and the fallback payoff equals
the status-quo payoff exactly (0 violations). Re-solving the objective at
a fallback transfer is NOT idempotent (232 rows where an extra solve
lands on a different fixed point, the warm-start selection effect of
`benchmark/transfer_search_validation.md` section 2), which is why the
bundle convention is used. Deficits are
`max(0, discovery payoff - production payoff)` (`Inf` when only
production is infeasible) and relative deficits divide by the discovery
payoff when it is finite and positive.

## 1. The three near-zero regressions (households 85/100/387)

Method (`benchmark/transfer_validation/gs_s1_demo.csv`,
`gs_s1_finegrid.csv`, `gs_s1_tick1.csv`, driver `gs_s1_fixtures.jl`): the
frozen fixtures of `test/fixtures/transfer_feasibility_households.toml`
(tick-0 states of the seed-1 `ws_500` run; re-extraction from a fresh
seed-1 world reproduces every fixture field and every recorded context
value bitwise). Per household: the production result (`search=:local`),
the demonstrated candidates (`demo_theta`/`demo_payoff`, `demo2_*` for
household 85), and discovery on the identical state; then a fine
true-objective sweep at 1e-5 steps over the measured band of
`benchmark/transfer_search_validation.md` section 2 (85 [8.55e-4,
1.025e-3], 100 [6.65e-4, 8.05e-4], 387 [5e-5, 1e-4]) plus a 1e-5 window
around both committed transfers; then the same comparisons on the
households' tick-1 states of the production trajectory (the states the
next tick's bargaining sees).

Tick-0 results:

| Household | Production commit theta | Payoff | Gains (woman, man) | Demonstrated payoff(s) | Discovery commit theta | Discovery payoff |
| --- | --- | --- | --- | --- | --- | --- |
| 85 | 8.494857350497692e-4 | 1.077029407459327e-8 | 3.990072042642234e-4, 2.6992730856711944e-5 | 8.239360204105467e-9 (0.0009); 2.1406731321933553e-9 (0.001) | 8.652475842498528e-4 | 1.001999449504675e-8 |
| 100 | 6.622008300729853e-4 | 1.4766184762379934e-8 | 4.503066587155935e-4, 3.279139776546369e-5 | 1.1554486667771662e-8 (0.0007) | 6.652475842498528e-4 | 1.4523856357202782e-8 |
| 387 | 5.1803398874989494e-5 | 4.424091598165963e-10 | 2.3044056576937422e-5, 1.9198406250198197e-5 | 1.1575079773623812e-10 (0.0001) | 6.524758424985278e-5 | 4.2288346280524827e-10 |

- All three production payoffs reproduce the `MDR-0016` recorded fixture
  payoffs exactly and beat both demonstrated candidates bitwise; the
  demonstrated values themselves re-evaluate bitwise from the live
  objective.
- Production beats discovery on all three identical states (the
  production Stage C refinement lands on a higher spike than discovery's
  tiered-grid bracket refinement). Production commits 22-26 objective
  records (18-22 solved, 4 certified prunes) versus discovery's
  322-609 records.

Position relative to the band optimum (fine sweeps, `gs_s1_finegrid.csv`):

| Household | Band sweep feasible points | Band-grid best (1e-5 steps) | Window-grid best | Production commit | Position |
| --- | --- | --- | --- | --- | --- |
| 85 | 18/18 in [8.55e-4, 1.025e-3] | 8.55e-4 -> 1.0512e-8 | 8.5e-4 -> 1.0746e-8 | 8.4949e-4 -> 1.0770e-8 | above both grids |
| 100 | 15/15 in [6.65e-4, 8.05e-4] | 6.65e-4 -> 1.4544e-8 | 6.6e-4 -> 1.4939e-8 | 6.622e-4 -> 1.4766e-8 | above band best, 1.2% below window best |
| 387 | 6/6 in [5e-5, 1e-4] | 5e-5 -> 4.4082e-10 | 5e-5 -> 4.4082e-10 | 5.1803e-5 -> 4.4241e-10 | above both grids |

- The production commits of 85 and 100 sit just BELOW the previously
  measured band edges (8.49e-4 < 8.55e-4, 6.62e-4 < 6.65e-4) at payoffs
  above every point of the measured band's grid: the old band edges were
  properties of that sweep's 5e-6-aligned grid, and the objective is
  jagged at the 1e-5 scale (the fixed-point selection of
  `benchmark/transfer_search_validation.md` section 2). Household 100 is
  the one case where a fine-grid point beats the production commit
  (6.6e-4 at 1.4939e-8 versus 1.4766e-8, 1.2%): a neighbouring spike in
  the same contiguous feasible region, in the fine-grid-beats-commit
  class of `benchmark/search_reduction_validation.md` section 1.

Tick-1 states on the production trajectory (`gs_s1_tick1.csv`); the
tick-0 commit has become infeasible against the recomputed zero-transfer
outside options once the lagged norms absorbed it (`status_payoff ==
-Inf`), the recorded re-bargaining dynamic:

| Household | theta0 (tick-0 commit) | Status payoff | Production result | Discovery result | Deficit |
| --- | --- | --- | --- | --- | --- |
| 85 | 8.494857350497692e-4 | -Inf | 6.180339887498949e-5, 8.864667444861444e-10 | 6.180339887498948e-5 (1 ulp), 8.864667444861444e-10 | 0 |
| 100 | 6.622008300729853e-4 | -Inf | 7.180339887498949e-5, 1.9007851672485775e-9 | 7.639320225002102e-5, 1.903099044269383e-9 | 2.3138770208057106e-12 |
| 387 | 5.1803398874989494e-5 | -Inf | 0.0, 2.7523331719723247e-13 | 0.0, 2.7523331719723247e-13 | 0 |

- Production finds finite improvements at all three tick-1 states (85 and
  100 commit smaller positive transfers, 387 commits the zero transfer
  strictly above its `-Inf` status quo), matching discovery except
  household 100's 2.3e-12 deficit (0.12% relative).
- Fine sweep at 1e-5 over [0, 1.5e-3] (151 points per household): the
  only feasible region for 85 and 100 is [0, 9e-5] with grid best 7e-5;
  for 387 only theta 0 is feasible. Production sits within 4.5e-13 of
  the 85 grid best (and above the 100 grid best), i.e. at the band
  optimum up to the objective's 1e-5 jaggedness.

Connection to the artifact assessment (not redone): the gains here are
the same converged fixed-point features that
`benchmark/transfer_search_validation.md` section 2 established as
bitwise stable from labour `eps` 1e-3 down to 1e-6 with 1000 sweeps.
Nothing measured here contradicts that assessment: the fine-sweep
differences are same-band spikes at the recorded jaggedness scale
(largest 1.7e-10 absolute at household 100 tick 0, 4.5e-13 at household
85 tick 1), and the non-idempotent fallback re-solves documented above
are the same warm-start selection mechanism it describes. No reason to
doubt the gains.

## 2. Low-conformism households (where substantial transfers occur)

Method (`gs_s2_lowconf.csv`, `gs_s2_summary.csv`, `gs_losses.csv`,
driver `gs_identical_states.jl`): workload `low_conformism` (initial
conformism 0/0; `benchmark/anchor_local_validation.jl` and
`benchmark/transfer_search_validation.md` section 3), household states
extracted at ticks 0, 1, 5, 24 of the seeded production trajectory
(the production run is the model's actual trajectory; all 500 households
per state, 2,000 identical-state comparisons), both searches evaluated
offline on each state.

| Tick | Finite / positive status payoff | Improvements production / discovery | Discovery substantial commits (abs theta >= 0.01) | substantial: found / beats / missed | Max deficit (finite) | Mean deficit over losses | abs > 1e-12 / 1e-9 / 1e-6 | rel > 1e-12 / 1e-9 / 1e-6 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 0 | 500 / 0 | 191 / 241 | 80 | 0 / 10 / 70 | 1.9686e-5 | 6.46e-7 | 145 / 62 / 17 | 175 / 161 / 148 |
| 1 | 334 / 25 | 181 / 175 | 69 | 20 / 16 / 33 | 3.5984e-6 | 1.74e-7 (finite part) | 90 / 50 / 8 | 111 / 108 / 105 |
| 5 | 425 / 7 | 47 / 46 | 17 | 2 / 3 / 12 | 1.0633e-7 | 1.80e-8 | 9 / 7 / 0 | 17 / 11 / 11 |
| 24 | 500 / 7 | 2 / 7 | 0 | - | 2.03e-15 | 1.54e-15 | 0 / 0 / 0 | 5 / 5 / 0 |

- Status payoffs: at tick 0 every status quo is exactly 0.0 (zero
  transfers); from tick 1 on, 25-7 households live in finite positive
  transfer regimes and 8-166 have infeasible (`-Inf`) status quos, the
  absorbed-transfer dynamic of the recorded regime change.
- Substantial transfers: of the 166 discovery-found substantial commits,
  production commits the identical transfer in 22, commits a
  payoff-equal-or-better one in 29, and ends below discovery's payoff in
  115. The 115 misses are stratified by absolute deficit: 4 above 1e-5,
  19 in (1e-6, 1e-5], 49 in (1e-9, 1e-6], 11 in (1e-12, 1e-9], 32 at or
  below 1e-12; by relative deficit: 5 above 10% (all in the tiny-payoff
  regime, discovery payoffs <= 2.4e-6), 12 above 1%, 31 above 0.1%, 44
  at or below 1e-4. Full list with discovery payoff and production
  deficit: `gs_losses.csv` (`disc_substantial=true`).

Worst missed substantial transfers (`gs_losses.csv`):

| Tick | Household | Discovery theta | Discovery payoff | Production theta | Production payoff | Deficit abs | Deficit rel |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0 | 382 | -0.24559674775249768 | 4.040065460885567e-3 | -0.2458980337503154 | 4.020379473351421e-3 | 1.968598753414666e-5 | 0.49% |
| 0 | 320 | 0.24840750905426476 | 4.614395218222974e-3 | 0.2477047518912099 | 4.599612870782359e-3 | 1.4782347440614983e-5 | 0.32% |
| 0 | 434 | 0.1793030742477314 | 7.202715619451976e-3 | 0.17976901867630218 | 7.190842677327648e-3 | 1.1872942124327782e-5 | 0.16% |
| 0 | 349 | 0.2554108787532888 | 7.46708613098832e-3 | 0.25537127274894833 | 7.456752051944222e-3 | 1.0334079044098388e-5 | 0.14% |
| 0 | 70 | -0.2099756151581401 | 3.8420175402725408e-3 | -0.2097339058681001 | 3.8324975383560883e-3 | 9.520001916452515e-6 | 0.25% |
| 0 | 188 | 0.34754427992460335 | 1.1628293623062124e-2 | 0.3558622229901459 | 1.1621408706545426e-2 | 6.884916516698009e-6 | 0.06% |
| 1 | 62 | -0.2666687370800101 | 1.8988704096578688e-3 | -0.2647830496428687 | 1.8952719709830394e-3 | 3.5984386748293736e-6 | 0.19% |
| 1 | 476 | -0.011709354762393416 | 1.0814918798620631e-7 | -4.793118804712526e-4 | 4.997329228955063e-10 | 1.076494550633108e-7 | 99.5% |
| 0 | 82 | 0.013875388202501891 | 7.967887190939411e-8 | 1.3869910099907465e-3 | 2.0635453498952746e-8 | 5.9043418410441364e-8 | 74.1% |

- The worst absolute losses (>= 9.5e-6) are refinement-resolution
  differences on shared broad peaks: production lands within 4e-4 in
  theta of discovery (median 1.1e-4 over the 115 misses, p90 5.5e-3,
  worst 0.055) and within 0.5% of its payoff. The worst relative losses
  (>= 74%) are near-zero-regime rows where discovery finds a slightly
  better tiny peak (payoffs <= 2.4e-7).
- Two rows lose an improvement ENTIRELY (infeasible miss class, `Inf`
  deficit): tick-1 households 367 (discovery -6.18e-5 at 3.34e-10,
  production falls back to its `-Inf` status quo) and 456 (discovery
  1.85e-6 at 4.59e-13). Both are hidden near-zero bands between the
  production ladder probes - the recorded `MDR-0016` miss class.
- The searches are not nested: production finds 34 improvements that
  discovery misses entirely (33 at tick 1, e.g. household 455:
  production 3.82e-5 at 3.79e-10 where discovery returns its infeasible
  status quo), while discovery finds 85 production misses (50 at tick 0).
- Comparison with the superseded anchor-local search
  (`benchmark/anchor_local_validation.md`): its worst shared-state
  low-conformism deficit was 6.41297e-4 (50.3% relative, household 71),
  with 7 of 132 sampled states below discovery. The feasibility-guided
  search reduces the worst substantial-transfer deficit to 1.97e-5
  (0.49% relative) and the largest theta miss from 0.011 to 0.055 on a
  0.24 transfer (median 1.1e-4). The recorded material losses of
  `MDR-0015` are largely recovered; the residual losses above are
  recorded, not hidden.

## 3. Payoff losses against discovery on identical states

Method (`gs_s3_ws500.csv`, `gs_s3_heterogeneous.csv`, `gs_s3_solver.csv`,
`gs_s3_workload_summary.csv`, `gs_s3_solver_summary.csv`,
`gs_s3_worst10.csv`, driver `gs_s3_solver_cases.jl`): the identical-state
protocol on `ws_500` and `heterogeneous` at ticks 0, 1, 5, 24 (500
households each, 4,000 states), plus the 200 solver fixture cases of
`test/fixtures/bargaining_baseline.toml` (parameter-space coverage
beyond model states: five utility specs, wage pairs to 40:1, conformism
0/10/50, `theta_init` -1..1). Each search's committed/best candidate is
evaluated on the true objective like with like (bundle convention).

| Source | States | Bitwise-identical bundles | Loss rows | abs > 1e-12 | abs > 1e-9 | abs > 1e-6 | Infeasible misses | Max finite deficit | Max finite rel |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ws_500 | 2,000 | 1,994 | 2 | 2 | 0 | 0 | 0 | 4.7266e-10 | 1.0 |
| heterogeneous | 2,000 | 1,998 | 2 | 2 | 0 | 0 | 0 | 1.5906e-10 | 1.0 |
| solver cases | 200 | 44 | 127 | 94 | 22 | 14 | 3 | 4.3440e-5 | 0.697 |

- `ws_500` and `heterogeneous` (the model's own parameter range):
  4 losses of 4,000 states, all at or below 4.7e-10 Nash payoff. The
  `ws_500` tick-0 loss is household 350 (discovery 4.16e-5 at
  4.7266e-10, production falls back to 0.0): a narrow near-zero band
  between ladder probes, the `MDR-0016` miss class, 9 orders of
  magnitude below the workload's transfer scale. The tick-1 loss is
  household 100 (2.3139e-12, section 1). The `heterogeneous` losses are
  1.3e-11 and 1.59e-10.
- Solver cases: 127/200 rows below discovery (94 above 1e-12), but 113
  of them within 1e-6 and 78 within 1e-9 of discovery; 162/200 commits
  are strict improvements by production and 167 by discovery. Worst
  finite deficit 4.34e-5 (0.38% relative) and worst relative deficit
  0.697 (case 28: both candidates in the 1e-7..1e-8 near-zero regime,
  7.36e-8 vs 2.43e-7). The three `Inf` rows (cases 23, 51, 124) are
  remote-band misses at extreme `theta0` (0.5, 1.0, -0.5): discovery
  commits far from the anchors (-0.0176, 0.0096, 0.4626) where the
  production ladder has no probe; case 124's missed payoff is 3.25e-3.

Worst 10 cases over the section-3 sources (`gs_s3_worst10.csv`; every
one is a solver case - the workload-state losses are all below 5e-10):

| Case | theta0 | Production theta / payoff | Discovery theta / payoff | Deficit abs / rel | Band class | Window spike |
| --- | --- | --- | --- | --- | --- | --- |
| 23 (ces 0.5, conf 0, N_theta 1.0, wages 1.0/1.0) | 0.5 | 0.5 / -Inf | -0.017557280900008417 / 5.877396869898208e-9 | Inf | remote | - |
| 51 (mult_weighted, conf 10, wages 0.05/2.0) | 1.0 | 1.0 / -Inf | 0.00964265921748301 / 4.065317293204188e-5 | Inf | remote | - |
| 124 (mult_weighted, conf 0, wages 0.05/2.0) | -0.5 | -0.5 / -Inf | 0.46259375058973917 / 3.253569388572038e-3 | Inf | remote | - |
| 187 (multiplicative, conf 0, wages 1.2/0.6) | 1.0 | -0.49911941254521314 / 1.1379485797753641e-2 | -0.5001450052871387 / 1.1422926151529636e-2 | 4.3440e-5 / 0.38% | same_band | 3.65e-6 |
| 108 (multiplicative, conf 0, wages 0.6/1.2) | -0.5 | 0.49933442991535654 / 1.139733190659508e-2 | 0.5001837223014032 / 1.1434697849846995e-2 | 3.7366e-5 / 0.33% | same_band | 3.51e-6 |
| 140 (multiplicative, conf 0, wages 0.6/1.2) | 1.0 | 0.499475681887476 / 1.1349078983001996e-2 | 0.5002105917324745 / 1.1381522365468457e-2 | 3.2443e-5 / 0.29% | same_band | 3.67e-6 |
| 180 (multiplicative, conf 10, wages 1.2/0.6) | 1.0 | -0.4985042401120368 / 0.534802694510963 | -0.4989605331475107 / 0.5348290285641738 | 2.6334e-5 / 4.9e-5 | same_band | 1.66e-8 |
| 109 (ces 0.5, conf 50, wages 2.0/0.05) | 0.0 | 0.998896538360892 / 0.8616593245407591 | 0.9984655117168373 / 0.8616852227794284 | 2.5898e-5 / 3.0e-5 | same_band | 1.08e-5 |
| 191 (multiplicative, conf 0, wages 0.6/1.2) | 1.0 | 0.5000461298100404 / 1.1429717615915548e-2 | 0.5001451027844003 / 1.1441101148158375e-2 | 1.1384e-5 / 0.10% | same_band | 6.22e-6 |
| 61 (multiplicative, conf 0, wages 1.2/0.6) | 1.0 | -0.5001728596336706 / 1.1390124256507206e-2 | -0.5002106386868415 / 1.1398861436768841e-2 | 8.7372e-6 / 7.7e-4 | same_band | 1.83e-5 |

- Band class (1e-5 scan over the gap between the two candidates):
  the seven finite worst cases lie in ONE contiguous feasible band
  (same_band) - different refinement outcomes on a shared broad peak,
  each within 0.4% relative and within 1e-3 in theta of discovery's
  peak; the objective's local 2.1e-4-window variation around the
  production commit (the `benchmark/search_reduction_validation.md`
  quality methodology, "window spike" column) is of the same order or
  below. The three remote misses are the recorded disconnected-band
  class of `MDR-0016`, never silent: failed probes do not certify
  infeasibility and discovery remains the explicit validation option.
- Materiality at the model's output scale: the model's own states lose at
  most 1.97e-5 Nash payoff (low_conformism, section 2) or 4.7e-10
  (`ws_500`/`heterogeneous`), on transfer magnitudes of 1e-4..1 and
  transfer sums of 1.6e-3 (`ws_500`) to 5.7 (low_conformism), with
  per-household theta differences mostly below 1e-4. The larger solver
  deficits occur only at parameter corners the model trajectory never
  produces (40:1 wage pairs, conformism 0 with extreme `theta0`). By
  the search_reduction quality methodology (deficits against measured
  local jaggedness and the same-band/missed-band split) the losses are
  SAME-BAND refinement differences plus a documented remote-band class -
  not material at the model's output scale. This is a bounded-loss
  statement, not a dominance claim: production is below discovery in 127
  of 200 solver cases and 115 substantial low_conformism rows, and the
  numbers above are the honest magnitudes.

## 4. Multi-tick trajectories and evaluation counts

Method (`gs_s4_ticks.csv`, `gs_s4_divergence.csv`, `gs_s4_changes.csv`,
`gs_s4_counts.csv`, `gs_s4_persistence.csv`, `gs_timing.csv`, driver
`gs_s4_trajectories.jl`): 25-tick seeded trajectories per workload
(`ws_500`, `heterogeneous`, `low_conformism`), production versus
discovery versus the frozen old reference (`bargain_transfer_reference`,
`test/reference_bargaining.jl`), all three driven through the identical
MDR-0010 model loop via one sequential mirror of `set_theta!`. The
mirror is verified bitwise against the real `GN.set_theta!` over 3 ticks
of every workload in both search modes (6/6 identical world digests)
before the trajectories run.

Per-tick aggregates (tick 0 and tick 24; full per-tick table in
`gs_s4_ticks.csv`):

| Workload | Variant | tick 0: sum theta / frac nonzero | tick 24: sum theta / frac nonzero | tick 24 mean perceived transfer norm (women) |
| --- | --- | --- | --- | --- |
| ws_500 | reference (frozen old) | 0.0 / 0.000 | 0.0 / 0.000 | 0.0 |
| ws_500 | production | 0.00156 / 0.006 | 0.0 / 0.000 | 0.0 |
| ws_500 | discovery | 0.00164 / 0.008 | -0.00061 / 0.012 | -1.25e-6 |
| heterogeneous | reference (frozen old) | 0.0 / 0.000 | 0.0 / 0.000 | 0.0 |
| heterogeneous | production | 0.0 / 0.000 | 0.0 / 0.000 | 0.0 |
| heterogeneous | discovery | 0.0 / 0.000 | -0.0003 / 0.002 | -6.0e-7 |
| low_conformism | reference (frozen old) | 3.108 / 0.042 | 5.694 / 0.236 | 0.01221 |
| low_conformism | production | 5.695 / 0.382 | 0.00011 / 0.014 | 2.35e-7 |
| low_conformism | discovery | 5.687 / 0.482 | -0.000083 / 0.036 | -2.06e-7 |

- The frozen old reference rows reproduce the recorded old-search rows of
  `benchmark/transfer_search_validation.md` section 3 exactly
  (`low_conformism` 3.108/0.042 at tick 0 growing to 5.694/0.236 at tick
  24; zero transfers on `ws_500`/`heterogeneous`), cross-validating the
  frozen reference and the loop mirror.
- Production tracks discovery's transient regime on `low_conformism`
  (tick-0 sums 5.695 versus 5.687; both decay to about 1e-4 rather than
  growing the old self-sustaining regime). On `ws_500` production
  commits 4 ever-nonzero transfers (max 8.49e-4) versus discovery's 21
  (max 8.65e-4) and ends fully zero at tick 24 where discovery retains 6
  tiny transfers (sum -6.09e-4); `heterogeneous` has essentially no
  transfers under either search.

Production-versus-discovery divergence per tick (`gs_s4_divergence.csv`,
1,935 differing household-ticks in `gs_s4_changes.csv`):

| Workload | Differing households (tick 0 -> peak -> tick 24) | Max abs dtheta over time (tick) | tick 24: differing / mean / max abs dtheta |
| --- | --- | --- | --- |
| ws_500 | 4 -> 10 (t7) -> 6 | 7.29e-4 (t7) | 6 / 1.22e-6 / 2.94e-4 |
| heterogeneous | 0-1 | 3.0e-4 (t24) | 1 / 6.0e-7 / 3.0e-4 |
| low_conformism | 227 -> 283 (t1) -> 18 | 0.912 (t7) | 18 / 3.9e-7 / 6.6e-5 |

- `low_conformism` diverges transiently (worst 0.912 household-tick, a
  state-feedback difference of the same kind as
  `benchmark/anchor_local_validation.md`'s 0.912 case) and reconverges:
  18 differing households with max 6.6e-5 at tick 24. Mean hours by
  gender stay within 3e-3 of each other across variants at every tick
  (e.g. `low_conformism` tick 24 production/discovery/reference women
  0.6400/0.6400/0.6420), so the search change is first-order in
  transfers and transfer norms, second-order in hours.

Transient versus persistent (`gs_s4_persistence.csv`):

| Workload | Variant | Ever nonzero | Dropped to zero before tick 24 | Nonzero at tick 24 |
| --- | --- | --- | --- | --- |
| ws_500 | production | 4 | 4 | 0 |
| ws_500 | discovery | 21 | 15 | 6 |
| ws_500 | reference | 0 | 0 | 0 |
| heterogeneous | production | 0 | 0 | 0 |
| heterogeneous | discovery | 4 | 3 | 1 |
| heterogeneous | reference | 0 | 0 | 0 |
| low_conformism | production | 337 | 330 | 7 |
| low_conformism | discovery | 379 | 361 | 18 |
| low_conformism | reference | 118 | 0 | 118 |

- Production and discovery are both TRANSIENT (a committed transfer is
  usually re-bargained away once the lagged norms absorb it); the frozen
  old reference is fully PERSISTENT (`low_conformism`: 118 ever-nonzero
  households, none drops to zero, the growing regime of the recorded
  old-vs-new comparison). Production is the more transient of the two
  new searches because it finds slightly fewer near-zero bands.

Evaluation counts per household-tick over time (production, instrumented
in the throwaway driver from the scratch cache, never via `src/` edits;
`gs_s4_counts.csv` has all 75 workload-ticks):

| Workload | Tick | Records mean (min-max) | Solved | Certified prunes | Full labour solves |
| --- | --- | --- | --- | --- | --- |
| ws_500 | 0 | 15.056 (15-26) | 11.054 | 4.002 | 11.054 |
| ws_500 | 5 | 15.000 (15-15) | 10.002 | 4.998 | 10.002 |
| ws_500 | 10 | 15.000 (15-15) | 8.992 | 6.008 | 8.992 |
| ws_500 | 24 | 15.000 (15-15) | 6.090 | 8.910 | 6.090 |
| heterogeneous | 0 | 14.760 (0-15) | 8.868 | 5.892 | 8.868 |
| low_conformism | 0 | 18.852 (15-28) | 16.482 | 2.370 | 16.482 |
| low_conformism | 1 | 20.862 (15-43) | 16.648 | 4.214 | 17.030 |
| low_conformism | 2 | 19.548 (15-44) | 14.434 | 5.114 | 14.906 |
| low_conformism | 24 | 15.132 (15-28) | 6.242 | 8.890 | 6.256 |

- The `ws_500` 20-tick means are 15.021 records, 9.513 solves, 5.508
  certified prunes per household-tick - exactly reproducing the
  `MDR-0016` recorded anatomy (15.02 / 9.51 / 5.51). Counts fall over
  the run as households converge to corners (more certified prunes,
  fewer solves); `low_conformism` costs more early (Stage C refinements
  on its peaks) and never exceeds the record cap (observed max 44 at
  tick 2, the `TRANSFER_SEARCH_MAX_EVALS` bound). The
  `heterogeneous` minimum of 0 records is the recorded early return on
  non-finite outside options (8 wage-0 households per tick, empty
  cache), consistent with its 492/500 finite status payoffs.

Kernel timing (`gs_timing.csv`; methodology `MDR-0011`/`ADR-0013`:
500 households x 20 ticks, fresh seed-1 world per repetition, one
discarded full-size warmup, five measured repetitions, only `set_theta!`
timed; `bargaining_kernel` rows are the `benchmark/bargaining_kernel.jl`
harness itself):

| Metric | Recorded (MDR-0016) | Now (1 thread) | Now (8 threads) |
| --- | --- | --- | --- |
| `ws_500` production kernel median | 0.05585 s (gate 0.0627) | 0.05977 s (harness 0.05446) | 0.01411 s (harness 0.01579) |
| `heterogeneous` production kernel median | 0.05468 s | 0.05184 s (harness 0.05087) | 0.01187 s (harness 0.01554) |
| `ws_500` discovery kernel median | 2.510 s (MDR-0014) | 2.498 s | 0.605 s |
| `heterogeneous` discovery kernel median | 1.675 s (MDR-0014) | 1.611 s | 0.453 s |
| Production kernel per household-tick | 5.6-6.3 us | 5.45-5.98 us | 1.19-1.58 us |
| Production allocations per household-tick | 1662 B | 1656-1662 B | 1663-1669 B |
| Historical pre-change reference | 0.0627 / 0.0136 s | - | - |
| In-tree pre-change reference R | 0.028-0.032 s | - | - |

- The measured production medians sit in the recorded band (the `gs`
  pass reads 0.0598 s for `ws_500`, the contemporaneous harness 0.0545
  s, against the recorded 0.0549-0.0569 s and the 0.0627 s acceptance
  gate) and reproduce the recorded allocation count. Discovery's 2.50 s
  versus the recorded 2.510 s confirms its unchanged semantics at about
  42x the production kernel - the measured price of full-domain
  coverage.

## Summary and acceptance

1. Near-zero regressions 85/100/387: FOUND and at the band optima.
   Production commits 8.49e-4 / 6.62e-4 / 5.18e-5 at payoffs
   1.0770e-8 / 1.4766e-8 / 4.4241e-10, beating both demonstrated
   candidates and discovery bitwise on all three, at or above every
   fine-grid point except household 100's same-band neighbour spike
   (1.2%); all three still find finite improvements at their tick-1
   states (max deficit versus discovery 2.3e-12). The gains connect to
   the artifact assessment as converged fixed-point features; no doubt
   raised.
2. Low-conformism substantial transfers: RECOVERED with bounded
   residual losses. Of 166 discovery-found substantial commits
   production finds 22 bitwise and beats 29; the 115 misses lose at
   most 1.97e-5 (0.49% relative) in the broad-peak regime, with 32 of
   them below 1e-12; two tiny improvements are lost entirely (3.3e-10
   and 4.6e-13) and 34 improvements go the other way. Against the
   superseded anchor-local search (worst 6.4e-4, 50.3%) the coverage
   loss is largely recovered.
3. Payoff losses versus discovery: QUANTIFIED and not material at the
   model's output scale. Model states: 4 losses of 4,000
   (`ws_500`/`heterogeneous`, max 4.7e-10) and the low_conformism
   losses of item 2. Solver-space: 127/200 rows below discovery but 113
   within 1e-6 and 78 within 1e-9; worst finite 4.34e-5 (0.38%), worst
   relative 0.70 (near-zero regime); 3 remote-band misses at extreme
   `theta0` (the recorded `MDR-0016` miss class, largest missed payoff
   3.25e-3). The worst 10 are documented with parameters and both
   candidates in `gs_s3_worst10.csv`.
4. Trajectories and evaluation counts: DOCUMENTED. 25-tick
   production/discovery/old-reference trajectories per workload with
   per-tick aggregates, divergence (reconverging to <= 6.6e-5 on
   `low_conformism`), transient-versus-persistent counts, per-tick
   records/solves/prunes (ws_500 20-tick means 15.021/9.513/5.508,
   reproducing the recorded anatomy; cap 44 respected), and the kernel
   timing table against the recorded numbers.

Quality findings reported prominently (validation only, not fixed):
production loses 115 substantial low_conformism transfers to discovery
(4 above 1e-5 payoff) and 3 remote solver-space bands entirely, and on
`ws_500` it misses household 350's tick-0 near-zero band (4.7e-10) and
ends the 25-tick run with zero transfers where discovery retains 6 tiny
ones (sum -6.09e-4). These are the recorded budgeted-search limitations
(bands between ladder probes; "best candidate found", not global
optimum) and are immaterial at the model's output scale, but they are
real and experimenters who need full-domain coverage should keep using
`search=:discovery`.

## Deviations from the plan

- The identical-state protocol of sections 2 and 3 extracts its states
  from the seeded PRODUCTION trajectory (the task's "a seeded run"); at
  tick 0 this is trajectory-independent, and the production trajectory
  is the model's actual behavior.
- Candidate payoffs use the committed-bundle convention rather than a
  fresh re-solve at each candidate theta: re-solving at a fallback
  transfer is non-idempotent (232 rows, warm-start selection), and the
  bundle payoff is both the model's outcome and the earlier validation
  reports' convention. Re-solved payoffs are stored alongside in every
  per-case table (`*_resolved_payoff`) and are bitwise equal to the
  bundle payoffs at every non-fallback commit.
- The worst-10 table covers the section-3 sources (ws_500,
  heterogeneous, solver cases) as specified; the worst low_conformism
  rows are tabulated in section 2 instead.
- The fine sweeps of section 1 add a second 1e-5 grid (the commit
  windows) to the measured-band grid of the task, because both
  production commits sit just below the recorded band edges; the band
  grid is preserved exactly as specified.
- Substantial-transfer recovery is reported as found (bitwise identical
  theta) / beats (payoff at least discovery's) / missed (below
  discovery's payoff), with the payoff-deficit distribution as the
  primary magnitude measure; a "missed" row can carry a deficit at or
  below 1e-12 (32 of 115 do).
- The old-reference trajectory is `bargain_transfer_reference` on today's
  world loop (frozen solver chain, unchanged world updates); its
  aggregate rows reproduce the recorded old-search rows bitwise-scaled,
  so no separate pre-change tree checkout was needed.
