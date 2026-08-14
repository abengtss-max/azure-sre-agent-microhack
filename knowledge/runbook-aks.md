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
- Remediate: `kubectl rollout undo deploy/<svc> -n aetherion` to the last good
  revision. If the pods never started at all, check `kubectl get events` for an
  image pull failure before assuming the application is at fault.

## Fault: pods cannot start after a release (ImagePullBackOff / ErrImagePull)

- Symptom: new pods stay `Pending`/`ImagePullBackOff`; with a `Recreate` rollout
  strategy the old pods are gone first, so the service goes fully dark.
- Confirm: `kubectl rollout history deploy/<svc> -n aetherion` shows a new
  revision and a change cause; events name the tag that cannot be pulled.
- Remediate: `kubectl rollout undo deploy/<svc> -n aetherion`. Do not try to fix
  the tag forward during an incident.

## Fault: memory pressure / OOM

- Symptom: restarts with reason `OOMKilled`, rising memory in Azure Monitor.
- Remediate: raise the memory limit or scale out, then look for the leak.

## Fault: high latency

- Symptom: amber tiles, elevated request duration in Application Insights.
- Confirm where the time goes before acting. Container CPU pinned at its limit
  (high throttling) points at a resource limit that is too low - check whether a
  recent rollout reduced it. Low pod CPU with slow dependency calls points at a
  downstream service or the database; follow that runbook instead.
- Remediate: restore the limit the workload was sized for, or fix the downstream
  dependency. Scaling replicas does not help when the constraint is shared.

## Fault: error rate

- Symptom: failed requests (HTTP 500) in Application Insights, red/amber tile.
- Confirm whether *all* pods fail or only some. A partial error rate usually
  means one revision behind the Service is misconfigured - compare the pods
  backing the Service (`kubectl get pods -n aetherion -l app=<svc> --show-labels`).
- Remediate: remove or roll back the offending revision.

## Guardrails (AKS-specific)

- Do **not** cordon/drain nodes or restart node pools during business hours.
- Pod restarts and `rollout restart`/`undo` are safe at any time.
- Prefer scaling replicas and letting the HPA/cluster-autoscaler respond over
  manual node operations.
