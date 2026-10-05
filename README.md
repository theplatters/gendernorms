# gendernorms

This is the model code of the working paper "Endogenous Heterogeneous Gender Norms and Female Labor Supply in an Intra-Household Bargaining Model" by Theresa Hager, Patrick Mellacher and Magdalena Rath.

## Development

See `AGENTS.md` for the contributor constitution and `registry/README.md`
for the model and code registries. Verify changes with
`julia --project=. scripts/registry_check.jl`.

## Dashboard

`dashboard/` hosts the interactive Genie/Stipple dashboard for
launching, watching, and comparing runs (`ADR-0025`, `TASK-0028`). The
dashboard is architecturally separate from the core package (own
project and dependencies); core performance is unaffected by the
dashboard. See `dashboard/README.md`.
