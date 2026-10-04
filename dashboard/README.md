# GenderNorms dashboard

An interactive, web-independent-of-the-core dashboard for launching,
watching, and comparing GenderNorms runs. Runs are configured in a form,
executed in isolated worker processes behind a FIFO queue (one run at a
time), and animated live in three Plotly panels (working time of men,
women, and the gap). Recorded runs under `runs/` can be loaded and
overlaid, and any run's configuration can be cloned and adapted.

The dashboard is separate tooling on top of the public run API only
(`ADR-0025`); the core package in `src/` is untouched, so core runs and
benchmarks carry no dashboard overhead by construction. Implementation
is tracked as `TASK-0028`.

## Install

The dashboard is its own Julia project with its own environment
(Genie, Stipple, StippleUI, StipplePlotly; GenderNorms by path
dependency). From the repository root:

```sh
julia --project=dashboard -e 'using Pkg; Pkg.instantiate()'
```

## Run

```sh
julia --project=dashboard dashboard/bin/serve.jl
```

The server binds `127.0.0.1:8000` by default and prints the URL. Options:

```sh
julia --project=dashboard dashboard/bin/serve.jl --host=127.0.0.1 --port=8000 --runs-root=/path/to/runs
```

`--runs-root` defaults to the repository's `runs/`. Stop the server with
Ctrl-C: shutdown cancels and reaps every queued and running job and
detaches the page presentation tasks.

## Usage

- **Launching runs with adapted configurations.** Fill the form and
  press *Submit*. The form is validated server-side; problems are listed
  on the page and nothing is queued until the configuration is valid.
  One run executes at a time; further submissions queue in FIFO order
  and the job table shows the honest queue position.
- **Live animation.** Execution and display are separate cursors: the
  model runs at full speed in its worker while the panels reveal the
  buffered rows at a paced rate (about 20 frames per run), so a fast run
  animates without ever slowing down. While catching up the run is
  labeled *replaying buffered metrics*; *Jump to latest* snaps the
  cursors to the newest rows.
- **Loading and overlaying recorded runs.** The run list shows the live
  jobs and the records under `runs/`. *Plot* adds a run to the panels
  (at most 8 at once), *Hide*/*Show* toggles it across all panels, and
  *Load* reads a record by id. *Replay* plays a plotted run again from
  its first row.
- **Cloning configurations.** *Clone* copies a run's model settings,
  seed, and metric selection into the form under a copied name for
  adaptation. Cloning needs the run's validated specification: records
  without one (or with an invalid one) disable the action and report
  why.
- **Cancellation.** *Cancel* on a job (or *Cancel active run*) stops a
  queued or running job; its partial metrics stay visible as a visibly
  cancelled incomplete run and are never recorded.
- **Recording policy.** With the recording checkbox on, each run is
  written via `GN.TomlLogger` into `runs/.dashboard-staging/<job-uuid>/`
  and promoted atomically to `runs/<run-uuid>/` only after clean
  completion or a recorded model failure. Cancelled and broken runs are
  left in staging (invisible to the catalog); recorded output
  directories are never reused.

## Configuration reference

Blank form fields are omitted and the model defaults apply. The form
maps onto run specification keys as follows (see
`GenderNorms.parse_spec` for the accepted values):

| Form field | Spec key |
| --- | --- |
| Name | `[run] name` |
| Seed | `[run] seed` |
| Ticks | `[runtime] ticks` |
| Agents per gender | `[model] agents_per_gender` |
| Standard deviation | `[model] std_dev` |
| Initial transfer | `[model] initial_transfer` |
| Initial lambda | `[model] initial_lambda` |
| Network type | `[model.network] type` |
| p | `[model.network] p` (random only) |
| Neighbors per side, Rewiring | `[model.network] neighbors_per_side`, `rewiring` (watts_strogatz only) |
| m | `[model.network] m` (preferential_attachment, homophily, similarity only) |
| Trait | `[model.network] trait` (similarity only) |
| Utility type | `[model.utility] type` |
| Weight self/partner/transfer | `[model.utility] w_self`, `w_partner`, `w_transfer` |
| Beta (CES only) | `[model.utility] beta` (ces only) |
| Paid time (men/women) | `[model.paid_time] men`, `women` |
| Mean wage (men/women) | `[model.mean_wage] men`, `women` |
| Mean preference (men/women) | `[model.mean_preference] men`, `women` |
| Initial conformism (men/women) | `[model.initial_conformism] men`, `women` |
| Metrics | `[logging] metrics` |
| Record each run | `[logging] outputs` (dashboard-managed staging policy) |

Only the parameters of the selected network and utility types are
submitted, so stale hidden fields never reach the model.

## Testing

```sh
julia --project=dashboard -e 'using Pkg; Pkg.test()'
```

The suite covers the web-free runtime layer plus the UI layer (plot
construction, presentation pacing, and a headless HTTP smoke of the
Genie app).

## Benchmarks

Take benchmark measurements with dashboard workers stopped: a running
dashboard job occupies CPU and will contaminate timings.
