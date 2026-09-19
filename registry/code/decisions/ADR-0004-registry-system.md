---
id: ADR-0004
title: Adopt split model and code registry with validator
status: accepted
date: 2026-09-19
---

# ADR-0004: Adopt split model and code registry with validator

## Context

Model semantics (ODD, NetLogo mapping, parameters) and code structure
(layering, conventions, file map) evolve for different reasons and need
different reviewers. Prior work referenced `ADR-0001`, `ADR-0002`, and
`ADR-0003` without a recorded home for such records, and the rules in
`registry/code/architecture.md` and `registry/code/conventions.md`
need mechanical enforcement so agents and CI catch drift early.

## Decision

Adopt the `registry/` system split into Model Decision Records (MDR)
under `registry/model/` and Architecture Decision Records (ADR) under
`registry/code/decisions/`. Use Markdown with flat YAML frontmatter
(`id`, `title`, `status`, `date`, plus optional `supersedes` and
`superseded_by`) and the required `## Context`, `## Decision`, and
`## Consequences` headings. Enforce the mechanically-checkable subset
with a Base-only Julia validator at `scripts/registry_check.jl`, run by
agents before finishing and by CI on PRs.

## Consequences

- Every structural or architectural change needs an ADR; every model
  behaviour, parameter, or porting choice needs an MDR. Silent
  divergence from the ODD or NetLogo is forbidden.
- The validator checks frontmatter, headings, file-map coverage of
  `src/`, exclusion annotations, ASCII, tabs, trailing whitespace, and
  final newlines; review covers what cannot be automated.
- Registry maintenance follows the shared contract: backticked IDs such
  as `ADR-0002`, backticked repo-relative paths such as
  `src/systems/initialisation.jl`, ASCII only, and one trailing newline.
