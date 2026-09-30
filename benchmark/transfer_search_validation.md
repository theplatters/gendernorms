# Transfer search validation package (TASK-0014)

Validation evidence for the staged transfer search of `MDR-0012`
(superseding `MDR-0005`, structure in `ADR-0016`): solution quality of
the new search on a finer grid, an artifact assessment of the tiny
demonstrated gains under tighter labour convergence, a multi-tick
old-versus-new trajectory comparison against the frozen reference
search (`bargain_transfer_reference`, `test/reference_bargaining.jl`),
a matched-state NetLogo comparison of the transfer stage (ODD section
Transfer bargaining; NetLogo `set-theta`, `set-theta-index`,
`calculate-payoff`, `choose-bundle`, `calculate-utility`), and the
measured search cost. Validation only: no model or search code was
changed. The search intentionally changed model results
(`MDR-0012`); this report establishes solution quality and documents
the change.

Environment: Julia 1.12.7, NetLogo 7.0.4 headless (Java 21), AMD Ryzen
7 5825U (16 hardware threads). Sequential runs on an otherwise idle
machine; seed 1 everywhere. Throwaway driver scripts live outside the
repository in `/tmp/opencode/` (regenerate by running them from the
repository root with `julia --project=.`):

- `/tmp/opencode/val_common.jl` (shared: workload specs, `set_theta!`
  extraction, the tolerance-parameterized objective chain, the fine
  grid, the old-search world loop mirror)
- `/tmp/opencode/val_s1_grid.jl`, `/tmp/opencode/val_s2_tolerance.jl`,
  `/tmp/opencode/val_s2_warmstart.jl`,
  `/tmp/opencode/val_s3_trajectory.jl`
- `/tmp/opencode/gen_nl_probe.py` (NetLogo probe model and
  BehaviorSpace setup generator), `/tmp/opencode/val_s4_compare.jl`
- `/tmp/opencode/val_s5_counts.jl`

Data tables are in `benchmark/transfer_validation/` (referenced per
section). Pre-change kernel numbers cited below are pre-`MDR-0012`
(`benchmark/bargaining_kernel_report.md`, `ADR-0015` scope).

## 1. Finer-grid solution-quality comparison

Method (`benchmark/transfer_validation/s1_fine_grid.csv`): 44
households of the seed-1, 500-agents-per-gender, Watts-Strogatz
neighbors-per-side 2 / rewiring 0.1, CES beta 0.5 setup, sampled
deterministically across the index range (`1:12:493` plus 85, 100,
387), at states tick 0, after 1 tick, and after 5 ticks of the model
trajectory. Per household and state the search's committed result
(`bargain_transfer`) is compared with the maximum of the same
objective (`equilibrium_payoff` chain, same status-quo warm start,
certificate bypassed by direct evaluation) on a grid finer than the
search's coarse grid: 1e-4 spacing over [-0.02, 0.02] around 0 and
`theta0`, plus 2.5e-4 over [-1, 1] (about 8,400 points per
household-state, 1.1M objective evaluations). The objective is jagged
at the 1e-4 scale (discrete labour solver, see section 2 and the 2/118
fixture counterexamples), so the report distinguishes a missed
materially better band from a different noise spike in the same band.

| State | Household-states | Fine grid beats committed | Committed equals fine max | Committed beats fine max | Max fine-minus-committed | Max theta distance |
| --- | --- | --- | --- | --- | --- | --- |
| tick 0 | 44 | 0 | 41 | 3 | 0.0 | 3.48e-5 |
| tick 1 | 44 | 0 | 43 | 1 | 0.0 | 1.52e-18 |
| tick 5 | 44 | 0 | 44 | 0 | 0.0 | 0.0 |

- The fine grid never beats the committed result (0/132). The four
  negative deltas are the opposite direction: the search's bounded
  refinement (1e-5 argument tolerance) sits between fine-grid points
  and reaches slightly higher payoffs (largest gap 2.97e-9, household
  100 at tick 0).
- Every fine-grid argmax lies in the same feasible band as the
  committed point, within 3.5e-5 in theta (one local-grid step): all
  observed differences are different noise spikes in the same band,
  not missed bands. Representative rows (tick 0): household 85
  committed theta 8.652475842498528e-4 (payoff 1.002e-8) vs fine max
  0.0009 (8.239e-9), band [0.0009, 0.001]; household 100 committed
  6.652475842498528e-4 (1.452e-8) vs 0.0007 (1.155e-8), band [0.0007,
  0.0008]; household 387 committed 6.524758424985278e-5 (4.229e-10)
  vs 0.0001 (1.158e-10), band {0.0001}.
- Positive-payoff census on the sample: 3/44 households at tick 0
  (exactly 85/100/387, consistent with the diagnosis's 3/500), 3/44
  after 1 tick, 0/44 after 5 ticks. The trajectory is now driven by
  the `MDR-0012` search, so the tick-1 and tick-5 states differ from
  the pre-`MDR-0012` states of `benchmark/transfer_search_diagnosis.md`
  (which reported 0/500 at ticks 1 and 5 on the old trajectory): the
  tick-0 commits of households 85/100/387 keep a positive band alive
  one tick longer.
- New dynamic found at tick 1: for 85/100/387 the tick-0 committed
  transfer is infeasible against the new zero-transfer outside options
  once the lagged norms absorb it (`status_payoff == -Inf`), so the
  search re-bargains: 85 and 100 commit smaller positive transfers
  (6.52e-5 and 7.64e-5, payoffs 9.22e-10 and 1.92e-9), 387 returns to
  zero transfer (payoff 4.37e-13 at theta 0, also strictly above the
  `-Inf` status quo).
- Known limitation confirmed, not hidden: over the 200 solver fixture
  cases (`test/test_bargaining_equivalence.jl` log) the old Brent
  commits 118, and the new search's payoff is below the old one in 2
  of those 118 (and >= in 116; the new search commits 167 cases, 49 of
  them new). Those 2/118 counterexamples are narrow peaks that the
  sampled set plus refinement does not reach; on the population sample
  above no such case occurred.

## 2. Tighter labour-convergence checks (artifact assessment)

Method (`benchmark/transfer_validation/s2_tolerance.csv`,
`benchmark/transfer_validation/s2_warmstart.log`): the demonstrated
households 85/100/387 at tick 0 (fixture parameters of
`test/fixtures/transfer_feasibility_households.toml`), their tick-1
states on the `MDR-0012` trajectory, and five additional households
(50/150/250/350/450 at tick 1). For each case the committed
candidate's payoff, the status-quo payoff, and the fine-grid near-zero
payoffs are recomputed with `mutual_best_response` at successively
tighter labour convergence: `eps` 1e-4, 1e-5, 1e-6 with `max_sweeps`
100, plus `eps` 1e-6 with `max_sweeps` 1000 (default `eps` 1e-3 as
reference).

- Every payoff and both gains are bitwise identical at all five
  tolerance levels for every case and every evaluated theta (the
  committed candidates, the demo points, +/-0.001 and +/-0.0005, and
  the near-zero grid maxima). The fixed-point residual of one extra
  `mutual_best_response` run is exactly 0.0 at every level: the outer
  loop is fully converged even at the default `eps` 1e-3.
- Committed candidates strictly improve on the status quo at every
  level. Gains at the committed theta (identical at all levels):
  85 tick 0 (4.06e-4, 2.47e-5), 100 tick 0 (4.52e-4, 3.21e-5), 387
  tick 0 (2.90e-5, 1.46e-5), 85 tick 1 (3.39e-5, 2.72e-5), 100 tick 1
  (5.16e-5, 3.72e-5), 387 tick 1 (4.59e-7, 9.52e-7 at theta 0). The
  five additional households: zero gains (four cases, stable) or the
  tick-1 theta-0 case of household 350 (6.42e-7, 1.71e-6, stable).
- Supplementary warm-start probe: at the committed theta, warm starts
  `status`, `outside`, and `committed` (the model's recorded rule
  starts from the status-quo equilibrium) converge to the identical
  feasible fixed point. Alternative warm starts (`init`, `half`,
  `zero`, `one`) converge to neighbouring fixed points where the
  smaller partner gain flips sign: household 85 man's gain 2.47e-5
  becomes -8.3e-6 to -2.5e-5 (payoff `-Inf`), household 100's 3.21e-5
  becomes -1.0e-5 to -3.4e-5 (one start keeps a smaller positive
  payoff 1.55e-9); household 387 stays feasible from three of four
  alternative starts (payoffs 5.7e-10, 5.5e-10, 1.2e-10) but not from
  `init`; the tick-1 cases lose feasibility from every alternative
  start. The feasible band shapes are contiguous at 1e-5 steps
  (household 85 positive over [0.000855, 0.001025], household 100 over
  [0.000665, 0.000805]) with sharp sign flips at the edges.

Conclusion (plainly): the near-zero improvements are NOT
labour-solver-tolerance artifacts of an unconverged loop - they are
genuine, exactly converged fixed points of the implemented objective
and are bitwise stable from `eps` 1e-3 down to 1e-6 and 1000 sweeps,
and the committed theta strictly improves on the status quo at every
tolerance. They are genuine features of the converged implemented
model under its recorded warm-start rule (`MDR-0012`). The MIXED part:
feasibility of the smaller gain (1.5e-5 to 3.7e-5 in the tick-0/tick-1
cases, 2.6e-6 at the demo point of household 387) is a fixed-point
SELECTION property of the discrete best-response solver - the map has
several fixed points within about 1e-5 in hours, and a different warm
start lands on one where the small gain is negative. This is
faithful-to-reference behavior: NetLogo `choose-bundle` is likewise a
discrete, search-history-dependent hill-climb (mutable warm starts,
`current-delta` 0.0001, `convergence_epsilon` 0.001), so the reference
implementation has no unique continuous equilibrium either. The gains
must therefore be read as model-defined solver outputs (smaller than
the fixed-point selection scale at their lower end), not as numerically
exact gains from trade.

## 3. Multi-tick old-vs-new comparison

Method (`benchmark/transfer_validation/s3_ticks.csv`,
`s3_<workload>_households.csv`, `s3_<workload>_deltas.csv`): the
frozen old search (`bargain_transfer_reference`) and the new
`bargain_transfer` driven through the identical seeded model loop
(`step_model!` order of `MDR-0010`; the driver mirror was verified
bitwise identical to `set_theta!` on 3 ticks) over 25 ticks, seed 1,
500 households. Workloads: `ws_500` (the representative config),
`heterogeneous` (the `benchmark/bargaining_kernel.jl` wage-gap variant:
mean_wage 2.0/0.5 men/women, conformism 50/50), and `low_conformism`
(the diagnosis control where transfers matter most: conformism 0/0).
Per-tick aggregates of committed transfers and hours, perceived
transfer norms (`norm_means(...).transfer`, the `N_theta` the next
tick's bargaining sees), and per-household deltas over time.

| Workload | Variant | tick 0: sum theta / frac nonzero | tick 24: sum theta / frac nonzero | tick 24 mean perceived transfer norm (women) |
| --- | --- | --- | --- | --- |
| ws_500 | old | 0.0 / 0.000 | 0.0 / 0.000 | 0.0 |
| ws_500 | new | 0.00164 / 0.008 | -0.00061 / 0.012 | -1.25e-6 |
| heterogeneous | old | 0.0 / 0.000 | 0.0 / 0.000 | 0.0 |
| heterogeneous | new | 0.0 / 0.000 | -0.0003 / 0.002 | -6.0e-7 |
| low_conformism | old | 3.108 / 0.042 | 5.694 / 0.236 | 0.01221 |
| low_conformism | new | 5.687 / 0.482 | -0.000087 / 0.034 | -2.2e-7 |

- `ws_500`: the old search commits zero transfer in every household at
  every tick. The new search commits small nonzero transfers in 21
  households over the run (max 8.65e-4); 6 are nonzero at the final
  tick. Trajectories diverge from tick 0 (4 households, mean
  |dtheta| 3.3e-6); final-tick deltas: 6 households, mean |dtheta|
  1.2e-6, max 2.9e-4. Hours barely differ (|dhw| max 4.0e-6, |dhm|
  max 0.0).
- `heterogeneous`: nearly nothing happens in either variant (4
  households ever nonzero under the new search, 1 at the final tick,
  theta -0.0003); the high conformism suppresses feasible transfer
  bands, consistent with the diagnosis control.
- `low_conformism`: the trajectories diverge strongly and
  qualitatively. The new search starts with many small transfers (241
  households nonzero at tick 0, sum 5.687, mean perceived norm 0.0123)
  which decay to near zero (sum 1.38 at tick 2, 94 nonzero at tick 5,
  17 nonzero and sum -8.7e-5 at tick 24). The old search starts with
  fewer but larger transfers (21 nonzero, sum 3.108) and grows them
  through the transfer-norm feedback (118 nonzero, sum 5.694, mean
  perceived norm 0.0122 at tick 24). From tick 0 on, 127-287
  households differ per tick (tick 0: 241, mean |dtheta| 0.0108; final
  tick: 127, mean |dtheta| 0.0405, max 0.348; max over time 1.004).
  Per-household hours diverge less (final |dhw| median 0.0, p99 5.4e-5)
  except one household whose hours jump corner-to-corner (|dhw| 0.99995).
- Persistent versus transient: the new search produces predominantly
  TRANSIENT nonzero transfers - of the households ever nonzero, 15/21
  (`ws_500`), 3/4 (`heterogeneous`), and 362/379 (`low_conformism`)
  drop back to zero before the final tick; 6, 1, and 17 respectively
  persist to the end. Mechanism (section 1): once a committed transfer
  is absorbed into the lagged norms it can become infeasible against
  the recomputed zero-transfer outside options (`status_payoff ==
  -Inf`), and the strict-improvement rule then shrinks it or returns
  to zero. The old search's large sparse transfers instead move the
  norms and grow a self-sustaining regime.
- Mean hours by gender evolve almost identically in both variants
  within each workload (e.g. `ws_500` women 0.374 to 0.00027, men
  0.765 to 1.0 in both; `low_conformism` women about 0.62 to 0.64 in
  both), so the transfer-stage change is first-order in transfers and
  transfer norms and second-order in hours at this horizon.

## 4. Matched-state NetLogo comparison

Method: approach (a) of the plan succeeded. A probe copy of
`gender_model_shocks_preferences.nlogox` (generator
`/tmp/opencode/gen_nl_probe.py`) injects the three fixture households
85/100/387 as literal turtle state (wages, `preference-private`,
`conformism`, current and old hours and transfer exactly as recorded in
`test/fixtures/transfer_feasibility_households.toml`) and reproduces
the perceived norms exactly with same-sex donor neighbours whose
lagged hours and transfers equal the fixture `N_h`, `N_theta`, and
`N_h_spouse` means. The shipped procedures are then driven headless
(NetLogo 7.0.4, BehaviorSpace, `--threads 1`, `MDR-0011` invocation
style): `set-theta` (the +/-0.001 hill-climb around the current
transfer) and `set-theta-index` (the shipped full scan at
`delta-theta` 0.001), with the outside options computed by the shipped
`choose-bundle`-at-0 path of `set-theta` and all utilities recorded via
`calculate-utility` and `calculate-payoff` (8-decimal `precision`
rounding, -1 sentinel).

Matched exactly: household parameters, perceived norms, initial hours
and transfer. Verified bitwise - `calculate-utility` at the initial
bundle equals Julia's `individual_utility` exactly in all three
households (woman/man utilities 0.5006427761871605 / 0.833296168294311
(hh 85), 0.5206498341823258 / 0.8950666271198164 (hh 100),
0.6124965109474886 / 0.7974226121586336 (hh 387)). Not matched (and
attributed, not hidden): the labour solver (discrete `choose-bundle`
vs the continuous Brent best response of `MDR-0002`) and its
consequences, the 8-decimal payoff rounding and -1 sentinel of
`calculate-payoff`, the mutable warm starts inside `choose-bundle`
(the probe runs the shipped `set-theta` order, so its search history is
NetLogo's own), and NetLogo's randomized partner order (irrelevant
here: one couple per run). Outside options therefore differ slightly
between implementations (e.g. hh 85: Julia (0.5185931226856632,
0.7822408667016871) vs NetLogo (0.5185957349484491, 0.782202104212091));
this is a solver difference at the same state, not a state mismatch.
Comparison is state-level (single transfer stage on matched
households), not a joint trajectory run.

| Household | Julia old commit | Julia new commit | NetLogo `set-theta` (hill) | NetLogo `set-theta-index` (scan) |
| --- | --- | --- | --- | --- |
| 85 | 0 | 8.652475842498528e-4 | 0.001 | 0.001 |
| 100 | 0 | 6.652475842498528e-4 | 0 | 0.002 |
| 387 | 0 | 6.524758424985278e-5 | 0 | 0 |

(`benchmark/transfer_validation/s4_nl_hill.csv`,
`s4_nl_scan.csv`, per-theta objectives `s4_nl_eval.csv` and
`s4_netlogo_comparison.csv`.)

- Household 85: YES - NetLogo's `set-theta` hill-climb finds the
  near-zero improvement the old Julia search missed and commits
  theta 0.001 (rounded payoff 2.147e-9). Julia's objective at the same
  theta gives 2.141e-9 (the fixture demo2 point); NetLogo's committed
  hours (0.4153, 0.7270) sit at Julia's committed hours
  (0.4152738, 0.7270214) to the discrete solver's 1e-4 resolution. The
  old Julia search's miss here is confirmed as a search failure, and
  the improvement is real in both objectives.
- Household 100: NO - NetLogo's hill probes at +/-0.001 are infeasible
  in NetLogo's objective too, so `set-theta` commits 0 exactly like
  the old Julia search: the near-zero band lies between the probes.
  NetLogo's own objective confirms the band exists (payoffs 2.35e-8 at
  0.0005, 1.45e-8 at the Julia commit 6.65e-4, 1.16e-8 at 0.0007), so
  both implementations see the improvement the old search missed, and
  both shipped search procedures can miss it at their probe step; the
  full 0.001 scan of `set-theta-index` instead commits 0.002 (payoff
  9.93e-8), a band that exists only in NetLogo's objective (Julia's
  objective is `-Inf` there).
- Household 387: NO - and the improvement does not exist in the
  reference at all: NetLogo's objective is infeasible at 6.52e-5 and
  1e-4 (the man's raw gain is -2.56e-5 and -3.93e-5 where Julia's
  discrete fixed point gives +1.46e-5 and +2.60e-6). The Julia band of
  household 387 is a continuous-solver fixed-point feature not
  reproduced by the reference's discrete `choose-bundle`.
- Objective agreement over 22 probe thetas x 3 households (66 rows):
  54 rows agree on feasibility, 12 differ - all of them the
  fixed-point-selection sign flips of section 2 (NetLogo feasible /
  Julia infeasible at 0.0002-0.0015 for hh 85 and 0.0005-0.002 for hh
  100; Julia feasible / NetLogo infeasible at 6.52e-5 and 1e-4 for hh
  387; plus the theta-0 loose-convergence residual of `choose-bundle`,
  which leaves a -3.3e-6 gain where Julia has exactly 0). Where both
  are feasible at the same theta the payoffs agree closely (hh 85 at
  0.001: 2.147e-9 vs 2.141e-9).
- Outcome for `TASK-0014`: the near-zero improvement phenomenon is
  intended behavior at the ODD Transfer bargaining level in both
  implementations where it exists (hh 85 confirmed by the reference's
  own hill-climb, hh 100 confirmed in the reference's objective), and
  the pointwise band structure diverges between the reference and the
  port through the discrete versus continuous labour solver at the
  1e-5..1e-4 scale. The `MDR-0012` staged search is closer to the
  reference's objectives than the old unseeded Brent search: it finds
  the bands NetLogo's objective also has (85, 100) and, like every
  sampled search, it can also commit solver-fixed-point bands the
  reference lacks (387, and the 2/118 fixture counterexamples in the
  other direction). No behavior was hidden or fixed; the divergence is
  the documented, intended model change of `MDR-0012` and its
  recorded search-resolution limitation.

## 5. Runtime impact and registry sync

Measured with `benchmark/bargaining_kernel.jl ws_500 20 5`
(methodology `MDR-0011`/`ADR-0013`; medians over 5 repetitions, fresh
world per repetition, sequential on an idle machine). Pre-change
numbers are pre-`MDR-0012` (`benchmark/bargaining_kernel_report.md`:
kernel 0.0627 s / 0.0136 s at 1/8 threads for the 5-repetition variant
of the final `ADR-0015` tree; the 15-repetition table there reads
0.0632 s / 0.0136 s, `GN.run` 0.0675 s / 0.0188 s).

| Metric | Pre-change (1 thread) | Now (1 thread) | Pre-change (8 threads) | Now (8 threads) |
| --- | --- | --- | --- | --- |
| `set_theta!` kernel median (20 ticks) | 0.0627 s | 18.208 s (IQR 0.704) | 0.0136 s | 3.656 s (IQR 0.030) |
| `GN.run` median | 0.0675 s | 18.523 s | 0.0188 s | 3.665 s |
| kernel per household-tick | 6.3 us | 1.82 ms | 1.4 us | 0.37 ms |
| `set_theta!` allocations per household-tick | 0.85 | 40.9 | 0.92 | 40.9 |

The kernel is 290x slower at 1 thread and 269x at 8 threads
(`GN.run` 274x and 195x); the multithreaded loops of `ADR-0014` still
scale (4.98x kernel speedup at 8 threads). This is the recorded cost
of guaranteed feasibility discovery (`MDR-0012`), tracked as the
remaining `TASK-0014` work.

Objective evaluations per household-tick (`/tmp/opencode/val_s5_counts.jl`,
150 sampled ws_500 household-ticks): 2376 total at `theta0 = 0`
(2371 Stage A samples plus 5 bounded-refinement evaluations). The
Stage A set is the explicit `MDR-0012` set deduplicated: 2371 samples
when `theta0` is 0 and up to 2772 when `theta0` lies off both grids
(e.g. 2731 at `theta0` 0.5; the previously quoted 2371-2739 range is
this same arithmetic). Of the 2376 evaluations, a mean 1706 are
certified `-Inf` without a labour solve (`ADR-0015` certificate) and
669 execute a full `mutual_best_response` (min 604, max 758 in the
sample).

Registry sync (this section's last deliverable):

- `registry/model/discrepancies.md`: the zero-transfer-regime entry now
  records what this validation resolved and what remains open.
- `registry/tasks.md`: `TASK-0014` narrowed to the remaining work
  (record the comparison outcome as an MDR, reduce the staged search
  cost); the validation deliverables are complete and cited.
- `MDR-0012` and `ADR-0016`: factual, additive measurement notes in
  `Consequences` (in-place amendment of current records, allowed by
  `ADR-0008`); no decision text changed.
- `benchmark/transfer_search_diagnosis.md` links here.

## Deviations from the plan

- Section 1 evaluates the tick-1 and tick-5 states on the current
  (`MDR-0012`) model trajectory, not the pre-`MDR-0012` trajectory of
  the diagnosis; tick 0 is identical to the diagnosis's state. This is
  documented per state above.
- Section 1's sample is 44 households (`1:12:493` plus 100 and 387;
  85 already falls on the stride), within the suggested 25-50.
- Section 3 adds a third workload (`low_conformism`) beyond the
  required pair because it is the regime where transfers matter and
  the old/new divergence is largest.
- Section 2's "small additional sample" is five households at tick 1
  (50/150/250/350/450); none of them shows positive gains except the
  theta-0 status-quo case of household 350 (recorded above).
- Section 4 is a state-level matched comparison (approach (a)); no
  joint NetLogo trajectory run was performed, so trajectory-level
  NetLogo-vs-Julia comparison remains unmeasured (the config-level
  comparison of `MDR-0011` exists separately).
- The probe code needed two NetLogo workarounds: BehaviorSpace
  constants can only vary interface widgets (three input boxes were
  injected), and `calculate-utility` is turtle-only (it writes
  turtles-own norm variables), so the probe wraps every call in `ask`.
  Neither affects the driven `set-theta`/`set-theta-index` logic.
- The two fixture counterexamples (2/118) where the old search's
  payoff exceeds the new search's are reported as the known sampled-
  search limitation of `MDR-0012`, not fixed here (validation only).
