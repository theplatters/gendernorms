# Code Registry

This directory is the CODE half of the `registry/` system.
It records how the Julia implementation in `src/` is organized,
which conventions it follows, and which architecture decisions were made.

## Relation to `registry/model/`

- `registry/code/` covers the software side: file map, layering,
  naming and cleanliness rules, and Architecture Decision Records (ADRs).
- `registry/model/` covers the model side: ODD description, NetLogo mapping,
  and Model Decision Records (MDRs).
- Agent and model code must cite the NetLogo procedure and ODD section
  it ports (see `registry/code/conventions.md`).
  Divergences from the NetLogo or ODD behaviour require an MDR in
  `registry/model/`; structural code changes require an ADR here.

## Index

- `registry/code/architecture.md`: file map and layering of `src/`,
  module include order, and registration rules for new files.
- `registry/code/conventions.md`: normative naming, structure,
  documentation, formatting, and dead-code rules plus enforcement.
- `registry/code/decisions/ADR-0001-ark-ecs.md`: use Ark.jl ECS.
- `registry/code/decisions/ADR-0002-layered-package-structure.md`:
  `components` -> `resources` -> `systems` layering and include order.
- `registry/code/decisions/ADR-0003-utility-dispatch.md`:
  `UtilitySpec` subtype dispatch for utility forms.
- `registry/code/decisions/ADR-0004-registry-system.md`: this registry,
  ADR versus MDR split, and validator plus CI enforcement.
- `registry/code/decisions/ADR-0005-parametric-model-properties.md`:
  parametric `ModelProperties` resource that carries the network
  specification in its type parameter instead of an abstract field.

## How to add a new source file correctly

1. Decide the layer for the file: `components`, `resources`, or `systems`.
   The module root `src/GenderNorms.jl` holds the include list only.
   The standalone entry point `src/main.jl` is exempt from the include list.
2. Use a `snake_case.jl` file name with one concern per file.
   Keep to the naming, docstring, and formatting rules in
   `registry/code/conventions.md`.
3. Add the `include(...)` line to `src/GenderNorms.jl` in dependency order
   (`components` -> `resources` -> `systems`, no cycles).
   Every new `.jl` file under `src/`, except `src/main.jl`,
   must be added to the module include list.
4. Add a row for the file to the file-map table in
   `registry/code/architecture.md`, with its layer,
   responsibility, and status.
5. If the file introduces or changes an architectural pattern,
   record an ADR in `registry/code/decisions/` following the
   filename, frontmatter, and heading rules in `registry/code/conventions.md`.
   If it changes model behaviour, record an MDR in `registry/model/` instead.
6. Run `julia --project=. scripts/registry_check.jl` before finishing
   and fix any reported violation.
