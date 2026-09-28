# Tasks

Actionable work that is recorded but not implemented. Findings and open
questions stay in `registry/model/discrepancies.md`; this ledger is the
work queue derived from them, from decision consequences, and from the
port status in `registry/model/`. A task is closed by implementing and
verifying it, then setting its status to `done`; the row is kept as
history. Code comments mark work in place as `TODO TASK-0007: ...` and
must cite an open task (see `ADR-0009`).

Statuses: `open`, `in progress`, `blocked`, `done`.

## Model tasks

| Id | Status | Task | Evidence |
| --- | --- | --- | --- |
| `TASK-0001` | open | Port Statistics remainder: 10-element histories and moving averages, `global-mean-transfer` storage, and the ODD observer sets (shock propagation, employment types, median-split subgroups); the lightweight core (lag copy plus `WorkingTimeStats` men/women/gap means) is ported, see `MDR-0007` | `registry/model/processes.md` (`update-statistics`); `registry/model/entities.md`; ODD Statistics |
| `TASK-0002` | done | Port Transfer bargaining (`set-theta`, `calculate-payoff`) and use or remove the `Theta` component | `registry/model/processes.md`; `registry/model/discrepancies.md`; `src/components.jl`; ODD Transfer bargaining; `MDR-0005` |
| `TASK-0003` | done | Port Shocks (`start-shock`, `end-shock`): typed `WageShock`/`PreferenceShock` resources, `DirectlyAffected` tag, and `start_shock!`/`recover_shock!`/`update_shocks!` plus ported-but-unscheduled `update_wages!`, see `MDR-0009` | `registry/model/processes.md`; `registry/model/parameters.md`; `src/resources/shock.jl`; `src/systems/shocks.jl`; `MDR-0009` |
| `TASK-0004` | open | Port endogenous preference adaptation (`update-preferences`) | `registry/model/processes.md`; `registry/model/parameters.md` (`lambda`) |
| `TASK-0005` | open | Schedule wage growth: `update_wages!` is ported but unscheduled because NetLogo `go` never calls `update-wages`, see `MDR-0009` | `registry/model/processes.md`; `registry/model/parameters.md` (`wage-growth-rate`); `src/systems/shocks.jl`; `MDR-0009` |
| `TASK-0006` | open | Port the specific-couple probe override (`ProbeCouple`) or record its removal | `registry/model/discrepancies.md`; `registry/model/parameters.md`; ODD Initialization item 7 |
| `TASK-0007` | in progress | Port the remaining `setup` inputs: the fixed-seed RNG path is now provided by the run pipeline (required `seed` in the run specification, `create_world` seeding, see `ADR-0012`); the CSV import mode and the wiring of `select_affected!` into the setup sequence remain | `registry/model/processes.md` (`setup`); `registry/model/parameters.md` (`import-csv`, `fixed-rs`, `random-seed-fixed`); `src/systems/shocks.jl`; `MDR-0009`; `ADR-0012` |
| `TASK-0008` | open | Record the retained ODD quirks (items 1-12) as MDRs under `MDR-0003` | `registry/model/discrepancies.md`; `MDR-0003` |
| `TASK-0009` | open | Decide the recorded open questions in MDRs: the infeasibility penalty `-Inf` vs `-200`, and `rho` vs `lambda` before porting experiments | `registry/model/discrepancies.md`; `registry/model/parameters.md`; ODD Parameters table |

## Code tasks

| Id | Status | Task | Evidence |
| --- | --- | --- | --- |
| `TASK-0010` | in progress | Wire the model loop: the tick-order scheduling of `calculate_norm_perception!` and `set_theta!` is decided in `MDR-0010` and implemented as the `step_model!` go port; restoring the deferred ODD quirk 11 overwriting and implementing `src/main.jl` remain | `registry/model/discrepancies.md`; `MDR-0004`; `MDR-0010`; `ADR-0012`; `ADR-0007`; `registry/code/architecture.md`; ODD Process overview and scheduling |
| `TASK-0011` | open | Experiment infrastructure on top of the run pipeline: parameter sweeps and Monte Carlo runners, additional logging backends (CSV, database), and JSON/YAML run-specification parsers | `registry/code/decisions/ADR-0012-run-execution-pipeline.md`; `registry/model/decisions/MDR-0001-normative-model-specification.md` (ODD experiments section) |
| `TASK-0012` | done | Benchmark harness and performance report (`benchmark/`): headless NetLogo vs Julia runtime comparison on a matched config matrix, raw per-run CSVs, and a merged summary | `benchmark/report.md`; `benchmark/README.md`; `registry/code/decisions/ADR-0013-benchmark-harness.md`; `registry/model/decisions/MDR-0011-benchmark-methodology.md` |
| `TASK-0013` | done | Multithread the per-tick world loops `set_theta!` and `calculate_norm_perception!` with `Threads.@threads :greedy` over disjoint households/agents, with per-iteration `spouse_seen` scratch and cross-thread-count determinism tests | `src/systems/norm_perception.jl`; `src/systems/household_bargaining.jl`; `test/test_threading.jl`; `benchmark/threading_speedup.jl`; `ADR-0014` |
