---
description: Run the registry validator and report violations.
agent: build
---

Run `julia --project=. scripts/registry_check.jl` and report the result.

1. Run the validator exactly as:
   `julia --project=. scripts/registry_check.jl`
2. Summarize errors separately from warnings, quoting the validator output.
3. For each violation, name the file at fault and the fix implied by
   `registry/code/conventions.md` or the registry-maintenance skill.
4. Do not edit unrelated code; only report unless asked to fix.
