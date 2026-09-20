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
| `TASK-0001` | open | Port Statistics: compute and update `WorkingTimeStats` and the ODD observer sets (shock propagation, employment types, median-split subgroups) | `registry/model/processes.md` (`update-statistics`); `registry/model/entities.md`; ODD Statistics |
| `TASK-0002` | open | Port Transfer bargaining (`set-theta`, `calculate-payoff`) and use or remove the `Theta` component | `registry/model/processes.md`; `registry/model/discrepancies.md`; `src/components.jl`; ODD Transfer bargaining |
| `TASK-0003` | open | Port Shocks (`start-shock`, `end-shock`): define `ShockType`, make `src/resources/shock.jl` load, and include it in the module | `registry/model/processes.md`; `registry/model/parameters.md`; `registry/model/discrepancies.md` |
| `TASK-0004` | open | Port endogenous preference adaptation (`update-preferences`) | `registry/model/processes.md`; `registry/model/parameters.md` (`lambda`) |
| `TASK-0005` | open | Port wage growth (`update-wages`) | `registry/model/processes.md`; `registry/model/parameters.md` (`wage-growth-rate`) |
| `TASK-0006` | open | Port the specific-couple probe override (`ProbeCouple`) or record its removal | `registry/model/discrepancies.md`; `registry/model/parameters.md`; ODD Initialization item 7 |
| `TASK-0007` | open | Port the remaining `setup` inputs: the CSV import mode and the fixed-seed RNG path | `registry/model/processes.md` (`setup`); `registry/model/parameters.md` (`import-csv`, `fixed-rs`, `random-seed-fixed`) |
| `TASK-0008` | open | Record the retained ODD quirks (items 1-12) as MDRs under `MDR-0003` | `registry/model/discrepancies.md`; `MDR-0003` |
| `TASK-0009` | open | Decide the recorded open questions in MDRs: `MeanPreference.men` 0.44 vs 0.45, the infeasibility penalty `-Inf` vs `-200`, and `rho` vs `lambda` before porting experiments | `registry/model/discrepancies.md`; `registry/model/parameters.md`; ODD Parameters table |

## Code tasks

| Id | Status | Task | Evidence |
| --- | --- | --- | --- |
| `TASK-0010` | open | Wire the model loop: schedule `calculate_norm_perception!` and `choose_bundles`, apply the labour results, restore the deferred ODD quirk 11 overwriting, and implement `src/main.jl` | `registry/model/discrepancies.md`; `MDR-0004`; `ADR-0007`; `registry/code/architecture.md`; ODD Process overview and scheduling |
