# GenderNorms dashboard

An interactive, web-independent-of-the-core dashboard for launching,
watching, and comparing GenderNorms runs. Runs are configured in a form,
executed in isolated worker processes behind a FIFO queue (one run at a
time), and animated live in user-composed Plotly charts. Recorded runs
under `runs/` can be loaded and overlaid, and any run's configuration
can be cloned and adapted.

The dashboard is architecturally separate from the core package (own
project and dependencies, public run API only, `ADR-0025`); core
performance is unaffected by the dashboard, so core runs and benchmarks
carry no dashboard overhead by construction. Implementation is tracked
as `TASK-0028`.

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

## Layout

The page has three regions. The top row is a two-column grid: the
configuration form in the narrow left column beside the plot area in
the wide right column (about twice the width). The plot area shows one
chart at a time, 560 px tall, so the plot dominates the page. Below
both columns sits the full-width run log: the job table and the run
list with their row actions and notes.

## Usage

- **Launching runs with adapted configurations.** Fill the form and
  press *Submit*. The form is validated server-side; problems are listed
  on the page and nothing is queued until the configuration is valid.
  One run executes at a time; further submissions queue in FIFO order
  and the job table shows the honest queue position.
- **Live animation.** Execution and display are separate cursors: the
  model runs at full speed in its worker while the charts reveal the
  buffered rows at a paced rate (about 20 frames per run), so a fast run
  animates without ever slowing down. While catching up the run is
  labeled *replaying buffered metrics*; *Jump to latest* snaps the
  cursors to the newest rows. The reveal cursor is per run and shared
  by every plot that shows the run; *Replay* restarts it per run. A
  browser whose connection drops catches up by itself on reconnect:
  the page asks the server for a full resync of rows, charts, and
  status, without a reload or a click.
- **Plots and line selection.** Only one plot is visible at a time. The
  "+" button beside the plot tab strip creates further plots (at most
  8; each tab's "x" deletes one, the last plot stays). Every plot owns
  its own line selection: each line (one metric of one run) is shown or
  hidden by its own tickbox under the chart (clicking the tickbox or
  its label toggles it), grouped by run. Every plotted line has its own
  color, assigned per line identity when it first appears in the
  session and kept across tickbox changes, plot switches, and
  republishes (a palette of ten distinguishable colors, cycled for
  plots with more lines). The chart legend is labels-only (legend
  clicks do not hide lines), so the tickboxes alone decide what a chart
  shows. The run list's *Plot* action checks that run's lines in the
  active plot, *Unplot* removes the run and its lines from every plot,
  and a new plot starts with the available lines checked. Selecting
  runs is limited to 8 at once.
- **Loading and overlaying recorded runs.** The run log shows the live
  jobs and the records under `runs/`; the record list keeps itself
  fresh while the page runs, so a completed run shows up within seconds
  without a manual refresh. *Plot* adds a run to the charts (at most 8
  at once), *Load* reads a record by id, and *Replay* plays a plotted
  run again from its first row.
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

## Metrics reference

The model produces eight per-tick metrics; each run logs the ones
selected in the form's Metrics checkboxes. The dashboard renders each
metric with the unit class below; `METRIC_META` in
`dashboard/src/plotting.jl` is the single source.

| Metric | Title | Unit class | Values |
| --- | --- | --- | --- |
| `working_time_men` | Working time (men) | `:proportion` | mean committed labour fraction of men in [0, 1] |
| `working_time_women` | Working time (women) | `:proportion` | mean committed labour fraction of women in [0, 1] |
| `working_time_gap` | Working time gap | `:signed_fraction` | men minus women in [-1, 1] |
| `preference_men` | Preference (men) | `:proportion` | pre-adaptation mean preference-private of men in [0, 1] |
| `preference_women` | Preference (women) | `:proportion` | pre-adaptation mean preference-private of women in [0, 1] |
| `utility_men` | Utility (men) | `:value` | per-sex mean individual utility at the committed bundle |
| `utility_women` | Utility (women) | `:value` | per-sex mean individual utility at the committed bundle |
| `transfer_mean` | Mean transfer | `:signed_fraction` | women-only mean transfer coefficient in [-1, 1] |

Records written before these metrics existed carry only their own
columns: loading them works unchanged and their tickboxes offer only
the lines the record actually has. Unknown future metric names plot
with `:value` behavior and a title derived from the name.

### Axis and hover behavior

- All visible lines `:proportion`: the y-axis is fixed to 0% to 100%
  (data range [0, 1]) with percent tick labels.
- Any `:signed_fraction` line visible (mixed with proportions, or
  alone): the y-axis is fixed to -100% to 100% (data range [-1, 1])
  with percent tick labels.
- Any `:value` line visible (or an empty plot): raw values with an
  automatic range.
- Hover values are formatted per metric: one decimal percent for
  fraction-class metrics (e.g. `25.0%`, `-25.0%`), raw numbers for
  `:value` metrics. Non-finite values render as gaps in the line.

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

The suite covers the web-free runtime layer plus the UI layer (metric
metadata and per-plot line construction, plot management, presentation
pacing, and a headless HTTP smoke of the Genie app).

## Benchmarks

Take benchmark measurements with dashboard workers stopped: a running
dashboard job occupies CPU and will contaminate timings.
