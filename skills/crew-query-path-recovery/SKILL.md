---
name: crew-query-path-recovery
description: Recover crew scheduling when a saturated shared database, not the workload, is the bottleneck.
---

## When this applies

`crew-scheduling` is slow or timing out, but its pods are healthy, not
restarting, and using little CPU. Peer services sharing the same PostgreSQL
server are also degraded; services that do not share it are unaffected.

## Diagnose before acting

1. Confirm the pods are waiting, not working: check pod CPU against requests
   and confirm no restarts.
2. Confirm the autoscaler is not the constraint. If CPU is below target the
   autoscaler will refuse to add replicas, and it is right to refuse.
3. Confirm the database is the saturated layer: check PostgreSQL CPU.
4. Identify the query path behind the crew duty lookup and whether it is
   supported by an index.

## Remedy

Repair the query path — restore the missing index supporting the crew duty
lookup. Build it without taking a disruptive lock on a live table.

Verify by re-measuring crew latency under the same load, not by checking
that a pod restarted.

## Guardrails

- Never delete or restart the database. It is a shared dependency and the
  blast radius is every service on it.
- Do not scale the layer that is merely waiting. Adding replicas to
  `crew-scheduling` adds connections to an already-saturated database and
  makes it worse.
- Any write is proposed for approval first, never applied unilaterally.
- If the evidence does not show database saturation, this skill does not
  apply — stop and say so.
