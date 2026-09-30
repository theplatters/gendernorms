# Solver equivalence validation (Stage 2, TASK-0018/0019)

Validation evidence for the prepared best-response objective and the
`CES` `beta == 0.5` sqrt/square material specialization of `MDR-0013`
(superseding `MDR-0012`): the same-state old-versus-new equivalence
protocol of that record, its measured deltas, the changed-commit
assessment, and the performance measurements. Validation only: the
recorded arithmetic changes were implemented in
`src/resources/utility_functions.jl` and
`src/systems/household_bargaining.jl`; this report establishes
equivalence and documents the change.

Environment: Julia 1.12.7, AMD Ryzen 7 5825U (16 hardware threads),
sequential runs on an otherwise idle machine, seed 1 everywhere. Old
arithmetic = the frozen chain of `test/reference_bargaining.jl` (the
bitwise pre-Stage-2 objective, verified bitwise against the fixtures
by `test/test_bargaining_equivalence.jl`); new arithmetic = the
package. Throwaway driver scripts live outside the repository in
`/tmp/opencode/` (`stage2_common.jl`, `stage2_s1_equiv.jl`,
`stage2_s23_grid.jl`, `stage2_s4_multitick.jl`, `stage2_counts.jl`,
`stage2_profile.jl`, `stage2_ab.jl`, `stage2_fixture_diag.jl`,
`stage2_attrib.jl`). Data tables are in
`benchmark/transfer_validation/st2_*.csv`.

## 0. Shipped variants and measured-and-dropped variants

Item 1 (prepared best-response objective) was implemented in two
variants plus one hybrid and measured at the evaluation-kernel level
(`stage2_ab.jl`, identical hoisted constants, alternating min-of-5
repetitions) and end to end (`stage2_profile.jl`, solve cost):

| Variant | eval kernel | solve (near-eq start) | arithmetic |
| --- | --- | --- | --- |
| old (baseline) | 55 ns (`individual_utility`) | 1717 ns | - |
| + CES sqrt/square only | 12 ns | 483 ns | validated-equivalent |
| exact (1a, shipped) | 9.8 ns | 463 ns | bitwise outside CES `beta == 0.5` |
| hybrid (payer-x exact, Q/norm regrouped) | 8.9 ns | not shipped | ulp-level |
| regrouped (1b) | 7.9 ns | 449 ns | ulp-level |

Shipped: the exact variant `1a` plus the `CES` `beta == 0.5`
sqrt/square `material` specialization. The regrouped forms are
dropped: their solve-level gain over `1a` is about 3 percent while
they introduce two demonstrated divergences (see `MDR-0013`): the
regrouped payer `x = A * h` flips the `x <= 0` guard trigger in
subnormal-product corners (constructed counterexample: `wage_self =
1e-323`, `h = 0.6`, `1 - theta = 0.5` gives exactly `x = 0`, `-Inf`
in the old grouping and `x = 5e-324`, feasible, in the regrouped
one), and the regrouped `Q`/norm grouping flipped one zero-gain
knife-edge commit in the fixture sample (solver case 116: old commits
theta 0 with payoff exactly 0.0, regrouped falls back to theta -1,
reference payoff `-Inf` - outside the accepted changed-commit bar).
Under the exact grouping the case-116 chain is bitwise identical and
every guard trigger is preserved exactly on every input; the `Q`
trigger analysis for the record: for hours in `[0, 1]` both
subtraction orders compute `Q > 0` except at `h == h_spouse == 1`
where both are exactly 0 (the guard corner), so the regrouped `Q`
could not have flipped its guard either.

## 1. Same-state old-versus-new comparison

Method (`stage2_s1_equiv.jl`, table
`benchmark/transfer_validation/st2_s1_commits.csv`): 428 identical
household states - the 200 solver fixture cases of
`test/fixtures/bargaining_baseline.toml` (all four `UtilitySpec`s,
`CES` betas 0.2/0.5/1.5, zero wages, `alpha` 0/1, bracket-endpoint
transfers), the three fixture households
85/100/387, and 25 sampled households of each of `ws_500`,
`heterogeneous`, `low_conformism` at ticks 0, 1, and 5 - evaluated
with both chains: `individual_utility` on the 11x11
`(h_self, h_spouse)` grid for both partners at 9 thetas per state,
`mutual_best_response` fixed points from the identical warm start, the
gains at each chain's own fixed point, and `bargain_transfer`
(old-arithmetic staged search = the frozen `MDR-0012` search over the
frozen chain vs the package).

| Check | Count | Result |
| --- | --- | --- |
| `individual_utility` finite pairs compared | 761,919 of 932,184 | see per-bucket deltas below |
| infeasibility-sign flips (finite vs `-Inf`/`NaN`) | 932,184 evaluations | 0 |
| `mutual_best_response` fixed points | 3,852 runs | per-bucket deltas below |
| gains at own fixed points | 6,732 compared | 0 sign flips; max abs delta 5.2e-13 |
| commits bitwise identical | 428 | 397 |
| commits changed | 428 | 31 (all `CES` `beta == 0.5`) |

Per-bucket deltas (max over the sample; p99 in parentheses):

| Bucket | utility abs | utility rel | solver hours |
| --- | --- | --- | --- |
| additive | 0.0 (0.0) | 0.0 | 0.0 |
| ces beta=0.2 | 0.0 (0.0) | 0.0 | 0.0 |
| ces beta=0.5 | 1.11e-15 (2.2e-16) | 1.15e-15 | 9.6e-13 (1.7e-14) |
| multiplicative | 0.0 (0.0) | 0.0 | 0.0 |
| multiplicative_weighted | 0.0 (0.0) | 0.0 | 0.0 |

Every spec except `CES` `beta == 0.5` is bitwise identical (max delta
exactly 0.0); the sqrt/square specialization moves values by at most
two ulps.

Changed commits (all 31 rows in `st2_s1_commits.csv`): 25 differ only
in solved hours (max 4.0e-13), 6 differ in theta by at most 3.7e-12
(solver cases 2, 3, 6, 8, 31, 142) with reference-evaluated payoff
deltas at most 2.9e-15. Every one is Brent-refinement jitter: the
theta displacement is at least six orders of magnitude below one
local-grid step (1e-4) and below the refinement tolerance (1e-5), the
payoff deltas are far inside the objective's measured jaggedness
(same-band noise spikes up to 2.97e-9 in the
`benchmark/transfer_search_validation.md` section-1 sample), and the
feasible band is unchanged. No changed commit outside the accepted
bar occurred.

Fixture-diagnostics check (`stage2_fixture_diag.jl`): over the 200
solver cases, live-versus-frozen-reference comparisons of the
unseeded-Brent diagnostics give 0 branch-label flips, 0
status-finite/maximizer-finite flips, 4 fixed-point mismatches (ulp
level), and 8 moved unseeded-Brent maximizers (the recorded `best_*`
fields of the fixture describe that jagged maximizer; its payoff moves
by at most 2.0e-15). The frozen reference reproduces the fixture
bitwise in every case.

## 2. Fine-grid solution quality (0/132 criterion)

Method (`stage2_s23_grid.jl`, table `st2_s2_finegrid.csv`): the
section-1 protocol of `benchmark/transfer_search_validation.md` on
the new solver - ws_500 households `1:12:493` plus 100 and 387 at
ticks 0, 1, and 5, committed result vs the maximum of the same
objective (same status-quo warm start, certificate bypassed) on a
finer grid (1e-4 over +/-0.02 around 0 and `theta0`, 2.5e-4 over
`[-1, 1]`, about 8,400 points per household-state).

| State | Household-states | Fine grid beats committed | Committed equals fine max | Committed beats fine max | Max fine-minus-committed | Max theta distance |
| --- | --- | --- | --- | --- | --- | --- |
| ticks 0/1/5 pooled | 132 | 0 | 128 | 4 | 0.0 | 3.48e-5 |

Identical to the `MDR-0012` criterion (0/132, same-band noise spikes
within one local-grid step).

## 3. Demonstrated households 85/100/387

Method (`stage2_s23_grid.jl`, table `st2_s3_demo_households.csv`):
the regression fixtures of
`test/fixtures/transfer_feasibility_households.toml` re-evaluated
under the new solver.

| Household | Committed theta | Payoff (new chain) | Demonstrated candidate (old chain) | Verdict |
| --- | --- | --- | --- | --- |
| 85 | 8.652475842498528e-4 | 1.0020e-8 | 8.239360204105467e-9 | nonzero, payoff above candidate |
| 100 | 6.652475842498528e-4 | 1.4524e-8 | 1.1554486667771662e-8 | nonzero, payoff above candidate |
| 387 | 6.524758424985278e-5 | 4.2288e-10 | 1.1575079773623812e-10 | nonzero, payoff above candidate |

The committed transfers are bitwise identical to the `MDR-0012`
commits; the demonstrated points evaluate to the recorded values in
the new chain to within 1 ulp.

## 4. Multi-tick old-versus-new trajectories

Method (`stage2_s4_multitick.jl`, tables `st2_s4_multitick.csv` and
`st2_s4_multitick_commits.csv`): 25 ticks, 500 households, both
variants driven through the identical sequential model loop (the
mirror was verified bitwise identical to `set_theta!` over 3 ticks),
per-tick aggregates and per-household deltas; every changed commit is
reference-evaluated at both bundles against the old-chain outside
options with the local old-objective jaggedness measured over a
2.1e-4 window around the old commit at 1e-5 steps.

| Workload | Variant | tick 0: sum theta / frac nonzero | tick 24: sum theta / frac nonzero | tick 24 mean perceived transfer norm (women) |
| --- | --- | --- | --- | --- |
| ws_500 | old | 0.001637 / 0.008 | -0.000609 / 0.012 | -1.40e-6 |
| ws_500 | new | 0.001637 / 0.008 | -0.000609 / 0.012 | -1.40e-6 |
| heterogeneous | old | 0.0 / 0.000 | -0.0003 / 0.002 | 0.0 |
| heterogeneous | new | 0.0 / 0.000 | -0.0003 / 0.002 | 0.0 |
| low_conformism | old | 5.686889 / 0.482 | -8.74e-5 / 0.034 | -9.85e-7 |
| low_conformism | new | 5.686801 / 0.482 | -8.74e-5 / 0.034 | -9.85e-7 |

- `ws_500` and `heterogeneous`: every household commits a bitwise
  identical transfer at every tick (0/500 differing at ticks 0, 1, 2,
  5, 10, 24); hours jitter at most 2.6e-14; the aggregate columns are
  identical.
- `low_conformism`: 224 household-ticks differ in theta (of 37,500),
  concentrated in the four noise-spike households 105/253/262/479
  regime: max `|dtheta|` 8.7e-5 (tick 0, household 382 - both payoffs
  inside the measured local jaggedness 4.8e-6, the new bundle's
  reference payoff is 1.7e-6 higher), the rest at most 2.4e-5; zero
  feasibility flips among them; reference payoffs agree within the
  local jaggedness in every row; the trajectories reconverge (0
  differing thetas at tick 24).
- Hours-only jitter (same theta, hours changed): 23,969 household-ticks,
  max 1.0e-7 (below the solver's own 1e-4 resolution). For exactly
  zero-gain bundles (committed transfer 0 or about 1e-20, gains
  exactly 0 in each chain's own basis) the cross-evaluated old-chain
  payoff flips between exactly 0.0 and `-Inf` at the 2e-15 level in
  12,432 rows; the committed transfer is identical in both variants
  and the flip is a cross-evaluation-basis artifact of the
  exactly-zero-gain knife edge, not a model-output change (each
  bundle's payoff is exactly 0.0 in its own chain).

## 5. Determinism and thread-count independence

The `stage2_counts.jl` state digest (hash over every household's
committed transfer, hours, and perceived transfer norms after a 5-tick
`ws_500` trajectory) is identical across repeated runs and across
`JULIA_NUM_THREADS=1` and `8` (digest 0x831181860bdd48e0, run twice
per thread count). `test/test_threading.jl` asserts bit-identical full
runs across thread counts in the suite.

## 6. Search structure, solves, and objective evaluations

The search driver is untouched, so the sample set, refinement, tie
rule, commit rule, and solve count are unchanged by construction. A
counted mirror of `bargain_transfer` (verified bitwise against it on
the sample) over 150 `ws_500` household-ticks at tick-2 states
reports 2,381.3 cached objective evaluations, 715.3 `evaluate!`
calls, 686.4 labour solves, and 28.9 pointwise certificate prunes per
household-tick (the `MDR-0012`-basis numbers 2,378.7 evaluations and
583.2 solves were measured on a different tick mix; the structures
match).

## 7. Performance

Kernel medians of `benchmark/bargaining_kernel.jl ws_500 20 5`
(`MDR-0011`/`ADR-0013`), 5 repetitions, fresh world per repetition,
idle machine:

| Metric | Post-Stage-1 (1 thread) | Now (1 thread) | Post-Stage-1 (8 threads) | Now (8 threads) |
| --- | --- | --- | --- | --- |
| `set_theta!` kernel median (20 ticks) | 12.52 s | 7.069 s (IQR 0.39) | 2.53 s | 1.662 s (IQR 0.07) |
| `GN.run` median | - | 6.989 s | - | 1.668 s |
| kernel per household-tick | 1.25 ms | 0.707 ms | 0.253 ms | 0.166 ms |
| allocations per household-tick | 20.8 / 100 KB | 20.8 / 100.2 KB | 20.8 / 100 KB | 20.8 / 100.2 KB |

Solve cost (isolated, `stage2_profile.jl`): `mutual_best_response`
1717 ns to 463 ns (near-equilibrium warm start) and 3259 ns to 906 ns
(cold warm start), 3.7x; `individual_utility` 54.7 ns to 12.4 ns
(4.4x); utility calls per solve unchanged at 28 (material-call probe
count); zero allocations per solve and per evaluation retained.

Same-basis total (`stage2_attrib.jl`, 150 identical tick-2
household-ticks): `bargain_transfer` 2.00 ms to 0.75 ms per
household-tick (2.67x). Breakdown of the new per-household-tick cost
(713 us): 292 us labour solves (686 x 426 ns at the real candidate
arguments), 212 us pointwise certificate bounds (715 x 297 ns, the
pow-based `_material_envelope` of `ADR-0015` at about 180 ns per
bound), and about 209 us search machinery (interval slab prefilter,
evaluation cache, sort, and bookkeeping). Honest target assessment:
the 2x kernel target via solve cost alone is NOT met (1.77x at 1
thread, 1.52x at 8): solves fell from about 72 percent of the kernel
to about 41 percent, so Amdahl caps the kernel gain at about 2.2x
even at unlimited solve speedup; the remaining lever is the certified
envelope evaluation and the search machinery (Stage 3 territory -
the envelope is deliberately unchanged here, `MDR-0013`).

## Deviations from the plan

- The regrouped variant (1b) and the hybrid are measured but dropped
  (section 0); the shipped prepared objective is the exact variant
  (1a). This is the plan's documented fallback
  ("keep only what helps").
- The log-utility objective (item 3) is not implemented: item 1+2
  give 3.7x on solve cost, above the 2x trigger, and the specialized
  `beta == 0.5` material leaves no transcendental for a log form to
  remove.
- The same-state comparison samples 25 households per workload state
  (225 workload states plus 203 fixture cases), wider than the
  originally suggested fixture-plus-sample scope.
- The multi-tick comparison uses old arithmetic under the SAME
  `MDR-0012` staged search (the frozen pre-`ADR-0017` driver with the
  pointwise certificate), not the pre-`MDR-0012` unseeded search; the
  question of this stage is solver arithmetic, not search procedure.
