# Aetherion AirOps - Escalation & Ownership

> Knowledge base document for the Azure SRE Agent. Who owns what, and when to
> stop and escalate instead of acting autonomously.

## Team ownership

| Area | Owning team | Notes |
|------|-------------|-------|
| flight-ops, crew-scheduling, gateway | Flight Systems (Tier 0) | Highest priority |
| booking (reservations & check-in) | Passenger Services | Customer-facing |
| baggage, telemetry-ingest | Ground Operations | Tier 1-2 |
| PostgreSQL, Redis | Data Platform | Data changes require this team |
| APIM | API Platform | Policy changes are customer-facing |
| AKS / infra / networking | Cloud Platform / SRE | Node & infra operations |

## When the SRE Agent should act vs escalate

**Safe to act (reversible, low blast radius):**
- Restarting a pod, `rollout restart`/`undo` on a single deployment.
- Scaling replicas or adjusting an HPA within configured bounds.
- Resetting a service's profile to `standard` (this teaching environment).

**Stop and escalate (get a human / Administrator approval):**
- Anything touching PostgreSQL or Redis beyond app-side settings.
- APIM policy or product/API changes (customer-facing).
- AKS node pool drain/restart/scale, or actions during business hours.
- Any action that is not clearly reversible or affects multiple services.

## Approvals

- Only a user with the **Azure SRE Agent Administrator** role can approve actions
  the agent proposes in Review mode or elevated (on-behalf-of) operations.
- In Review mode the agent must present a plan and wait for approval before
  making changes. In Autonomous mode it may act within its permissions, but the
  guardrails in `platform-standards.md` still apply.

## Escalation contacts (example)

- Primary on-call SRE: `#aetherion-sre` (chat) / on-call rotation.
- Data Platform on-call: `#aetherion-data`.
- Incident commander for Sev1/Sev2: paging bridge.

> These contacts are illustrative for the MicroHack. In a real deployment,
> replace with your actual on-call and paging details.
