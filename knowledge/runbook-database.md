# Runbook - Databases (PostgreSQL & Redis)

> Knowledge base runbook for the Azure SRE Agent. PostgreSQL Flexible Server
> `aetherion-pg-*` (database `aetherion`) and Azure Managed Redis
> `aetherion-redis-*` (Redis Enterprise). **These resources must never be deleted or recreated.**

## PostgreSQL - connection pool exhaustion

This is the most common database incident in Aetherion AirOps.

- **Where:** `crew-scheduling` uses a deliberately small pool (`PG_POOL_MAX=5`).
- **Cause in this env:** `FAULT_MODE=db-pool` holds connections open so the pool
  is exhausted and new requests to `/api/crew` time out.
- **Symptoms:**
  - `crew-scheduling` readiness starts failing; tile goes amber then red.
  - Application Insights shows database dependency timeouts / long durations.
  - Other services are unaffected (isolated to crew-scheduling).

### Remediate (in order)

1. Confirm the pool is the bottleneck (dependency timeouts, not CPU):
   `kubectl logs deploy/crew-scheduling -n aetherion --tail=200`.
2. **Scale before killing sessions.** Increase pool headroom by scaling replicas
   (each replica adds its own pool) or raise `PG_POOL_MAX`:
   `kubectl set env deploy/crew-scheduling -n aetherion PG_POOL_MAX=20`.
3. If this env's injected fault: clear it -> `FAULT_MODE=none`.
4. Only if truly stuck, and never as a first step, consider terminating idle
   backend sessions on the server side. Do **not** restart the database server.

## PostgreSQL - general guidance

- Do not modify or remove firewall rules as remediation (the `AllowAllAzureServices`
  rule is required for AKS pods to connect).
- For sustained CPU/IO pressure, scale the compute tier (Burstable -> General
  Purpose) rather than terminating workloads.
- Credentials are provided to pods via the `aetherion-secrets` Kubernetes secret
  (`PGHOST`, `PGUSER`, `PGPASSWORD`).

## Redis

- Azure Managed Redis (Redis Enterprise, Balanced B1); used by `booking` for
  check-in/session state; TLS on port 10000.
- If Redis is unreachable, `booking` degrades but should not crash.
- Do not delete or recreate the cache. If eviction/memory pressure is real,
  scale the cache SKU up; never flush production keys as a first response.

## Guardrails (data-specific)

- Never delete, recreate, or re-key PostgreSQL or Redis as a fix.
- Prefer application-side remediation (pool size, replicas) first.
- Any data-tier scaling is higher-impact - confirm before applying.
