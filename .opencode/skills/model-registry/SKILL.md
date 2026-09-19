---
name: model-registry
description: "Use when changing, porting, reviewing, or documenting the model: entities, state variables, parameters, submodels, NetLogo procedures, ODD semantics, shocks, utility, bargaining, networks. It guides consulting the model registry and recording MDRs."
---

# Model Registry

## When to use

Use this skill when changing, porting, reviewing, or documenting model
behavior: entities, state variables, parameters, submodels, NetLogo
procedures, ODD semantics, shocks, utility, bargaining, or networks.

## Where the registry lives

- `registry/model/README.md` - index and reading order.
- `registry/model/entities.md` - agents, state variables, scales.
- `registry/model/parameters.md` - parameters, defaults, ranges.
- `registry/model/processes.md` - submodels and scheduling.
- `registry/model/discrepancies.md` - known NetLogo-vs-Julia gaps.
- `registry/model/decisions/MDR-*.md` - Model Decision Records.
- Normative spec: `odd_model_description.typ`.
- Reference code: `gender_model_shocks_preferences.nlogox`.

## Consult procedure

1. Read the ODD section for the behavior first; note its section number.
2. Read `entities.md`, `parameters.md`, then `processes.md` in that order.
3. Check `discrepancies.md` for known gaps (e.g. unwired
   `src/resources/shock.jl`, empty `src/main.jl`, unported submodels).
4. Check `decisions/MDR-*.md` for prior rulings on the same behavior.
5. For ported logic, locate the NetLogo procedure and compare it with
   the ODD before writing Julia code.

## Record an MDR

1. Copy `registry/templates/decision.md`; name the file
   `MDR-<NNNN>-<kebab-slug>.md` with the next free four-digit number.
2. Fill flat YAML frontmatter between `---` lines with non-empty `id`,
   `title`, `status`, `date`; `status` is one of `proposed`, `accepted`,
   `rejected`, `superseded`, `deprecated`; `date` is `YYYY-MM-DD`;
   `id` must equal the filename prefix (e.g. `MDR-0007`).
3. Body must contain exactly `## Context`, `## Decision`, and
   `## Consequences` sections.
4. Lifecycle: start at `proposed`; move to `accepted` on implementation.
   To supersede, add `supersedes:` and `superseded_by:` keys, mark the old
   record `superseded`, and link both directions.

## Rules

- No silent divergence: ODD and registry change together, never one alone.
- Register every new or changed entity, parameter, or process in
  `entities.md`, `parameters.md`, or `processes.md`.
- Record gaps in `discrepancies.md`; do not silently fix or hide them.
- Cite the ODD section and the NetLogo procedure in code and records.

## Checklist

- [ ] ODD section cited; NetLogo procedure checked.
- [ ] Entities, parameters, processes consulted; discrepancies checked.
- [ ] MDR created or updated with valid frontmatter and headings.
- [ ] Registry index and tables updated; validator run.
