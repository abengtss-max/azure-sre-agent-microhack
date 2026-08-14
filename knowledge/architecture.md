# Aetherion AirOps - Platform Architecture

> Knowledge base document for the Azure SRE Agent. Aetherion AirOps is a Tier 0,
> mission-critical **aviation operations** platform (flight operations, crew
> scheduling, reservations, baggage and telemetry). It is an operational/business
> platform, not safety-of-flight avionics.

## High-level topology

```
Internet
   │
   ├───────────────────────────────┐
   ▼                               ▼
Azure API Management               Envoy Gateway (Gateway API) + HTTPS
(Consumption tier)                 cert-manager + Let's Encrypt
  single API front door,           public front door for the Ops Center UI at
  subscription-key auth            https://sreagenthack-XXXXX.<region>.cloudapp.azure.com
  product: aetherion-ops           TLS terminate -> gateway service
  api:     aetherion (/aetherion)
   │                               │
   └───────────────┬───────────────┘
                   ▼
         AKS gateway service (public LoadBalancer)
   │
   ├── gateway            (serves Ops Center GUI + aggregates /api/status)
   ├── flight-ops         (flight board  -> PostgreSQL)
   ├── crew-scheduling    (crew rosters  -> PostgreSQL, small connection pool)
   ├── booking            (reservations & check-in -> PostgreSQL + Redis)
   ├── baggage            (baggage throughput, in-memory)
   └── telemetry-ingest   (aircraft/ground telemetry -> PostgreSQL)
   │
   ├── Azure Database for PostgreSQL Flexible Server (Burstable B2s, db: aetherion)
    └── Redis (in-cluster, namespace `aetherion`) - check-in/session state
```

Two front doors sit in front of the cluster:

- **API Management** (`aetherion-apim-*`, Consumption) is the API front door used by
  partners and the mobile app; it enforces subscription-key auth and rate limits.
- **Envoy Gateway** (Gateway API implementation, non-nginx) fronts the Ops Center
  GUI over HTTPS. **cert-manager** issues a trusted **Let's Encrypt** certificate for
  the auto-assigned DNS label `sreagenthack-XXXXX.<region>.cloudapp.azure.com` and
  terminates TLS before forwarding to the `gateway` service.

## Components

| Component | Azure resource | Purpose |
|-----------|----------------|---------|
| API front door | API Management `aetherion-apim-*` | Auth, routing, throttling |
| HTTPS front door | Envoy Gateway + cert-manager (in-cluster) | TLS for the Ops Center UI via Let's Encrypt |
| Compute | AKS `aetherion-aks` (namespace `aetherion`) | Runs all microservices |
| Registry | ACR `aetherionacr*` | Holds `aetherion-airops:latest` |
| Relational DB | PostgreSQL Flexible Server `aetherion-pg-*` | Flights, crew, bookings |
| Cache | Redis (in-cluster Deployment + Service, namespace `aetherion`) | Check-in/session state |
| Telemetry | Application Insights `aetherion-appi` | App traces/metrics/logs |
| Logs | Log Analytics `aetherion-law` | Central log store (AKS + AppInsights) |
| Dashboards | Managed Grafana `aetherion-grafana-*` | Azure Monitor data source |

## Microservice roles

All services run from **one image** (`aetherion-airops:latest`) with behaviour
selected by the `ROLE` environment variable.

| Service | ROLE | Key endpoints | Depends on |
|---------|------|---------------|-----------|
| gateway | gateway | `/`, `/api/status` | all services |
| flight-ops | flight-ops | `/api/flights` | PostgreSQL |
| crew-scheduling | crew-scheduling | `/api/crew` | PostgreSQL (pool max 5) |
| booking | booking | `/api/book`, `/api/bookings/count` | PostgreSQL, Redis |
| baggage | baggage | `/api/baggage/throughput` | none |
| telemetry-ingest | telemetry-ingest | `/api/telemetry` | PostgreSQL |

## Health model

- `/health/live` - liveness. Fails only if the process is in a crash fault state.
- `/health/ready` - readiness. For DB-backed services it verifies a PostgreSQL
  connection; a failing dependency takes the pod out of rotation.
- `/api/status` (gateway) - fans out to every service and returns aggregated
  health with per-service latency. This powers the Ops Center GUI.

## Autoscaling

- AKS cluster autoscaler: system node pool `aetherion` scales between the
  provisioned count and +2 nodes.
- HPAs on `crew-scheduling` and `booking`: 2-6 replicas, target 70% CPU.
