# Registry

The registry is the single source of truth for model and code decisions in
this repository. It records what the model is intended to do, how the Julia
port must implement it, and why past choices were made, so that humans and
agents do not have to reverse-engineer intent from `src/` alone and do not
let the port drift silently away from the specification.

The registry has two halves:

- `registry/model/` -- model truth: entities, parameters, processes,
  discrepancies, and model decision records (MDRs). See
  `registry/model/README.md`.
- `registry/code/` -- code truth: architecture, conventions, and code decision
  records (ADRs). See `registry/code/README.md`.

Reusable scaffolding lives in `registry/templates/decision.md`.

## Directory map

- `registry/README.md` -- this index.
- `registry/templates/decision.md` -- copy-ready template for MDR/ADR records.
- `registry/model/README.md` -- purpose of the model registry and sync rules.
- `registry/model/entities.md` -- entity and state-variable mapping table.
- `registry/model/parameters.md` -- parameter default mapping table.
- `registry/model/processes.md` -- NetLogo procedure to Julia mapping table.
- `registry/model/discrepancies.md` -- known model-vs-code gaps, unwired items.
- `registry/model/decisions/MDR-*.md` -- model decision records.
- `registry/code/README.md` -- code registry index.
- `registry/code/architecture.md` -- code structure.
- `registry/code/conventions.md` -- cleanliness rules.
- `registry/code/decisions/ADR-*.md` -- code decision records.

## How to use

For agents:

1. Before changing model behavior, read `registry/model/README.md`, then
   `registry/model/entities.md`, `registry/model/parameters.md`,
   `registry/model/processes.md`, `registry/model/discrepancies.md`, then the
   `registry/model/decisions/` records in numeric order.
2. Before changing code structure, read `registry/code/README.md`,
   `registry/code/architecture.md`, and `registry/code/conventions.md`.
3. Record first, then implement: any intentional divergence from the ODD or
   the reference implementation needs a new MDR (model) or ADR (code) before
   the code change. Never diverge silently.
4. Keep the registry in sync: new Julia files, entities, parameters, or
   processes must be registered; known gaps go to
   `registry/model/discrepancies.md`.

For humans:

1. Start here for orientation, then follow the model or code sub-README.
2. Use the MDR/ADR records as the changelog of intent: each one states its
   context, decision, and consequences.
3. In review, check that behavior changes cite an MDR and structural changes
   cite an ADR, and that tables still match `src/`.

## Decision-record ID scheme

- `MDR-NNNN-kebab-slug.md` -- Model Decision Record: model behavior,
  parameter, or porting choices. Example: `MDR-0001`.
- `ADR-NNNN-kebab-slug.md` -- Architecture Decision Record: structural or
  code-organization choices. Example: `ADR-0001`.
- Numbering is zero-padded and sequential within each prefix. The `id`
  frontmatter field must equal the filename prefix.
- Cross-reference records by backticked ID, e.g. `MDR-0001`. Reference repo
  files as backticked repo-relative paths, e.g. `src/components.jl`.

## Status legend

- `proposed` -- under discussion, not yet binding.
- `accepted` -- binding; seeded records use this.
- `rejected` -- considered and turned down; kept for history.
- `superseded` -- replaced by a newer record (see its `superseded_by` field).
- `deprecated` -- no longer applicable, without a direct replacement.

## Validation

Run the registry validator and the package load check before finishing work:

- `julia --project=. scripts/registry_check.jl`
- `julia --project=. -e 'using GenderNorms'`

Fix validator errors and warnings; CI runs `--strict`, so warnings are blocking.

## Further reading

- `AGENTS.md` -- repo constitution and required read-before-you-change order.
- `registry/model/README.md` -- model registry purpose and sync rules.
- `registry/code/README.md` -- code registry index.
- `registry/code/conventions.md` -- naming, types, docstrings, cleanliness.
- `registry/templates/decision.md` -- decision-record template.
