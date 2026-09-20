# AGENTS.md - Constitution for GenderNorms

`registry/` is the single source of truth for all model and code decisions.
The model registry defines intended behavior; the code registry defines how
it must be implemented. Code cleanliness is enforced by review and by the
`scripts/registry_check.jl` validator, not left to taste.

## Repo map

- Julia package `GenderNorms`; module declared in `src/GenderNorms.jl`.
- Include order in `src/GenderNorms.jl` is normative; respect the layers
  `src/components.jl` -> `src/resources/` -> `src/systems/`.
- `src/resources/shock.jl` is unwired (undefined `ShockType`/`SHOCK_NO`,
  not included); `src/main.jl` is empty. See `registry/model/discrepancies.md`.
- Early-stage partial port: much of the ODD submodels is not yet ported.
- Normative model spec: `odd_model_description.typ`.
- Reference implementation: `gender_model_shocks_preferences.nlogox`.
- Julia 1.12; `julia --project=. -e 'using GenderNorms'` must load.

## Read before you change

- Before changing model behavior, consult `registry/model/` in order:
  `README.md`, `entities.md`, `parameters.md`, `processes.md`,
  `discrepancies.md`, then `decisions/MDR-*.md`.
- Before changing code structure, consult `registry/code/` in order:
  `README.md`, `architecture.md`, `conventions.md`, then `decisions/ADR-*.md`.
- For model semantics, consult `odd_model_description.typ` first and cite
  the ODD section. For ported logic, also check the NetLogo procedure.
- For a compact view of all tasks and decisions, run
  `julia scripts/registry_digest.jl`.

## Record decisions

- Model behavior, parameter, or porting choices -> MDR in
  `registry/model/decisions/` (prefix `MDR`).
- Structural or architectural choices -> ADR in
  `registry/code/decisions/` (prefix `ADR`).
- Start from `registry/templates/decision.md`; keep the filename, frontmatter,
  and heading contract described in the registry-maintenance skill.
- Recorded but unimplemented work -> a task in `registry/tasks.md`
  (prefix `TASK`).
- Never diverge silently: record first, then implement.

## Keep the registry in sync

- New Julia file: include it in `src/GenderNorms.jl` at the right layer and
  register it in `registry/code/architecture.md`.
- New or changed entity, parameter, or process: register it in
  `registry/model/entities.md`, `parameters.md`, or `processes.md`.
- Known NetLogo-vs-Julia gaps go in `registry/model/discrepancies.md`;
  record them, do not silently fix or hide them.
- New or completed work item: add or close its row in
  `registry/tasks.md`; a `TODO`/`FIXME` comment in `src/` must cite an
  open `TASK-####`.

## Cleanliness summary

- Follow `registry/code/conventions.md`: naming, types, docstrings on all
  public functions and types.
- No tabs, no trailing whitespace, ASCII only, single trailing newline.
- No dead code, no commented-out blocks, no stray debug output.
- Every ported behavior cites its NetLogo procedure and ODD section.
- No silent divergence from the ODD or NetLogo; deviations need an MDR.

## Verify before finishing

Run both before declaring work done:

```sh
julia --project=. scripts/registry_check.jl
julia --project=. -e 'using GenderNorms'
```

Fix all validator errors and warnings; CI runs `--strict`, so warnings are blocking.

## Commits

- One logical change per commit; keep a change and its registry update
  together. Do not sweep unrelated work in progress into your commit.
- Imperative subject line, at most 72 characters, no trailing period;
  explain what and why in the body and cite the governing `MDR-####` or
  `ADR-####`.
- Every commit must leave a working tree: run the validator and the
  package load check (and the test suite once it exists) before
  committing.
- Stage explicit paths; never `git add -A` over unrelated edits. Start
  from `.gitmessage` and follow `registry/code/conventions.md` and the
  `commit` command.

## Skills

- `model-registry`: model edits, ports, ODD semantics, MDRs.
- `code-cleanliness`: Julia code, files, architecture, ADRs, validator output.
- `registry-maintenance`: creating or superseding ADR/MDR records, fixing
  validator errors category by category.
