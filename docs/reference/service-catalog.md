# Service catalog

Every microservice runs from a single Node.js image that takes on a role via
configuration. All services run in the AKS namespace `aetherion`.

## Microservices

| Service | Role | Depends on | Represents |
|---------|------|------------|------------|
| `gateway` | Ingress / Envoy gateway for the estate | AKS services | The public front door in front of APIM |
| `flight-ops` | Flight status and operational decisions | — | Live departures/arrivals view |
| `crew-scheduling` | Crew assignment | PostgreSQL | Roster and duty-time logic |
| `booking` | Booking and passenger check-in | PostgreSQL, Redis | Ticket sales and check-in |
| `baggage` | Baggage routing | — | Bag tracking and sortation |
| `telemetry-ingest` | Aircraft telemetry ingestion | PostgreSQL | Maintenance signal pipeline |

## Platform services

| Resource | Name / type | Purpose |
|----------|-------------|---------|
| API front door | Azure API Management | Partner/mobile entry, subscription-key auth, rate limiting |
| Compute | AKS `aetherion-aks` | Hosts all microservices + k6 load generator |
| Relational data | Azure Database for PostgreSQL Flexible Server | Crew, booking and telemetry data |
| Cache | Azure Managed Redis | Booking/check-in session and cache tier |
| App telemetry | Application Insights `aetherion-appi` | Requests, dependencies, exceptions |
| Logs | Log Analytics `aetherion-law` | Container and node logs, KQL |
| Dashboards | Azure Managed Grafana | Metrics, traces, autoscaling correlation |
| Change history | Azure Activity Log + GitHub | Deployment and resource change correlation |
| Load generator | k6 (in-cluster) | Continuous synthetic traffic |
| Reliability agent | Azure SRE Agent `aetherion-sre-agent` | Investigate, plan, remediate |

## Business impact

A disruption immediately affects flight departures/arrivals, passenger check-in,
crew assignment, baggage routing, regulatory reporting and revenue-generating
bookings — which is why the Operations Center leads with **business impact**, not
just service health.
