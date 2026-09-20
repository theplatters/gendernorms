---
id: ADR-0009
title: Task ledger for recorded but unimplemented work
status: accepted
date: 2026-09-20
---

# ADR-0009: Task ledger for recorded but unimplemented work

## Context

Unimplemented work is recorded in several places: the port statuses in
`registry/model/processes.md`, `entities.md`, and `parameters.md`, the
findings in `registry/model/discrepancies.md`, and decision consequences
such as the deferred transfer stage in `ADR-0007`. None of them is an
actionable work queue, and `src/` has no convention for `TODO` comments,
so the next unit of work has to be reconstructed from status columns. The
validator introduced by `ADR-0008` checks decisions, not work items.

## Decision

- Track recorded but unimplemented work in `registry/tasks.md` as
  `TASK-NNNN` rows with status `open`, `in progress`, `blocked`, or
  `done`. Ids are zero-padded, sequential, and never reused; a closed
  task keeps its row with status `done`.
- A task row names the work and cites its evidence: the discrepancy,
  process row, parameter row, or decision that motivates it.
- A `TODO` or `FIXME` comment in `src/` must cite an open `TASK-####` on
  the same line. Untracked comments and references to closed tasks are
  validator errors.
- `scripts/registry_check.jl --strict` additionally checks that task ids
  are unique and their statuses valid, and that every `TASK-####` token
  under `src/` or `registry/` resolves to a ledger row.
- `scripts/registry_digest.jl` prints the ledger together with the
  decision records.

## Consequences

- The work queue is one file; discrepancies stay findings and tasks stay
  the actions derived from them, so neither duplicates the other's
  wording.
- Dropping a planned follow-up requires deleting its ledger row or its
  citation, both visible in review, instead of silently emptying a status
  column.
- Closing a task is a code change plus a ledger update in the same
  commit; the digest shows what is still open.

## References

- `registry/tasks.md`
- `scripts/registry_check.jl`
- `scripts/registry_digest.jl`
- `registry/code/conventions.md`
- `registry/model/discrepancies.md`
- `ADR-0008`
