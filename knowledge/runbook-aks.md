# Runbook - Azure Kubernetes Service (AKS)

> Knowledge base runbook for the Azure SRE Agent. Cluster: `aetherion-aks`,
> namespace: `aetherion`.

## Common symptoms & first checks

| Symptom | First check |
|---------|-------------|
| A service tile is red in Ops Center | `kubectl get pods -n aetherion` and pod logs |
| Pod `CrashLoopBackOff` | `kubectl describe pod` + `kubectl logs --previous` |
| Pod `Pending` | Node capacity / autoscaler: `kubectl get nodes`, events |
| High latency (amber tiles) | Application Insights latency + CPU/HPA state |
| Readiness failing but process up | Downstream dependency (PostgreSQL/Redis) |

## Triage commands

```
kubectl get pods -n aetherion -o wide
kubectl describe deploy/<service> -n aetherion
kubectl logs deploy/<service> -n aetherion --tail=200
kubectl get hpa -n aetherion
kubectl get events -n aetherion --sort-by=.lastTimestamp
```

## Fault: crash (liveness failing, CrashLoopBackOff)

- Symptom: pods fail liveness/readiness, CrashLoopBackOff, the service tile goes dark.
- Confirm: `kubectl describe deploy/<svc> -n aetherion`; check the recent rollout / change history.
- Remediate (this teaching env): reset the service profile ->
  `kubectl set env deploy/<svc> -n aetherion SVC_PROFILE=standard` (or run `reset-environment.ps1`).
- If a real crash: `kubectl rollout undo deploy/<svc> -n aetherion`.

## Fault: memory pressure / OOM

- Symptom: restarts with reason `OOMKilled`, rising memory in Azure Monitor.
- Remediate (this teaching env): reset the service profile to `standard`; if real, raise memory limits or scale out.

## Fault: high latency

- Symptom: amber tiles, elevated request duration in Application Insights.
- Remediate (this teaching env): reset the service profile to `standard`; if real, check downstream + CPU, let HPA scale.

## Fault: error rate

- Symptom: failed requests (HTTP 500) in Application Insights, red/amber tile.
- Remediate (this teaching env): reset the service profile to `standard`; if real, `kubectl rollout undo`.

## Guardrails (AKS-specific)

- Do **not** cordon/drain nodes or restart node pools during business hours.
- Pod restarts and `rollout restart`/`undo` are safe at any time.
- Prefer scaling replicas and letting the HPA/cluster-autoscaler respond over
  manual node operations.
