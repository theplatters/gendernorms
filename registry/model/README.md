# Model registry

The model registry records what the NetLogo model does and how (or whether)
the Julia port in `src/` implements it. It is the model half of the single
source of truth described in `registry/README.md`.

## The three sources

- `odd_model_description.typ` -- the normative model specification. Per
  `MDR-0001`, this ODD-style description decides what counts as intended
  model behavior.
- `gender_model_shocks_preferences.nlogox` -- the reference implementation.
  Where the ODD is ambiguous, the NetLogo code as shipped is the tiebreaker
  (including its quirks, see `MDR-0003`).
- `src/` -- the Julia port (`GenderNorms` package). It must follow the ODD
  and the reference implementation; any intentional divergence needs a new
  MDR recorded first.

Relationship: the ODD says what the model means, the `.nlogox` file shows
what the model does line by line, and `src/` re-implements that behavior in
Julia. The tables below map the first two onto the third so gaps are visible
instead of silent.

## How to keep the registry in sync when porting

1. Read `odd_model_description.typ` fully and the relevant NetLogo procedure
   in `gender_model_shocks_preferences.nlogox` before writing port code.
2. If you port a new entity, parameter, or process, add or update its row in
   `registry/model/entities.md`, `registry/model/parameters.md`, or
   `registry/model/processes.md` in the same change.
3. If you find a NetLogo-vs-Julia gap, an unwired file, or an open question,
   record it in `registry/model/discrepancies.md`. Do not silently fix or
   hide it.
4. If you intentionally diverge from the ODD or reference (solver change,
   quirk fix, new default), write a new MDR under
   `registry/model/decisions/` first, then implement, then reflect the row
   updates back into the tables.
5. Cite the NetLogo procedure and ODD section for every ported behavior, and
   mark anything not implementable from the evidence as `unknown` or
   `not ported` rather than guessing.

## Index

- `registry/model/entities.md` -- every ODD entity and state variable mapped
  to NetLogo and to Julia symbols, with port status.
- `registry/model/parameters.md` -- every ODD parameter default mapped to its
  Julia location and default, with discrepancy notes.
- `registry/model/processes.md` -- every NetLogo procedure mapped to its ODD
  section and Julia symbol(s), with port status.
- `registry/model/discrepancies.md` -- concrete discrepancies, unwired items,
  and open questions with evidence and suggested resolutions.
- `registry/model/decisions/MDR-0001-normative-model-specification.md` --
  the ODD is normative, the `.nlogox` is the reference, `src/` is the port.
- `registry/model/decisions/MDR-0002-continuous-best-response-solver.md` --
  the port solves `choose-bundle` by continuous maximization.
- `registry/model/decisions/MDR-0003-preserve-netlogo-quirks.md` -- NetLogo
  quirks are reference behavior until an MDR fixes one.
- `registry/model/decisions/MDR-0004-norm-perception-port.md` -- norm
  perception (`calculate-utility`) ported into `src/systems/norm_perception.jl`.
