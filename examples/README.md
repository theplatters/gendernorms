# GenderNorms example run

Demonstrates the run execution pipeline (see `ADR-0012`) on the
`GenderNormsModel` binding: a TOML run specification is loaded,
a seeded world is created, five `go` ticks run (see `MDR-0010`),
and working-time metrics are logged to a TOML record.

## Run

From the repository root:

```sh
julia --project=. examples/run_example.jl
```

## Produces

A short stdout summary (run id, status, ticks executed, final
metric values, record path) plus one record directory
`runs/<run-id>/run.toml` with the run identity, the echoed
specification, and the per-tick metric series. The `runs/`
directory is ignored by `.gitignore`; delete it to start clean.
