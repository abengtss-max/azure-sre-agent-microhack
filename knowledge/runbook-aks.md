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

- Cause in this env: `FAULT_MODE=crash` on the deployment.
- Confirm: `kubectl get deploy/<svc> -n aetherion -o jsonpath='{.spec.template.spec.containers[0].env}'`.
- Remediate: clear the fault -> `kubectl set env deploy/<svc> -n aetherion FAULT_MODE=none`.
- If a real crash: `kubectl rollout undo deploy/<svc> -n aetherion`.

## Fault: memory pressure / OOM

- Cause in this env: `FAULT_MODE=memory` grows heap until the pod is OOM-killed.
- Symptom: restarts with reason `OOMKilled`, rising memory in Azure Monitor.
- Remediate: clear `FAULT_MODE`; if real, raise memory limits or scale out.

## Fault: high latency

- Cause in this env: `FAULT_MODE=latency` adds artificial delay.
- Symptom: amber tiles, elevated request duration in Application Insights.
- Remediate: clear `FAULT_MODE`; if real, check downstream + CPU, let HPA scale.

## Fault: error rate

- Cause in this env: `FAULT_MODE=error` returns HTTP 500 for a share of requests.
- Symptom: failed requests in Application Insights, red/amber tile.
- Remediate: clear `FAULT_MODE`; if real, `kubectl rollout undo`.

## Guardrails (AKS-specific)

- Do **not** cordon/drain nodes or restart node pools during business hours.
- Pod restarts and `rollout restart`/`undo` are safe at any time.
- Prefer scaling replicas and letting the HPA/cluster-autoscaler respond over
  manual node operations.
