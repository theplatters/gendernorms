# Transfer-search reduction validation (Stage 3, TASK-0018)

Validation evidence for the tiered Stage A sample set and the
specialized `CES` `beta == 0.5` envelope of `MDR-0014`/`ADR-0019`
(replacing the `MDR-0013` staged search as the search-semantics
record): fine-grid solution quality on three workloads, the
demonstrated fixture households, the same-state and trajectory
comparison against the frozen `MDR-0013` reference search
(`bargain_transfer_search_reference`, `test/reference_transfer_search.jl`),
the constructed adversarial band table of the documented discovery
guarantee, determinism, and the performance metrics with the remaining
cost anatomy. Validation only: the recorded changes were implemented
in `src/resources/utility_functions.jl` and
`src/systems/household_bargaining.jl`; this report establishes
quality against the reference search and documents the change.

Environment: Julia 1.12.7, AMD Ryzen 7 5825U (16 hardware threads),
sequential runs on an otherwise idle machine, seed 1 everywhere.
Reference search = the frozen `MDR-0013` staged search (the reference
of `MDR-0014`; its search semantics are the `MDR-0012`/`MDR-0013`
sample set and are bitwise-verified by the former identity tests of
`ADR-0017`). Old baseline = the frozen pre-`MDR-0012` unseeded Brent
search (`bargain_transfer_reference`, `test/reference_bargaining.jl`).
Throwaway drivers live outside the repository in `/tmp/opencode/`
(`stage2_common.jl` shared helpers; `stage3_item12.jl`,
`stage3_item3.jl`, `stage3_counts.jl`, `stage3_bands.jl`,
`stage3_bandloss.jl`, `stage3_measure.jl`, `stage3_anatomy.jl`,
`stage3_classify.jl`, `stage3_hh350.jl`). Data tables are in
`benchmark/transfer_validation/st3_*.csv`.

## 1. Finer-grid solution quality (three workloads)

Method (`benchmark/transfer_validation/st3_finegrid_<workload>.csv`):
the section-1 protocol of `benchmark/transfer_search_validation.md`:
44 households (`1:12:493` plus 100 and 387) at states tick 0, 1, and
5 of the seeded model trajectory, the committed result versus the
maximum of the same objective (same status-quo warm start,
certificate bypassed by direct evaluation) on the finer grid (1e-4
over `+/- 0.02` around `0` and `theta0`, plus 2.5e-4 over `[-1, 1]`,
about 8,400 points per household-state).

| Workload | Household-states | Fine grid beats committed | Committed equals fine max | Committed beats fine max | Max fine-minus-committed | Max theta distance |
| --- | --- | --- | --- | --- | --- | --- |
| ws_500 | 132 | 0 | 128 | 4 | 0.0 | 3.48e-5 |
| heterogeneous | 132 | 0 | 132 | 0 | 0.0 | 0.0 |
| low_conformism | 132 | 2 | 74 | 56 | 4.99e-7 | 3.81e-4 |

- `ws_500` and `heterogeneous` reproduce the `MDR-0013` criterion
  exactly (0/132 fine-beats; the negative deltas are the bounded
  refinement sitting between fine-grid points).
- `low_conformism` shows 2/132 fine-beats, both classified as
  same-band noise spikes within the objective's local jaggedness
  (measured over a 2.1e-4 window at 1e-5 steps around the commit):
  household 13 tick 1 (fine 0.0109 vs commit 0.010818, gap 1.0e-8
  against local jaggedness 5.2e-7) and household 313 tick 1 (fine
  0.04268 vs commit 0.0422985, gap 5.0e-7 against 9.2e-7). Both fine
  maxima lie inside the committed point's contiguous feasible band
  (widths 2.55e-3 and 4.0e-3, `st3_classify.jl`); the true 1e-5-grid
  band maxima sit still higher (2.73e-6 and 5.11e-5), so the fine
  grid itself under-samples those bands. No materially better band is
  missed anywhere: the 0/132-class criterion holds in the material
  sense on all three workloads.

## 2. Demonstrated households 85/100/387

Method (`benchmark/transfer_validation/st3_demo.csv`): the regression
fixtures of `test/fixtures/transfer_feasibility_households.toml`.

| Household | Committed theta | Payoff | Demonstrated candidate | Verdict |
| --- | --- | --- | --- | --- |
| 85 | 8.652475842498528e-4 | 1.0020e-8 | 8.239360204105467e-9 | nonzero, payoff above candidate |
| 100 | 6.652475842498528e-4 | 1.4524e-8 | 1.1554486667771662e-8 | nonzero, payoff above candidate |
| 387 | 6.524758424985278e-5 | 4.2288e-10 | 1.1575079773623812e-10 | nonzero, payoff above candidate |

The committed `(theta, hw, hm)` are bitwise identical to the
`MDR-0013` commits (their bands lie inside the fine windows, where
both searches sample and bracket identically); the coarse tier still
discovers all three bands (each contains a coarse-grid sample, e.g.
0.001 for households 85 and 100). Asserted bitwise in
`test/test_transfer_search_reduction.jl`.

## 3. Reference-search comparison (new vs `MDR-0013` reference)

Method (`benchmark/transfer_validation/st3_ref_changes.csv`,
`st3_multitick.csv`, `st3_multitick_changes.csv`): identical states
where the state is shared - the 200 solver fixture cases of
`test/fixtures/bargaining_baseline.toml`, the 3 fixture households,
and 44 workload households x ticks 0/1/5 of each workload (599
state comparisons, both searches on the identical state), plus 25-tick
trajectory aggregates of both searches driven through the identical
sequential model loop (the mirror verified bitwise against
`set_theta!` over 3 ticks).

Same-state census: **577/599 commits bitwise identical, 22 changed**
(19 solver cases, 3 workload states; 3/3 fixture households
identical). Every changed commit is justified:

- 10 changed commits have the NEW search strictly better
  (reference-evaluated payoff at the new bundle above the reference
  bundle's).
- 12 changed commits have the new search below the reference bundle's
  cross-evaluated payoff; every one of them is within the objective's
  measured local jaggedness (2.1e-4 window at 1e-5 steps around the
  reference commit) and within one refinement bracket of the
  reference commit: largest deficits solver 23 (8.7e-10 against
  jaggedness 1.0e-9), low_conformism t1 hh313 (1.0e-6 against
  1.2e-6), solver 169 (1.4e-8 against 3.0e-8), solver 136 (1.3e-7
  against 3.2e-7). These are different spikes of the jagged
  objective in the same feasible band (the annulus coarsening widens
  Stage B brackets from 1e-4 to 1e-3 there, so refinement settles on
  a neighbouring spike).
- The 2/118 jagged-peak counterexamples (where the pre-`MDR-0012`
  unseeded Brent search beats the staged search) are solver 171 and
  solver 182 (old-Brent payoff above the reference's by about 4.8e-7
  at payoffs near 1.8e-3); the new search matches the reference
  bitwise on both (same commit, same payoff), so the tier change does
  not deepen them.

Trajectory aggregates (25 ticks, 500 households):

| Workload | Variant | tick 0: sum theta / frac nonzero | tick 24: sum theta / frac nonzero | tick 24 mean perceived transfer norm (women) |
| --- | --- | --- | --- | --- |
| ws_500 | reference | 0.001637 / 0.008 | -0.000609 / 0.012 | -1.40e-6 |
| ws_500 | new | 0.001637 / 0.008 | -0.000609 / 0.012 | -1.40e-6 |
| heterogeneous | reference | 0.0 / 0.000 | -0.0003 / 0.002 | 0.0 |
| heterogeneous | new | 0.0 / 0.000 | -0.0003 / 0.002 | 0.0 |
| low_conformism | reference | 5.686801 / 0.482 | -8.74e-5 / 0.034 | -9.85e-7 |
| low_conformism | new | 5.686602 / 0.482 | -8.28e-5 / 0.036 | -8.92e-7 |

- `ws_500` and `heterogeneous`: every household commits a bitwise
  identical transfer at every tick (0/500 differing at ticks 0, 1, 2,
  5, 10, 24); the aggregates are identical; the 5-tick ws_500 state
  digest is bitwise equal to the `MDR-0013` digest recorded in
  `benchmark/solver_equivalence_validation.md`
  (0x831181860bdd48e0).
- `low_conformism`: 363 of 37,500 household-ticks differ in theta
  (19/500 at tick 0, 38 at tick 1, 32 at tick 2, 20 at tick 5, 12 at
  tick 10, 4 at tick 24), mean `|dtheta|` <= 3.3e-5, max 0.01 (tick
  2), and the trajectories reconverge (4 differing households at
  tick 24, max 4.6e-6). Of the changed commits 164 cross-evaluate
  better and 125 worse than the reference bundle (plus knife-edge
  rows at exactly-zero gains), every worse one within the same-band
  jaggedness class above; the aggregates move by 2e-4 of the tick-0
  transfer sum and reconverge to within 4.6e-6 of the reference sum.
- One trajectory row needs its own explanation (recorded, not
  hidden): `low_conformism` tick 2 household 350 falls back to its
  infeasible status quo in the new search while the reference
  trajectory's bundle (from its own, already-diverged state)
  cross-evaluates to a finite 5.0e-11 there. The state's true
  feasible set is a single band of width 1.0e-5 at `3.6e-6..1.4e-5`
  containing no sampled transfer of either search (`st3_hh350.jl`);
  on that exact state the frozen reference and the old Brent search
  fall back identically (`st3_hh350_ref.jl`). This is the documented
  narrow-band miss class (band narrower than the 1e-4 fine spacing),
  identical for the reference search, not a tier-change loss.
- Frozen-old-baseline context: the reference aggregates reproduce the
  `MDR-0013` rows of `benchmark/solver_equivalence_validation.md`
  exactly (e.g. `low_conformism` tick-24 sum -8.74e-5); against the
  pre-`MDR-0012` search (`benchmark/transfer_search_validation.md`
  section 3) the large old-regime transfers (sum 5.69 at tick 24) are
  long gone in both variants.

## 4. Constructed adversarial bands: the documented guarantee

Method: the `windowed_peak` machinery of `test/test_transfer_search.jl`
(the "documented band-discovery guarantee" testset) over band widths
3e-5, 1e-4, 3e-4, 1e-3, and 3e-3 at offsets 1e-4 to 2e-2 from the
anchors `0.0` and `theta0` (both signs; 140 cases; the search runs on
the manufactured objective and the expected outcome is computed from
the sampled set alone). The rule the tests encode is exactly the
recorded guarantee: **a band containing at least one sampled transfer
is discovered** (the sampled transfer is a weak local maximum whose
bounded refinement reaches the injected peak to within
`TRANSFER_REFINE_TOL`), and **a band containing no sampled transfer
can be missed** (on a windowed band the miss is exact: no sample, no
finite cached value, fallback). Found/missed counts per width
(`stage3_guarantee_table.jl`, test assertions 264/264 green):

| Band width | Found (band contains a sample) | Missed (documented class) |
| --- | --- | --- |
| 3e-5 | 22 | 6 |
| 1e-4 | 22 | 6 |
| 3e-4 | 22 | 6 |
| 1e-3 | 28 | 0 |
| 3e-3 | 28 | 0 |

Per-region rule (`MDR-0014`): within `+/- 0.002` of `0.0` or
`theta0` the spacing is 1e-4, elsewhere 1e-3, so every band of width
at least the local spacing is guaranteed discovered; the misses in
the table are sub-spacing bands between coarse samples outside the
fine windows (the table's offsets place narrow bands exactly on the
anchor lattices, hence the 22 found at every width). The measured
model bands never occupy the miss class except the recorded 1e-5
narrow band of `low_conformism` household 350 (section 3), which the
reference misses as well.

## 5. Determinism, cross-thread identity, gates

- State digests over every household's committed transfer, hours, and
  perceived norms after a 5-tick `ws_500` trajectory: identical
  across repeated runs and across `JULIA_NUM_THREADS=1` and `8`
  (digest 0x831181860bdd48e0 in all four runs,
  `benchmark/transfer_validation` methodology).
- Full test suite green at 1 and 8 threads (exit codes unmasked,
  `Pkg.test()`); `julia --project=. scripts/registry_check.jl
  --strict`: 0 warnings, 0 errors; `julia --project=. -e 'using
  GenderNorms'` loads.
- Certificate tests green and extended for the specialized path
  (`test/test_bargain_certificate.jl`, "specialized CES beta == 0.5
  envelope": 537 assertions, brute-force domination on dense grids
  over tiny/huge/asymmetric wages and alpha endpoints, bitwise
  candidate-identity with `material`, analytic-maximizer consistency,
  and bound-versus-computed-utility on both partner roles); the
  interval soundness fuzz (`test/test_interval_certificate.jl`) and
  the `CES_CERT_MIN_BETA` fail-open tests stay green.

## 6. Metrics and remaining anatomy

Kernel medians of `benchmark/bargaining_kernel.jl ws_500 20 5`
(5 repetitions, fresh world per repetition, idle machine):

| Metric | `MDR-0013` (1 thread) | Now (1 thread) | `MDR-0013` (8 threads) | Now (8 threads) |
| --- | --- | --- | --- | --- |
| `set_theta!` kernel median (20 ticks) | 6.869 s (IQR 0.195) | 2.510 s (IQR 0.017) | 1.599 s (IQR 0.040) | 0.608 s (IQR 0.006) |
| `GN.run` median | 6.717 s | 2.543 s | 1.655 s | 0.540 s |
| kernel per household-tick | 687 us | 251 us | 160 us | 61 us |
| `set_theta!` allocations per household-tick | 100.2 KB / 20.8 | 55.0 KB / 12.3 | 100.2 KB / 20.8 | 55.0 KB / 12.4 |

**2.74x at 1 thread and 2.63x at 8 threads** on the contemporaneous
baseline (7.07 s / 1.66 s in the task reference; measured here as
6.87 s / 1.60 s). The 5x target (toward 1-1.5 s at 1 thread) is NOT
met: the honest number is 2.51 s at 1 thread. Remaining anatomy per
household-tick (`stage3_counts.jl`, 150 `ws_500` household-ticks at
tick-2 states; unit costs from `benchmark/solver_equivalence_validation.md`
and `stage3_anatomy.jl`):

| Share | Cost | Composition |
| --- | --- | --- |
| labour solves | about 148 us (59%) | 347.6 solves x 426 ns (down from 686 solves) |
| certified-envelope bounds | about 7 us (3%) | 747.7 `_payoff_upper_bound` calls at 9.2 ns (down from 1426 at 149 ns; the specialized sqrt/square envelope is 16x cheaper) |
| certificate and interval machinery | about 26 us (10%) | 376.5 `evaluate!` calls with their pointwise guards and `exp`, 32.0 interval decisions |
| search machinery and household work | about 70 us (28%) | enumeration of 2037.5 sampled transfers with slab-membership checks, 376 cache inserts, one sort, Stage B scan, `norm_means`/extraction |

Per household-tick counters before -> after: sampled transfers
2381 -> 2037.5, `evaluate!` calls 715 -> 376.5, solves 686 ->
347.6, envelope-bound calls 1426 -> 747.7, interval decisions 58 ->
32.0. The remaining lever is the solve share: the uncertified span of
the certificate (about `+/- 0.2` around the anchors at conformism 10)
still places roughly 350 coarse-grid samples per search in full-solve
territory; recorded as `TASK-0020` with its candidate levers.

## Deviations from the plan

- The plan's "coarse coverage beyond `+/- 0.02` is already cheap"
  reading was measured to be wrong for the uncertified span (the
  certificate certifies only beyond about `|theta| ~ 0.2` at
  conformism 10); the tier scheme keeps the 1e-3 coarse grid there
  as recorded and the remaining solves are reported as the dominant
  share instead of being tuned away by unrecorded sample dropping.
- Section 1 pools the low_conformism fine-beats into the
  same-band-within-jaggedness class instead of demanding a literal
  0/132: the two gaps are below the objective's measured local
  jaggedness and the fine grid itself under-samples those bands
  (classification data in section 1).
- The adaptive-densification variant of the plan is not implemented
  (measured and rejected in `ADR-0019`): on the measured states it
  adds solves without new discovery.
- The status-quo-relative payoff pruning idea (a sound Nash-product
  upper bound from the envelope) is recorded as future work
  (`TASK-0020`), not implemented: it would change the cached-value
  semantics beyond the sanctioned discovery change.
