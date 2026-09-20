---
name: registry-maintenance
description: "Use when adding, updating, or superseding a decision record (ADR/MDR), or when `scripts/registry_check.jl` reports errors. It explains the record contract, lifecycle, and validator fixes."
---

# Registry Maintenance

## When to use

Use this skill when adding, updating, or superseding a decision record
(ADR or MDR), or when `scripts/registry_check.jl` reports errors
or warnings.

## Record types and ID scheme

- MDR (model) lives in `registry/model/decisions/`; ADR (code) lives in
  `registry/code/decisions/`.
- Filename: `<PREFIX>-<NNNN>-<kebab-slug>.md`, e.g.
  `MDR-0007-shock-timing.md`; `PREFIX` is `MDR` or `ADR`.
- Numbers are zero-padded, sequential per prefix, never reused.

## Frontmatter and heading contract

- Start from `registry/templates/decision.md`.
- Flat YAML frontmatter between `---` lines with required non-empty keys
  `id`, `title`, `status`, `date`.
- `status` is one of `proposed`, `accepted`, `rejected`, `superseded`,
  `deprecated`; `date` is `YYYY-MM-DD`; `id` matches the filename
  prefix (e.g. filename `ADR-0003-x` has `id: ADR-0003`).
- Body must contain `## Context`, `## Decision`, and `## Consequences`.
- Keep extra keys (`supersedes`, `superseded_by`) flat scalar strings
  (an empty `""` when unused); no nested maps or lists.

## Status lifecycle

- `proposed` -> `accepted` (implement) or `rejected` (drop with reason).
- `accepted` -> `deprecated` (retire) or `superseded` (replace).
- To supersede: create the new record, set `supersedes: [OLD-ID]` on it,
  set `superseded_by: [NEW-ID]` and `status: superseded` on the old one,
  and link both files by ID.
- While a record is current and no later record supersedes it, amend it in
  place and rename the file with its title; git history keeps the earlier
  text. Supersede once other work or a release relies on the record (see
  `ADR-0008`).

## Fixing validator errors

- Missing frontmatter keys or bad `status`/`date`: correct the four keys
  to match the filename and the allowed values.
- Bad filename or ID mismatch: rename the file or fix `id` so they agree.
- Missing headings: restore `## Context`, `## Decision`, `## Consequences`.
- Broken registry links: update `architecture.md`, `entities.md`,
  `parameters.md`, `processes.md`, or `discrepancies.md` references to
  point at existing files, includes, and record IDs.
- Run `julia --project=. scripts/registry_check.jl` and use `--strict`
  (as CI does), where warnings become errors.

## Checklist

- [ ] Correct prefix, number, slug, and matching `id`.
- [ ] Frontmatter complete, flat, valid `status` and `date`.
- [ ] Required headings present; supersede links bidirectional.
- [ ] Validator clean (`--strict` for release).
