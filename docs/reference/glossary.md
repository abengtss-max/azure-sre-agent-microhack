# Glossary

Terms below also appear as **hover tooltips** throughout the challenges — point at
any underlined acronym to see its meaning in place.

| Term | Meaning |
|------|---------|
| **Azure SRE Agent** | Azure's AI-powered reliability agent. Investigates, plans and remediates across the whole Azure estate (not just AKS) — with approval, or, once trusted, autonomously within guardrails. |
| **AKS** | Azure Kubernetes Service — the managed Kubernetes cluster that runs Aetherion's microservices. |
| **APIM / front door** | Azure API Management — the single public entry point that authenticates (subscription key) and routes all client traffic to the services. |
| **HPA / autoscaler** | Horizontal Pod Autoscaler — the Kubernetes control loop that adds or removes pods (replicas) as load changes. |
| **Replica** | One running copy (pod) of a service. More replicas share the load; the HPA adjusts the count. |
| **Connection pool** | A fixed set of reusable database connections. When it is exhausted, new requests queue or fail even though the database itself is healthy. |
| **Blast radius** | How much of the system an incident — or a fix — can affect. Good remediation keeps it as small as possible. |
| **RBAC** | Role-Based Access Control — Azure's permission model. Roles (e.g. Reader) decide what an identity is allowed to do. |
| **Managed identity** | An Azure identity for a workload (here, the agent) so it can authenticate to Azure without stored secrets. |
| **AAU** | Agent Activity Unit — the consumption unit for SRE Agent usage. Managing AAUs keeps the agent cost-effective (Challenge 6). |
| **OBO** | On-behalf-of. The agent performs an action using your approved credentials, making every action attributable and auditable. |
| **Review mode** | Run mode where the agent proposes a plan and waits for explicit human approval before any write. The default. |
| **Autonomous mode** | Run mode where the agent executes approved classes of action without pausing. Used only for well-understood, validated faults. |
| **Skill** | A packaged, reusable runbook the agent can auto-load by context (capped at 5 concurrent). |
| **Subagent** | A specialist agent invoked explicitly (e.g. `/agent aks`) for deep domain reasoning. |
| **Knowledge base** | The `.md` / `.txt` files (in `knowledge/`) that ground the agent in Aetherion's architecture and runbooks. |
| **SRE Agent Administrator** | The human role that approves changes to what the agent *is* — new skills, run-mode changes, permission grants. |
| **Operations Center** | The live GUI showing service health, operational-risk gauge, flight map, incidents and business impact. |
| **Operational-risk gauge** | The risk indicator on the Operations Center, driven by real service health — never fabricated telemetry. |
| **Grafana / App Insights / Log Analytics** | The observability stack: Grafana dashboards visualise metrics; Application Insights holds request/dependency/latency telemetry; Log Analytics stores container and platform logs. |
| **Activity Log** | Azure's record of control-plane changes — who changed what, and when — used to correlate incidents with deployments. |
| **Tier 0 / P1 / P2** | Business criticality and incident priority. Tier 0 services (check-in, crew scheduling) have immediate business impact; P1 is a critical outage, P2 a major degradation. |
| **SEV / severity** | Incident severity. <span class="aet-sev sev1">SEV1</span> critical, <span class="aet-sev sev2">SEV2</span> major, <span class="aet-sev sev3">SEV3</span> minor. |
| **Fault mode** | The kind of change behind an incident: a bad release, a resource limit cut too far, a canary revision serving the wrong role, a missing database index, or an API Management policy override. |
| **Reactive → Assisted → Autonomous** | The operational maturity arc the hack walks through, from human-driven response to trusted autonomy. |
