# Runbook - Databases (PostgreSQL & Redis)

> Knowledge base runbook for the Azure SRE Agent. PostgreSQL Flexible Server
> `aetherion-pg-*` (database `aetherion`) and the in-cluster Redis cache in the
> `aetherion` namespace. **These resources must never be deleted or recreated.**

## PostgreSQL - slow query saturating the server

The most common database incident in Aetherion AirOps, and the one behind every
crew-scheduling degradation to date.

- **Where:** `crew-scheduling` serves `/api/crew` from `crew_roster`.
- **Why it happens:** `crew_roster` retains every past season's duty records, so
  the table is large while only current assignments are ever served. The duty
  lookup filters on `assigned` and orders by flight and crew member. Without an
  index supporting that access path, every request scans the whole table.
- **Symptoms:**
  - `/api/crew` latency climbs from tens of milliseconds into seconds, then
    requests start timing out; the tile goes amber, then red.
  - PostgreSQL CPU is high (70-100%) while the application pods are not.
  - Adding replicas does not help, and the autoscaler may refuse to add any
    because pod CPU is below target - the pods are waiting on the database.
  - Only the services that read `crew_roster` are affected.

### Diagnose

1. Compare the layers. Application pod CPU low **and** database CPU high means
   the constraint is the database, not the workload.
2. Confirm the access path is unindexed. From any database session - or from a
   service pod that already holds credentials - check the indexes on the table
   and the plan for the duty lookup:

   ```sql
   SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'crew_roster';

   EXPLAIN
   SELECT flight_no, crew_member, role, assigned
     FROM crew_roster
    WHERE assigned = true AND role <> 'Cabin Crew'
    ORDER BY flight_no, crew_member
    LIMIT 40;
   ```

   A `Seq Scan` over `crew_roster` confirms it.

### Remediate (in order)

1. **Fix the query path.** Add an index that supports the duty lookup. Build it
   with `CONCURRENTLY` so the table stays writable:

   ```sql
   CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_crew_roster_duty
     ON crew_roster (assigned, flight_no, crew_member);
   ```

   A maintenance job that applies exactly this ships with the platform, for
   operators working from a terminal:

   ```bash
   kubectl create -f k8s/maintenance/crew-roster-index.yaml
   ```

   Either route is acceptable. This is a schema change: apply it **under
   approval**, and expect latency to recover within a minute.
2. Do **not** scale pods or widen `PG_POOL_MAX` to escape this. Pool capacity
   already exceeds what the server can absorb, so more concurrency pushes more
   work at a saturated database and can make it worse.
3. Only if the query path is confirmed healthy and pressure persists, scale the
   compute tier (Burstable -> General Purpose). Never restart the database
   server.

## PostgreSQL - connection pool exhaustion

A different failure with a similar-looking symptom. Tell them apart by where the
CPU is: pool exhaustion leaves the **database idle**.

- **Where:** every DB-backed service uses a small per-pod pool (`PG_POOL_MAX=5`).
- **Symptoms:** dependency timeouts in Application Insights, connection
  acquisition errors in pod logs, and low database CPU with few active sessions.
- **Remediate:** raise per-pod headroom
  (`kubectl set env deploy/<service> -n aetherion PG_POOL_MAX=20`) or add
  replicas, since each replica brings its own pool. Only if truly stuck, and
  never as a first step, consider terminating idle backend sessions on the
  server side.

## PostgreSQL - general guidance

- Do not modify or remove firewall rules as remediation (the `AllowAllAzureServices`
  rule is required for AKS pods to connect).
- Credentials are provided to pods via the `aetherion-secrets` Kubernetes secret
  (`PGHOST`, `PGUSER`, `PGPASSWORD`).

## Redis

- In-cluster Redis (`redis` Deployment and Service in the `aetherion`
  namespace); used by `booking` for check-in/session state.
- If Redis is unreachable, `booking` degrades but should not crash.
- Do not delete the cache or flush production keys as a first response.

## Guardrails (data-specific)

- Never delete, recreate, or re-key PostgreSQL or Redis as a fix.
- Fix the layer that is actually saturated. Scaling the layer that is merely
  *waiting* adds cost and hides the fault.
- Any data-tier scaling or schema change is higher-impact - confirm before applying.
