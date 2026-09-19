---
description: Create clear, isolated, comprehensible commits for the current changes.
agent: build
---

Create one or more commits for the current working-tree changes, following
`registry/code/conventions.md` and `AGENTS.md`.

1. Inspect `git status`, `git diff`, and `git log --oneline -10`.
2. Group the changes into isolated logical commits. Do not mix unrelated
   concerns, and leave unrelated work in progress unstaged.
3. For each group, stage explicit paths. If a change needs a registry
   update (an MDR/ADR or a table row), include it in the same commit.
4. Verify the tree is green before committing:
   `julia --project=. scripts/registry_check.jl --strict` and
   `julia --project=. -e 'using GenderNorms'`.
5. Write the message from `.gitmessage`: an imperative subject of at most
   72 characters, then a body explaining what and why and citing the
   governing `MDR-####` or `ADR-####`.
6. Do not amend, force-push, or rebase shared history unless asked.
7. Report the commits created and the files in each.
