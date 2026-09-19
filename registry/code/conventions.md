# Conventions

This file states the normative code-cleanliness rules for the
`GenderNorms` Julia package. The rules are the target standard.
Where current code deviates, fix the code, not the rule,
unless a recorded ADR or MDR permits the deviation.

## Naming

- Files use `snake_case.jl`, for example `household_bargaining.jl`.
- Types use `PascalCase`, for example `UtilityConfig` or `SocialNetwork`.
- Functions and variables use `snake_case`, for example
  `individual_utility` or `working_time`.
- Constants use `UPPER_SNAKE_CASE`, for example `SHOCK_NO`.
- Test files, when added, use `test_snake_case.jl` under `test/`.

## Structure

- One concern per file. Do not mix network construction, payoff
  functions, observers, and dynamics in a single file.
- Each file belongs to exactly one layer: `components`, `resources`,
  or `systems`, plus the module root `src/GenderNorms.jl` and the
  standalone entry point `src/main.jl`.
- Dependency direction follows `components` -> `resources` -> `systems`.
  Lower layers must not import from higher layers. No include cycles.
- New files must be registered: add the `include(...)` line to
  `src/GenderNorms.jl` in layer order and add a row to the file-map
  table in `registry/code/architecture.md`. The only exception is
  `src/main.jl`, which stays outside the module include list.

## Model-code citations

- Every ported behaviour must cite the NetLogo procedure and the ODD
  section it ports, either in a leading comment block or in the
  docstring. Name the NetLogo procedure in backticks and the ODD
  section by its heading or number, for example:
  `setup` in the NetLogo model, ODD section `Input and initialisation`.
- Any divergence from the ODD or NetLogo behaviour is forbidden
  without a recorded MDR in `registry/model/`. Reference the MDR
  identifier in the code comment, for example: see `MDR-0001`.
- Structural or pattern choices that affect more than one file
  require an ADR in `registry/code/decisions/`.

## Documentation

- All public and all top-level functions and types must have docstrings.
- Docstrings use triple-quoted strings directly above the definition,
  start with the signature line, and state purpose, arguments, and
  return value in plain sentences.
- Keep comments factual and tied to the cited NetLogo or ODD source.
  Remove stale comments when the code changes.

## Formatting and whitespace

- ASCII only in source and registry files unless a recorded decision
  allows otherwise.
- No tabs. Indent with spaces, four spaces per level in Julia files.
- No trailing whitespace on any line.
- LF line endings only.
- Every text file ends with exactly one trailing newline. An
  intentionally empty placeholder file is exempt from this rule but
  must be registered and explained in
  `registry/code/architecture.md`.
- Keep lines reasonably short and avoid unused imports or variables.

## Dead code

- No dead code, no commented-out blocks, and no stray debug output
  (`println`, `@show`, `@info`) without a recorded decision.
- Unwired or excluded files must be listed as `Excluded from module:`
  in `registry/code/architecture.md` with the reason and the plan
  (wire up, port, or delete under a later decision).
- Temporary scaffolding must be removed before a change is declared done.

## Commits

Commits are the changelog of intent; keep them clear, isolated, and
comprehensible.

- One logical change per commit. Do not mix unrelated concerns: a model
  port, a formatting sweep, and a dependency upgrade are separate
  commits. Commit a change together with the registry update it needs so
  that no commit leaves the registry stale.
- Subject line: imperative mood, lower-case except proper nouns, no
  trailing period, at most 72 characters, describing the change rather
  than the activity. Example:
  `port norm perception from calculate-utility`.
- Body when the subject is not self-explanatory: a blank line, then what
  changed and why, wrapped at 72 columns. Reference the governing
  `MDR-####` or `ADR-####`, the NetLogo procedure, and the ODD section.
- Every commit must leave a working tree. Before committing, run
  `julia --project=. scripts/registry_check.jl --strict` and
  `julia --project=. -e 'using GenderNorms'`, plus the test suite once
  `test/` is wired into `Pkg.test`.
- Stage explicit paths. Do not use `git add -A` or `git add .` when the
  tree contains unrelated work in progress, and never commit secrets,
  debug output, generated artifacts, or commented-out code.
- Do not amend, force-push, or rewrite shared history unless explicitly
  asked; correct a mistake with a new commit.
- Start from `.gitmessage` (enable locally with
  `git config commit.template .gitmessage`) and follow the `commit`
  command for the step-by-step workflow.

## Enforcement

- The command `julia --project=. scripts/registry_check.jl`, run by agents
  before finishing and by CI on PRs, checks the mechanically-checkable
  subset of this registry: frontmatter shape, required headings, file-map
  coverage of `src/`, exclusion annotations, skill frontmatter, ASCII,
  tabs, trailing whitespace, and final newlines. It also warns when a
  top-level definition is absent from the whole registry; because CI runs
  with `--strict`, that warning must also be resolved (by documenting the
  symbol, normally in `registry/code/architecture.md`).
- Checks that cannot be automated, such as naming sense, one concern per
  file, docstring quality, correct NetLogo and ODD citations, and the
  absence of silent divergence, are enforced by review.
- Every structural or architectural change requires an ADR in
  `registry/code/decisions/`. Every model behaviour, parameter, or
  porting choice requires an MDR in `registry/model/`. Never diverge
  silently: record first, then implement.
