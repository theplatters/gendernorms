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
| `TASK-0007` | open | Port the remaining `setup` inputs: the CSV import mode, the fixed-seed RNG path, and the wiring of `select_affected!` into the setup sequence | `registry/model/processes.md` (`setup`); `registry/model/parameters.md` (`import-csv`, `fixed-rs`, `random-seed-fixed`); `src/systems/shocks.jl`; `MDR-0009` |
| `TASK-0008` | open | Record the retained ODD quirks (items 1-12) as MDRs under `MDR-0003` | `registry/model/discrepancies.md`; `MDR-0003` |
| `TASK-0009` | open | Decide the recorded open questions in MDRs: the infeasibility penalty `-Inf` vs `-200`, and `rho` vs `lambda` before porting experiments | `registry/model/discrepancies.md`; `registry/model/parameters.md`; ODD Parameters table |

## Code tasks

| Id | Status | Task | Evidence |
| --- | --- | --- | --- |
| `TASK-0010` | open | Wire the model loop: schedule `calculate_norm_perception!` and `set_theta!` in the tick order, restore the deferred ODD quirk 11 overwriting, and implement `src/main.jl` | `registry/model/discrepancies.md`; `MDR-0004`; `ADR-0007`; `registry/code/architecture.md`; ODD Process overview and scheduling |
