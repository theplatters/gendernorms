---
id: ADR-0008
title: Decision record lifecycle and mechanical checks
status: accepted
date: 2026-09-20
---

# ADR-0008: Decision record lifecycle and mechanical checks

## Context

`ADR-0004` established the registry and its validator. In practice the
lifecycle rules in the `registry-maintenance` skill (always supersede,
never rewrite) and actual use diverged: `ADR-0005` was rewritten and
renamed one day after it was accepted when the decision was reversed, and
`scripts/registry_check.jl --strict` still reported a clean registry while
`src/` implemented the opposite of the accepted record. The validator
also could not tell whether a record cited from `src/` or the registry
exists, or whether the index READMEs list every record. The hand-kept
indexes and the supersede metadata partly duplicate what git history
already provides.

## Decision

- Records stay identified by `<PREFIX>-<NNNN>`; code and registry cite the
  ID, not the filename.
- While a record is current and no later record supersedes it, amend it in
  place; the filename follows the title and git history keeps the earlier
  text.
- Once a record is superseded or otherwise relied upon, do not rewrite it:
  add the successor, set `supersedes` on it, and set `superseded_by` plus
  `status: superseded` on the old record.
- `scripts/registry_check.jl --strict` additionally errors when an
  `ADR-####` or `MDR-####` token under `src/` or `registry/` does not
  resolve to a record, and when a record file is missing from its
  registry's index README.
- Accepted decisions that constrain code structure are kept executable in
  `test/test_decision_invariants.jl`, which cites the governing record.
- `scripts/decisions_digest.jl` prints a compact digest of all records on
  demand instead of committing a generated index.

## Consequences

- Rewriting in place is the cheap path for decisions that are still being
  settled; superseding remains for decisions that other work or releases
  already rely on.
- Renames and index drift fail the validator instead of rotting silently.
- The validator still cannot check semantic agreement between a record's
  prose and `src/`; the invariant tests carry that part.
- The digest is not committed, so it cannot drift; reviewers and agents
  run it to see all records in one view.

## References

- `scripts/registry_check.jl`
- `scripts/decisions_digest.jl`
- `test/test_decision_invariants.jl`
- `registry/code/conventions.md`
- `.opencode/skills/registry-maintenance/SKILL.md`
- `ADR-0004`
