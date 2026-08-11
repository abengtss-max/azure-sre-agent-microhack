# Aetherion AirOps - Platform Standards & Guardrails

> Knowledge base document for the Azure SRE Agent. These are the operating
> standards the SRE Agent must respect when proposing or taking actions.

## Service tiers & priorities

| Service | Business tier | If unhealthy, impact |
|---------|---------------|----------------------|
| flight-ops | Tier 0 | Flight board wrong -> gate/ops disruption |
| crew-scheduling | Tier 0 | Cannot assign crew -> potential delays |
| booking | Tier 1 | Reservations/check-in fail -> passenger impact |
| telemetry-ingest | Tier 1 | Loss of operational telemetry |
| baggage | Tier 2 | Baggage metrics degraded |
| gateway | Tier 0 | Whole Ops Center down |

## Change guardrails (must follow)

1. **Business hours = 06:00-22:00 local.** Do **not** drain or restart AKS node
   pools during business hours. Pod-level restarts are acceptable any time.
2. **Never delete data resources.** PostgreSQL and Redis must never be deleted,
   recreated, or have firewall rules removed as a remediation.
3. **Scale before you kill.** For database pressure, scale the compute tier
   (or increase the connection pool) before terminating active sessions.
4. **One change at a time.** Apply a single remediation, observe `/api/status`
   and Application Insights for 3-5 minutes, then decide the next step.
5. **Prefer reversible actions.** Scaling replicas, resetting a service profile,
   and HPA changes are reversible and preferred over node or infra changes.
6. **APIM policy changes are customer-facing.** Rate-limit / throttle policy
   edits affect every caller; treat as high-impact and confirm before applying.

## Standard remediation ladder

For an unhealthy microservice, escalate in this order:
1. Inspect pod logs and Application Insights failures/exceptions.
2. Check readiness vs liveness - is it a dependency problem or the process?
3. If a bad rollout: `kubectl rollout undo` to the last good revision.
4. If resource pressure: scale replicas / let HPA react; check node capacity.
5. If a clearly injected fault (this env): reset the service profile to `standard`.
6. If a dependency (PostgreSQL/Redis): follow the matching runbook, do not delete.

## Naming & locations

- Namespace: `aetherion`
- Image: `aetherion-airops:latest`
- Kubernetes secret: `aetherion-secrets`
- Config map: `aetherion-config`
- All resources live in a single resource group for easy teardown.

## What "healthy" looks like

- All six app deployments report `availableReplicas >= 1`.
- `/api/status` returns HTTP 200 with every service `green` and latency < 400 ms.
- APIM returns 200 (not 429) for `/aetherion/api/status` under normal load.
- No sustained exception spike in Application Insights.
