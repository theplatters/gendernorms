---
id: ADR-0027
title: Runic pre-commit hook for automatic formatting
status: accepted
date: 2026-10-05
supersedes: ""
superseded_by: ""
---

## Context

`registry/code/conventions.md` requires formatter-clean sources (ASCII,
spaces, no trailing whitespace, LF endings, one trailing newline), but
enforcement relied on author discipline and review. Formatting drift in
committed files creates review noise and risks validator churn, so the
agreed remedy is to enforce formatting at commit time with the Runic
formatter. The hook must stay out of the model package's dependency
graph: tooling dependencies do not belong in `Project.toml` or
`Manifest.toml`.

## Decision

1. **Tracked hook, local activation.** The hook lives in version control
   as `.githooks/pre-commit` and is activated per clone with
   `git config core.hooksPath .githooks` (local config, not committed).
2. **Runic in a separate `@runic` environment.** Runic runs in-process
   (`Runic.main`) from the dedicated Julia environment `@runic`
   (`~/.julia/environments/runic`) and is auto-installed there on first
   use with `Pkg.add("Runic")` by the entry point `scripts/format.jl`
   (Runic 1.5.1 is the version in use). Runic is deliberately
   NOT added to the project's `Project.toml`/`Manifest.toml`, to keep
   the model package's dependency graph and lockfile free of tooling
   dependencies.
3. **Format all, restage only staged.** On every commit the hook formats
   ALL `.jl` files in the working tree, skipping symlinked files during
   automatic directory scans so that files outside the repository are
   never written through a link, then re-stages only files that were
   already staged. Unstaged and untracked content never enters the
   commit: for EVERY staged `.jl` file the staged blob is extracted
   (`git cat-file blob`), formatted, and written back to the index
   (`git hash-object --no-filters -w` plus `git update-index
   --cacheinfo`) without applying working-tree filters, because the
   extracted blob is already in canonical repository form. Staged
   deletions are not resurrected.
4. **Separate-commit rule stays.** The "formatting sweep is a separate
   commit" rule in `registry/code/conventions.md` stays in force: the
   hook keeps everyday commits clean, while deliberate repo-wide
   reformatting remains its own isolated commit.

## Consequences

- Runic auto-installs into the separate `@runic` environment on first
  hook run; no project dependency or lockfile entry is needed, and the
  package load path is unaffected.
- Every clone must run `git config core.hooksPath .githooks` once; until
  then commits are unguarded, so reviewers should check that new
  contributors have activated the hook.
- The hook only covers commits, not pushes or CI: `scripts/registry_check.jl`
  (run with `--strict` in CI) keeps enforcing the mechanically
  checkable cleanliness rules independently of the hook.
- Partially staged files are safe by construction: every staged `.jl`
  blob is formatted and re-staged, so unstaged work never leaks into a
  commit and deleted files stay deleted.
- Unmerged paths (conflict states) and index entries whose mode is not
  `100644`/`100755` (symlinks, gitlinks/submodules) are skipped
  untouched.
- Runic failures (for example a parse error in some file) do not block
  the commit: they warn and the commit proceeds, so an unparseable
  unrelated file cannot block all commits. The only blocking failure
  is `julia` missing from `PATH`.

## Alternatives considered

- **Runic in `Project.toml`.** Rejected: a formatter dependency would
  pollute the model package's dependency graph and lockfile with pure
  tooling (see `ADR-0012`/`ADR-0013` for the precedent of keeping
  run tooling outside `src/`).
- **Check-only hook.** Rejected: a hook that only rejects unformatted
  commits forces manual fixup loops on the author; auto-formatting keeps
  the tree clean with no extra round trip.
- **Untracked `.git/hooks`.** Rejected: hooks installed by hand into
  `.git/hooks` are invisible to version control and diverge across
  clones; the tracked `.githooks/` directory plus one documented local
  config command keeps the hook shared and reviewable.
