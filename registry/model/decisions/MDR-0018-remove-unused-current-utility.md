---
id: MDR-0018
title: Remove the unused CurrentUtility carrier
status: accepted
date: 2026-10-02
supersedes: ""
superseded_by: ""
---

## Context

NetLogo `choose-bundle` stores `current-utility` as the reference payoff
of its discrete labour hill-climb. Experiment metrics report that stored
value. The ODD sections Entities, state variables, and scales, Labour
best response, and Parameters, experiments, and output describe this
scratch and diagnostic state.

The Julia port instead evaluates utility through `individual_utility`
and `BestResponseObjective` in its pure continuous solvers (`MDR-0017`).
The `CurrentUtility` component was initialized to zero in `get_agent`
and registered in the runtime and test worlds, but no Julia process
read or updated it. It was an unused placeholder, like the observer
carrier removed by `MDR-0008`, not an input to model dynamics.

## Decision

Remove the `CurrentUtility` component from `src/components.jl`, its
initial value from `get_agent`, and its registrations from runtime and
test worlds. Keep all utility evaluation, labour response, and transfer
bargaining code unchanged. Do not introduce a replacement stored
utility carrier or add utility computation to the tick loop.

Keep the NetLogo reference unchanged. Add a Julia-port note to the ODD
and mark the stored `current-utility` diagnostic as not ported in the
model registry. Historical decision contexts remain historical; this
record does not change the ECS pattern of `ADR-0001`.

## Consequences

Removing a component that no system consumes does not change the
model's numerical decisions. Worlds and initial agent tuples no longer
carry a permanently zero utility column. Code constructing worlds must
stop registering the removed type.

NetLogo's stored utility observations remain unported. Any future
utility observer must specify its evaluation state and timing rather
than revive the zero-valued placeholder. `TASK-0024` tracks the removal;
the decision invariant, model tests, package load, and strict registry
validator verify the implementation.
