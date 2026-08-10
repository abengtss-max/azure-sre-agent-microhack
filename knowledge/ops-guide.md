# Aetherion AirOps - Operations Guide

> Knowledge base document for the Azure SRE Agent. How to observe the platform
> and where to look during an incident.

## Where signals live

| Signal | Location |
|--------|----------|
| Live service health + latency | Ops Center GUI (HTTPS `https://sreagenthack-XXXXX.<region>.cloudapp.azure.com/`, or direct `http://<gateway-ip>/`) and `/api/status` |
| App traces, requests, exceptions, dependencies | Application Insights `aetherion-appi` |
| Container + node logs/metrics | Log Analytics `aetherion-law` (Container Insights) |
| Dashboards | Managed Grafana `aetherion-grafana-*` (Azure Monitor data source) |
| API traffic, 429s, latency | APIM analytics |

## Cloud role names (Application Insights)

Each service reports as `aetherion-<role>`, e.g. `aetherion-crew-scheduling`,
`aetherion-booking`. Use these to filter the application map and failures.

## Useful Log Analytics (KQL) starting points

Container restarts in the last hour:
```kusto
KubePodInventory
| where Namespace == "aetherion"
| where TimeGenerated > ago(1h)
| summarize Restarts = max(PodRestartCount) by Name
| order by Restarts desc
```

Failed requests by service:
```kusto
requests
| where timestamp > ago(1h)
| where success == false
| summarize failures = count() by cloud_RoleName
| order by failures desc
```

Dependency (database) duration spikes:
```kusto
dependencies
| where timestamp > ago(1h)
| where type == "postgresql" or name contains "postgres"
| summarize p95 = percentile(duration, 95) by cloud_RoleName, bin(timestamp, 5m)
| order by p95 desc
```

## Incident workflow (recommended)

1. Look at `/api/status` / Ops Center to see which service(s) are red/amber.
2. Identify the failing tier and check the matching runbook (AKS / database / APIM).
3. Correlate with Application Insights failures and Log Analytics restarts.
4. Form a hypothesis, apply **one** reversible remediation, observe 3-5 minutes.
5. Confirm recovery via `/api/status` returning all-green, then document.

## Load generator

A k6 **Azure Container Instance** (in a separate, un-monitored resource group)
drives continuous traffic through the public APIM gateway. Modes:
- `normal` - steady baseline traffic.
- `surge` - ramped spike used to exercise autoscaling and expose bottlenecks.
Switch with `./scripts/deploy-loadgen.ps1 -Mode surge` (`-Mode normal` to reset).
