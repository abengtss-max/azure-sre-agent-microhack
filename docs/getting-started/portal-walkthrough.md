# Azure portal walkthrough

New to Azure or to the SRE Agent? This page is your **complete, click-by-click
reference** for every action the challenges ask you to perform. Each challenge
links back to the exact procedures below, so you never have to guess where a
button is.

!!! info "Portal UI may vary"
    Azure portal labels and blades occasionally move. When a screen differs from a
    step here, follow the matching step in the linked official doc — the flow
    is the same. Keep the [Azure portal](https://portal.azure.com) open in one tab
    and this page in another.

Everything in this hack uses the same defaults:

| Setting | Value |
|---------|-------|
| Resource group | `rg-aetherion-microhack-<suffix>` (your unique name) |
| Region | `swedencentral` |
| AKS cluster | `aetherion-aks` (namespace `aetherion`) |
| SRE Agent | `aetherion-sre-agent` |

!!! note "Your resource group name is unique"
    Provisioning always creates `rg-aetherion-microhack-<suffix>` (for example
    `rg-aetherion-microhack-a7c3`) and **prints the exact name** at the end.
    Wherever this guide says the resource group, use **your** suffixed name.

---

## A · Sign in to the Azure portal { #a-sign-in }

1. Open **[https://portal.azure.com](https://portal.azure.com)** and sign in with
   the account that owns the subscription you provisioned.
2. Confirm the correct directory/subscription: select your avatar (top-right) →
   **Switch directory** if you have more than one.
3. In the top search bar, type your resource group name
   (`rg-aetherion-microhack-<suffix>`) and open it. Pin it (the star icon) so it's
   one click away all day.

---

## B · Open the Operations Center { #b-ops-center }

The Operations Center is the live health board you use to detect and verify every
incident.

1. The provisioning script opened it automatically. If you lost the tab, get the
   URL again by running in your terminal:
   ```powershell
   $st = Get-Content ./scripts/.env.aetherion.json | ConvertFrom-Json
   if ($st.httpsUrl) { $st.httpsUrl } else { "http://$($st.gatewayIp)/" }
   ```
2. Open that URL (HTTPS if configured). Let the page settle — the flight board,
   service tiles and operational-risk gauge should all render.
3. **Healthy reference:** every service tile is green and the risk gauge is low.
   This is what you compare against when something breaks.

---

## C · Open Grafana and sign in { #c-grafana }

1. In the portal search bar, type **Grafana** and open **Azure Managed Grafana**
   → the `aetherion` workspace → **Endpoint** URL.
2. Sign in with your Azure account (single sign-on). If prompted for access, you
   need at least **Grafana Viewer** on the workspace.
3. Open the **Aetherion** dashboard. Confirm data is flowing in two panels:
   **AKS** (pods / CPU) and **Application Insights** (requests / latency).

---

## D · Create the SRE Agent { #d-create-agent }

Do this once, in Challenge 1.

1. In the portal search bar, type **Azure SRE Agent** and select it.
2. Select **Create**.
3. On **Basics**, set:
    - **Subscription:** your subscription.
    - **Resource group:** your provisioned group (`rg-aetherion-microhack-<suffix>`).
    - **Name:** `aetherion-sre-agent`.
    - **Region:** the closest supported region (e.g. `swedencentral`).
4. Leave the default **managed identity** option so the agent gets its own
   identity (you grant it roles later).
5. Select **Review + create** → **Create** and wait for deployment to finish.
6. Open the resource and confirm the chat/console loads.

Reference: [Create and set up](https://learn.microsoft.com/en-us/azure/sre-agent/create-and-set-up)
· [Complete your setup](https://learn.microsoft.com/en-us/azure/sre-agent/complete-setup)

---

## E · Give the agent read-only (Reader) access { #e-reader }

This lets the agent *see* the whole estate but change nothing.

1. Open your **resource group** (`rg-aetherion-microhack-<suffix>`) → **Access control (IAM)**.
2. Select **Add** → **Add role assignment**.
3. **Role:** search and pick **Reader**.
4. **Members:** choose **Managed identity** → select the `aetherion-sre-agent`
   identity.
5. Select **Review + assign**.
6. Back in the agent, ask it to *"list the resources in the resource group and
   summarise the application"* to confirm scope.

Reference: [Permissions & run modes](https://learn.microsoft.com/en-us/azure/sre-agent/permissions)

---

## F · Set the run mode (Review vs Autonomous) { #f-run-mode }

1. Open the **`aetherion-sre-agent`** resource → **Settings** (or the run-mode
   control in the agent console).
2. **Review** (default): the agent proposes a plan and waits for your approval
   before any write. Use this for Acts I–III.
3. **Autonomous:** the agent executes approved classes of action without pausing.
   Only switch a **specific, validated** fault to Autonomous (Challenge 6).
4. Changing run mode is approved by the **SRE Agent Administrator** role.

---

## G · Ask the agent / start a thread { #g-ask }

1. Open the agent resource → the **chat/console**.
2. Type a specific question — e.g. *"Give an operational baseline for the
   `aetherion` namespace: services, ready replicas, dependencies, and check-in
   latency."*
3. When the agent proposes a **write** in Review mode, it shows a plan with an
   **Approve / Reject** prompt. Read the plan — that plan is your approval
   artifact — then decide.

---

## H · Approve a write, or grant a narrow write role { #h-write }

When a fix needs a change, you have two governed paths:

=== "Approve on-behalf-of (OBO)"

    1. Ask the agent for a **remediation plan**.
    2. When it prompts, select **Approve** — the action runs using *your*
       credentials, once, for that step.
    3. Best when you want a human decision on each change.

=== "Grant a scoped role"

    1. Decide the **narrowest** role that covers the action (e.g. a write role on
       the AKS cluster only — not the whole subscription).
    2. Open the target resource → **Access control (IAM)** → **Add role
       assignment** → pick the role → **Managed identity** →
       `aetherion-sre-agent` → **Review + assign**.
    3. Best when you want the agent to act with its **own** identity, auditable in
       the Activity Log.

Reference: [Security overview](https://learn.microsoft.com/en-us/azure/sre-agent/security-overview)

---

## I · Load the knowledge base (ground the agent) { #i-knowledge }

1. In the agent, open **Knowledge** (team onboarding / memory).
2. Upload the Markdown files from this repo's **`knowledge/`** folder.
3. Re-ask your remediation question — the advice should now cite Aetherion's own
   runbook guardrails instead of generic steps.

Reference: [Team onboarding & memory](https://learn.microsoft.com/en-us/azure/sre-agent/team-onboard)

---

## J · Create a specialist subagent { #j-subagent }

1. In the agent, open **Subagents** (or extensibility) → **Create**.
2. Give it a **narrow remit in one sentence** — e.g. *"AKS reliability triage for
   the `aetherion` namespace: pod status, events, rollout history, dependency
   health."*
3. Save it, then **invoke it explicitly** in chat (e.g. `/agent aks`) and ask for
   a scoped namespace triage.

Reference: [Subagents & extensibility](https://learn.microsoft.com/en-us/azure/sre-agent/sub-agents)

---

## K · Create a reusable skill { #k-skill }

1. In the agent, open **Skills** → **Create**.
2. Encode a well-defined procedure (e.g. the crew connection-pool relief) as steps,
   keeping the guardrails (scale to relieve the pool, **never** delete the
   database).
3. Save it. Skills **auto-load** by context and are capped at **5 concurrent** —
   remove any you don't need.

Reference: [Skills](https://learn.microsoft.com/en-us/azure/sre-agent/skills)

---

## L · Review agent consumption (AAUs) { #l-consumption }

1. Open the **`aetherion-sre-agent`** resource → **Metrics** / **Cost** (or the
   consumption view in the console).
2. Break usage down by **thread type** and **operational purpose** to see where
   Agent Activity Units go.
3. Use only real figures from your environment or the official
   [pricing & billing doc](https://learn.microsoft.com/en-us/azure/sre-agent/pricing-billing)
   — never invent rates or savings.

---

## M · Inspect AKS (pods, events, rollout) { #m-aks }

You can let the agent do this, or check directly:

- **In the portal:** resource group → **`aetherion-aks`** → **Workloads** →
  select a deployment (e.g. `flight-ops`) → **Pods** and **Events**.
- **In your terminal** (read-only):
  ```powershell
  kubectl get pods -n aetherion
  kubectl describe deploy flight-ops -n aetherion
  kubectl rollout history deploy/flight-ops -n aetherion
  ```

---

## N · Correlate a change with the Activity Log & GitHub { #n-activity }

1. Open the affected resource (or the resource group) → **Activity log**.
2. Filter by the time the tile went red — look for a recent deployment or config
   change.
3. Cross-check the timing against the repo's recent commits/deployments on GitHub.
   Proximity in time is your strongest lead for a change-induced outage.

---

## O · Compare direct-vs-APIM (front-door problems) { #o-direct-apim }

When clients fail but the backend looks healthy, the problem is at the front door:

```powershell
# Load env once
$st = Get-Content ./scripts/.env.aetherion.json | ConvertFrom-Json

# Through the API front door (APIM) — may be throttled (HTTP 429)
Invoke-WebRequest "$($st.apimGatewayUrl)/aetherion/api/status" `
  -Headers @{ 'Ocp-Apim-Subscription-Key' = $st.apimSubscriptionKey } -UseBasicParsing

# Direct to the service (bypasses APIM) — if this is 200, the service is fine
Invoke-WebRequest "http://$($st.gatewayIp)/api/status" -UseBasicParsing
```

If **direct** returns 200 but **APIM** returns 429, the fault is an API Management
policy, not the service.

---

Return to any challenge — each one tells you exactly which of these procedures to
run, in order.
