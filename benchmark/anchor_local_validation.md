# Bounded anchor-local production search (TASK-0020)

The default `bargain_transfer` / `set_theta!` now uses the bounded search
of `MDR-0015` / `ADR-0020`, not the unconditional discovery scan. The
old tiered `MDR-0014` discovery solver remains explicitly available with
`search=:discovery`. Sources: ODD section Transfer bargaining, NetLogo
`set-theta` and `calculate-payoff`; the objective and labour solver are
unchanged, including fixed status-equilibrium warm starts.

This is a speed/coverage tradeoff, NOT an equivalence claim. Remote bands
can be missed and at most four sampled peaks receive refinement. Never
interpret failed probes or a status fallback as global infeasibility.

## Search budget and usage

- Anchors `-1`, `0`, current transfer, `+1`.
- Unchanged fine windows: 1e-4 spacing over +/-0.002 of 0/current transfer.
- Eight exploration offsets per side per anchor, doubling from 0.004
  through 0.512; no full-domain grid and no automatic discovery fallback.
- At most four promising plateau refinements, at most 24 Brent iterations
  each, default argument tolerance 1e-5.
- At most **216 distinct objective records**, including the status seed:
  at most 116 Stage A transfers plus 4 * 25 new refinement probes.
  Cached bracket endpoints do not add calls. Outside/status labour solves
  are separate. Tiny requested tolerances cannot exceed the budget.
- Every finite evaluated candidate stays eligible; commit only on strict
  improvement over the seeded status payoff, with its cached solved hours.

No configuration change is needed for production. For explicit validation:

```julia
GenderNorms.bargain_transfer(hw, hm, theta, pw, pm, config; search=:discovery)
GenderNorms.set_theta!(world, config; search=:discovery)
```

## Performance

Julia 1.12.7, AMD Ryzen 7 5825U, one Julia thread, otherwise idle machine.
The existing `benchmark/bargaining_kernel.jl ws_500,heterogeneous 20 5`
was run before and after the implementation, with identical seed-1 fresh
worlds, a discarded full-size warmup, and five measured repetitions.
Times exclude compilation and setup. Each kernel number sums **20 ticks
over 500 households**, not a single tick. No other heavy jobs ran during
the timing passes.

| Workload | Before kernel median | Local kernel median | Faster | Local IQR | Before / local end-to-end |
| --- | --- | --- | --- | --- | --- |
| ws_500 | 2.47850 s | 0.23642 s | 10.48x | 0.00108 s | 2.48544 / 0.24213 s |
| heterogeneous | 1.62881 s | 0.21935 s | 7.43x | 0.00336 s | 1.63343 / 0.22162 s |

For ws_500 this is 23.64 us per household-tick, versus 247.85 us before;
allocations fall from 54,957 to 9,053 bytes per household-tick and from
12.35 to 5.85 allocations. The historical pre-discovery 0.063 s is NOT
fully recovered: local production remains about 3.75x slower because it
actually probes the fine anchor windows and remote exploration points.
There is no zero-transfer fast path.

The reproducible current-mode timing pass
(`benchmark/anchor_local_validation.jl <directory> timing`, raw table
`benchmark/transfer_validation/anchor_timing.csv`) confirms this on all
three workloads. Discovery here has identical search semantics but the
smaller production storage hints, so its allocation counts differ from
the pre-change tree; it is an explicit validation mode, not production.

| Workload | Local median / IQR | Discovery median / IQR | Faster |
| --- | --- | --- | --- |
| ws_500 | 0.23867 / 0.00122 s | 2.49490 / 0.01194 s | 10.45x |
| heterogeneous | 0.21522 / 0.00123 s | 1.67510 / 0.03083 s | 7.78x |
| low_conformism | 0.26706 / 0.00272 s | 6.56153 / 0.20606 s | 24.57x |

The ws_500 local pass has one 0.41242 s outlier; the median and IQR above
and the independent existing-harness pass remain consistent. Min/max
values and allocation bytes are preserved in the raw table.

## Identical-state quality versus discovery and finer grid

Reproduce with `benchmark/anchor_local_validation.jl <directory> quality`.
Data: `benchmark/transfer_validation/anchor_quality.csv`. The same
seed/network/defaults as the kernel harness; low_conformism differs only
in initial conformism 0/0. Use 44 household positions (`1:12:493` plus
100 and 387), at states before tick 0 and after 1/5 discovery ticks,
on all three workloads (396 comparisons). Both solvers use the identical
state. The finer grid directly evaluates `equilibrium_payoff`, bypassing
certificates, at 1e-4 over +/-0.02 of both anchors and 2.5e-4 over [-1, 1],
including the status quo. Commit payoffs use cached committed hours and
the identical outside utilities; they are not re-solved from a new start.

| Workload | States | Commits bitwise identical | Discovery beats local | Maximum payoff deficit | Fine grid beats local | Maximum fine-grid deficit |
| --- | --- | --- | --- | --- | --- | --- |
| ws_500 | 132 | 132 | 0 | 0 | 0 | 0 |
| heterogeneous | 132 | 132 | 0 | 0 | 0 | 0 |
| low_conformism | 132 | 121 | 7 | 6.85634e-6 | 2 | 6.03953e-8 |

Of the 11 changed low-conformism commits, four improve over discovery and
seven have lower payoff. The largest deficit is household 349 at tick 0
(0.00746023 local versus 0.00746709 discovery); the largest theta change
in this sample is household 253 after five ticks (0.232232 versus
0.242531). These are recorded losses, not silently classified as equivalent.
The finer grid is itself not a global optimizer.

Observed production objective-record means / maxima on these states:
ws_500 65.35 / 120, heterogeneous 64 / 64, low_conformism 77.65 / 145;
mean full SEARCH labour solves 57.55, 54.23, and 65.92 respectively,
excluding the status seed and separate outside/status solves. Every
record count stays within 216; every production improvement commit is
finite and strictly improves on its own status quo. An infeasible status
fallback can remain infeasible, as in the preserved commit contract.

The demonstrated household fixtures 85/100/387 still commit nonzero
transfers at payoffs above their demonstrated candidates; on the initial
seeded population they also match discovery bitwise. Their transfers are
8.652475842498528e-4, 6.652475842498528e-4, and
6.524758424985278e-5 respectively.

## Twenty-five-tick trajectories and material losses

Reproduce with `benchmark/anchor_local_validation.jl <directory> trajectories`.
Data: `benchmark/transfer_validation/anchor_trajectories.csv` and
`benchmark/transfer_validation/anchor_trajectory_changes.csv`. Independently
evolve local and discovery worlds through the identical `MDR-0010` phase
order, recording every tick. These are trajectory comparisons, not
identical-state payoff comparisons after divergence.

| Workload | Differing transfers over 12,500 household-ticks | Tick 0 sum theta local / discovery | Tick 24 sum theta local / discovery | Tick 24 nonzero fraction local / discovery |
| --- | --- | --- | --- | --- |
| ws_500 | 0 | 0.00163738 / 0.00163738 | -0.000609017 / -0.000609017 | 0.012 / 0.012 |
| heterogeneous | 0 | 0 / 0 | -0.0003 / -0.0003 | 0.002 / 0.002 |
| low_conformism | 664 | 5.71639 / 5.68660 | -9.27864e-5 / -8.27864e-5 | 0.032 / 0.036 |

Standard and heterogeneous households have bit-identical transfer and
hours digests at every tick. Low conformism has 92 differing transfers
at tick 0, three at tick 24, and a maximum transient |dtheta| of 0.911918
(household 83 at ticks 7/8). Discovery on that household's exact LOCAL
pre-tick state also returns zero: this largest trajectory delta is a
state-feedback difference, not evidence of a missed band on that state.

The change table additionally runs discovery on each changed household's
exact LOCAL pre-tick state, using the original starts, outside options,
and fixed warm-start rule. Of 664 changed trajectory rows, 206 match this
shared-state discovery bundle bitwise and 299 have lower local payoff.
**Material search losses exist:** the largest shared-state deficit is
6.41297e-4 at low_conformism tick 0 household 71: local theta 0.128 has
payoff 0.000634587, while discovery theta 0.117 has payoff 0.001275883
(a 50.3% deficit relative to discovery).
Household 344 similarly loses 3.18056e-4 (local 0.128 versus discovery
0.115). These are intentional budgeted-search limitations, not rounding
equivalence. Choose discovery when this loss of coverage is unacceptable
for an experiment. Neither solver proves global optimality.

## Verification

- Full `Pkg.test()` passed at 1 and 8 threads. The production contract
  tests also pass independently at both counts after adding the explicit
  216-record worst-case test (161 assertions).
- Retained discovery contract, interval-certificate soundness, fixture
  identity, and jagged-peak regression tests still pass; no oracle or
  fixture was overwritten to bless new outcomes.
- Production cache replay is exact on the 200 solver fixture cases;
  budget, strict commits, cached hours, exact fallback, and determinism
  are asserted. Against the historical unseeded-Brent baseline it commits
  166 cases, including 48 new commits; the historical baseline commits
  118, with local payoff at least as high in 113 and lower in five.
  Universal dominance is deliberately not asserted.
- The 25-tick trajectory tables and transfer/hours digests are identical
  at 1 and 8 threads across all three workloads, including both modes.
- `registry_check --strict` reports zero warnings/errors; the package
  load check succeeds. Decision records and task status are synchronized.
