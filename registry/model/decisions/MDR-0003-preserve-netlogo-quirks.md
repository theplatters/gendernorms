---
id: MDR-0003
title: Preserve NetLogo quirks as reference behavior
status: accepted
date: 2026-09-19
---

## Context

The ODD section Known implementation quirks (items 1-12) in
`odd_model_description.typ` documents shipped NetLogo behaviors that look
like bugs but are load-bearing for replication: for example the
`multiplicative including weights` donor-branch parenthesisation, the
`set-theta` default to zero on no improvement, and the global (not targeted)
preference shock. The Julia port in `src/` must decide for each quirk whether
to replicate it or fix it, and that choice must be visible.

## Decision

The documented quirks (ODD Known implementation quirks, items 1-12) are
treated as reference behavior and preserved during the port unless a
dedicated MDR explicitly fixes one. The port already follows this rule where
it replicates a quirk. Quirk item 4 (the `multiplicative including weights`
donor-branch parenthesisation of `individual_utility` in
`src/resources/utility_functions.jl`, initially preserved) is now FIXED
under `MDR-0019`, which states the corrected behavior and the
comparability consequences as required below. Per `MDR-0001`, the reference
implementation `gender_model_shocks_preferences.nlogox` remains the
tiebreaker while the ODD remains normative.

## Consequences

Replication runs stay comparable to NetLogo by default. Any quirk fix needs
its own MDR stating which quirk item changes, what the corrected behavior is,
and what happens to comparability; the ODD quirk list and the affected rows
in `registry/model/processes.md` and
`registry/model/discrepancies.md` must be updated alongside. Until such MDRs
exist, reviewers should treat quirk-preserving code as correct, not as a bug.

## References

- `odd_model_description.typ`, Known implementation quirks
- `gender_model_shocks_preferences.nlogox`
- `src/resources/utility_functions.jl`
