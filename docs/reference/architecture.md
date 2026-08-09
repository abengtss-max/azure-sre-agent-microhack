# Architecture

Aetherion AirOps is a microservices estate on Azure Kubernetes Service, fronted
by Azure API Management, backed by PostgreSQL and Redis, and observed through
Application Insights, Log Analytics and Grafana. The **Azure SRE Agent** reasons
across every tier — not just the cluster.

## Environment at a glance

[![Aetherion AirOps — Azure SRE Agent MicroHack environment architecture](../assets/architecture/aetherion-architecture.png){ .arch-diagram loading=lazy }](../assets/architecture/aetherion-architecture.png)

*Request/data flow runs left to right (solid blue); telemetry and control flow to
observability and the Azure SRE Agent (dashed purple); alerting is shown in red.
**Click the diagram to open it full size.** The agent runs governed remediation back into APIM and AKS, correlating change via
Azure Activity Log and GitHub history.*

## Executive view

The business-level picture: traffic enters through the API front door, flows to the
Aetherion AirOps services and their data stores, and the **Azure SRE Agent** watches
and recovers across all of it — grounded in monitoring, source control and your
runbooks.

```mermaid
flowchart TB
    OPS[Ops Centers · Airports · Partners] --> FRONT[API front door]
    FRONT --> APP["Aetherion AirOps services<br/>booking · crew · flight-ops · baggage · telemetry"]
    APP --> DATA[("Operational data<br/>PostgreSQL · Redis")]
    SRE[Azure SRE Agent] -. watches &amp; recovers .-> FRONT
    SRE -. watches &amp; recovers .-> APP
    SRE -. watches &amp; recovers .-> DATA
    SRE --- SIG[Monitor · Logs · GitHub · Knowledge]
```

## Request and data flow

```mermaid
flowchart LR
    U[Ops Centers / Airports / Partner APIs] --> APIM[Azure API Management]
    APIM --> FO[flight-ops svc]
    APIM --> CS[crew-scheduling svc]
    APIM --> BK[booking &amp; check-in svc]
    APIM --> BAG[baggage svc]
    APIM --> TEL[telemetry-ingest svc]
    subgraph AKS[Azure Kubernetes Service · namespace aetherion]
      FO
      CS
      BK
      BAG
      TEL
      K6[k6 load generator]
    end
    CS --> SQL[(Azure Database for PostgreSQL)]
    BK --> SQL
    BK --> REDIS[(Azure Managed Redis)]
    TEL --> SQL
    AKS -. metrics/logs .-> AI[Application Insights + Log Analytics]
    AI -. data source .-> GRAF[Azure Managed Grafana]
```

## Where faults hide

The symptom almost always appears at the **edge** (APIM 5xx or timeouts), but the
root cause can live in any tier. The hack deliberately rotates incidents across
the gateway, the cluster and the database so attendees learn to reason across the
whole estate.

| Tier | Example fault | First signal |
|------|---------------|--------------|
| Edge — APIM | Restrictive rate-limit policy | HTTP 429 under load |
| Compute — AKS | Crashing pod, memory pressure | Pod restarts, 5xx |
| App logic | Injected latency or errors | Slow responses, exceptions in App Insights |
| Data — PostgreSQL | Connection-pool exhaustion | Timeouts, saturation in Grafana |
| Data — Redis | Cache unavailability | Elevated latency on booking/check-in |

## Observability plane

- **Operations Center GUI** — live service health, operational-risk gauge, flight
  map, incidents and business impact. First place to confirm a symptom.
- **Application Insights** (`aetherion-appi`) — requests, dependencies,
  exceptions and the application map.
- **Log Analytics** (`aetherion-law`) — container and node logs for deep-dive KQL.
- **Azure Managed Grafana** — metrics, traces and autoscaling correlation.
- **Azure Activity Log + GitHub** — change history for incident correlation.

## Inside the Azure SRE Agent

The agent is more than a chat box: it operates in three complementary modes
(interactive, alert-driven, scheduled), routes work to tier specialists, grounds
itself in your knowledge and code, remembers past incidents, and can produce
artifacts from an isolated sandbox.

```mermaid
flowchart LR
    KNOW[Knowledge base] --> AGENT
    GH[GitHub repo] --> AGENT
    MON[Azure Monitor · App Insights · Log Analytics] --> AGENT
    subgraph AGENT[Azure SRE Agent]
      CHAT[Interactive chat]
      RESP[Alert-driven response plans]
      SCHED[Scheduled proactive tasks]
      SUBS[Sub-agents: AKS / APIM / DB]
      SKILLS[Skills: versioned runbooks]
      MEM[Memory &amp; session insights]
      SANDBOX[Python sandbox: reports/PDF]
    end
    AGENT -->|"read: investigate"| ESTATE[APIM · AKS · PostgreSQL · Redis]
    AGENT -->|"write: remediate — RBAC + approval"| ESTATE
```

See the [service catalog](service-catalog.md) for the per-service breakdown.
