---
name: code-cleanliness
description: "Use when writing, refactoring, reviewing, or adding Julia code/files, choosing architecture, or when the registry validator fails. It enforces conventions, layering, and ADR recording."
---

# Code Cleanliness

## When to use

Use this skill when writing, refactoring, reviewing, or adding Julia
code and files, when choosing architecture or module layering, or when
`scripts/registry_check.jl` reports an error or warning.

## Normative sources

- `registry/code/README.md` - index and reading order.
- `registry/code/conventions.md` - naming, types, docstrings, formatting.
- `registry/code/architecture.md` - module layout, include order, layers.
- `registry/code/decisions/ADR-*.md` - Architecture Decision Records.
- Package `GenderNorms`; include order in `src/GenderNorms.jl` is normative;
  layers are `src/components.jl` -> `src/resources/` -> `src/systems/`.

## Cleanliness rules

- Follow naming and type rules in `conventions.md`; docstrings on all
  public functions and types.
- ASCII only; no tabs; no trailing whitespace; single trailing newline.
- No dead code, no commented-out blocks, no stray debug output.
- Every ported behavior cites its NetLogo procedure and ODD section.
- No silent divergence from the ODD or NetLogo; deviations need an MDR.

## Add a file

1. Place it in the correct layer (`components`, `resources`, or `systems`).
2. Add the `include(...)` in `src/GenderNorms.jl` at the right position.
3. Register the file and its responsibility in `architecture.md`.
4. Confirm `julia --project=. -e 'using GenderNorms'` still loads.

## Record an ADR

1. Copy `registry/templates/decision.md`; name the file
   `ADR-<NNNN>-<kebab-slug>.md` with the next free four-digit number.
2. Fill flat YAML frontmatter (`id`, `title`, `status`, `date`) and the
   `## Context`, `## Decision`, `## Consequences` body; see the
   registry-maintenance skill for the exact contract.
3. Structural or layering choices need an ADR before implementation.

## Validator

- Run `julia --project=. scripts/registry_check.jl`; exit 0 is clean.
- CI runs the validator with `--strict`, so treat warnings as errors too.
- Fix or explicitly resolve every finding before finishing.

## Commits

- One logical change per commit; keep a change and its registry update
  together and leave unrelated work in progress out.
- Imperative subject at most 72 characters; the body explains what and
  why and cites the governing `MDR-####` or `ADR-####`.
- Run `scripts/registry_check.jl --strict` and the package load check
  before committing. Stage explicit paths and start from `.gitmessage`.

## Checklist

- [ ] Conventions and architecture consulted; layering respected.
- [ ] New files included in the module and registered.
- [ ] ADR created for structural choices; MDR for behavior drift.
- [ ] Validator run; errors fixed; warnings explained.
- [ ] Commit is isolated, comprehensible, and validated.
