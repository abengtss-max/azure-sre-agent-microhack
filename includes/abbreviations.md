*[SRE]: Site Reliability Engineering — running services with software-engineering discipline.
*[AKS]: Azure Kubernetes Service — the managed Kubernetes cluster that runs the microservices.
*[APIM]: Azure API Management — the API "front door" that authenticates and rate-limits traffic to the services.
*[HPA]: Horizontal Pod Autoscaler — Kubernetes control loop that adds or removes pods as load changes.
*[RBAC]: Role-Based Access Control — Azure's permission model; roles decide what an identity may do.
*[OBO]: On-behalf-of — the agent performs an action using your credentials after you approve it.
*[AAU]: Agent Activity Unit — the consumption/billing unit for Azure SRE Agent usage.
*[Tier 0]: The most business-critical services whose failure has immediate business impact (e.g. check-in, crew scheduling).
*[P1]: Priority 1 — a critical, business-stopping incident.
*[P2]: Priority 2 — a major incident that degrades service but is not a full outage.
*[SEV1]: Severity 1 — critical incident.
*[SEV2]: Severity 2 — major incident.
*[SEV3]: Severity 3 — minor incident.
*[blast radius]: How much of the system an incident (or a fix) can affect — kept as small as possible.
*[connection pool]: A fixed set of reusable database connections; when it is exhausted, requests queue or fail.
*[replica]: One running copy (pod) of a service; more replicas share the load.
*[replicas]: Running copies (pods) of a service; more replicas share the load.
*[front door]: The single public entry point (API Management) through which all client traffic passes.
*[managed identity]: An Azure identity for a workload (here, the agent) so it can authenticate without stored secrets.
*[Reader]: The built-in Azure role that grants read-only access — see everything, change nothing.
*[Review mode]: SRE Agent run mode where it proposes a plan and waits for your approval before any write.
*[Autonomous mode]: SRE Agent run mode where it executes approved classes of action without pausing for each step.
*[knowledge base]: Markdown/text files that ground the agent in Aetherion's own architecture and runbooks.
*[Grafana]: Dashboarding tool used here to visualise AKS and Application Insights metrics.
*[Log Analytics]: Azure service that stores and queries container and platform logs.
*[Application Insights]: Azure application-performance monitoring — requests, dependencies, exceptions, latency.
*[Activity Log]: Azure's record of control-plane changes (who changed what, and when).
