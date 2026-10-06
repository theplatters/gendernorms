---
id: ADR-0027
title: Pre-commit hook for automatic formatting and a blocking test gate
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
formatter. The commit rules further require every commit to leave a
working tree, which in practice means running the Julia test suite
before committing; the suite now exists (`test/runtests.jl`, wired into
`Project.toml` via `[extras]`/`[targets]`), and leaving its execution
to author discipline is as unreliable as leaving formatting was. The
hook must stay out of the model package's dependency graph: tooling
dependencies do not belong in `Project.toml` or `Manifest.toml`.

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
3. **Blocking test gate before formatting.** Every commit runs the test
   suite with `julia --project=. test/runtests.jl` directly against the
   committed project (no `Pkg.test()`, no dependency resolution or
   installation) and blocks the commit with a non-zero exit when the
   suite fails. The suite runs unconditionally on every commit,
   regardless of which paths are staged. The test step runs BEFORE any
   formatting touches the working tree or the index, so a failed suite
   leaves both exactly as they were. `git commit --no-verify` is the
   only bypass.
4. **Format all, restage only staged.** On every commit the hook formats
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
5. **Separate-commit rule stays.** The "formatting sweep is a separate
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
  unrelated file cannot block all commits. Exactly two failures block
  the commit: `julia` missing from `PATH` and a failing test suite.
- Every commit pays the wall-clock cost of one full test suite run:
  `julia --project=. test/runtests.jl` takes about 1m30s on the
  development machine, whatever the staged paths are.
- The test gate tests the WORKING TREE: `julia --project=.
  test/runtests.jl` reads working-tree files, while the commit contains
  the staged content, which may differ. A commit can therefore pass the
  gate without testing exactly what it commits; this is inherent to
  running the suite from the working tree and is accepted here.

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
- **`Pkg.test()` instead of `julia --project=. test/runtests.jl`.**
  Rejected: `Pkg.test()` resolves dependencies and runs the suite in a
  temporary environment instead of against the committed project (and
  measured 2m15s on the development machine, against 1m30s for the
  direct entry point); the hook must neither resolve nor install
  anything.
- **Warn and continue on test failure.** Rejected: a gate that only
  warns never stops a broken commit, while the commit rules require
  every commit to leave a working tree. Formatting stays warn-and-
  continue on purpose (an unparseable unrelated file must not block all
  commits), but a failing test is a broken commit and must block.
- **Test gate at `pre-push` instead of `pre-commit`.** Rejected: the
  pushed history would then contain commits that never passed the
  suite, which is exactly what the commit rules forbid; the gate
  belongs where the commit is created.
- **Skip environment variable.** Rejected: `git commit --no-verify` is
  already the one documented bypass; a second, invisible bypass invites
  habitually skipping the gate and leaves no trace in review.
