# Challenge 1 — Onboard the Agent and Establish the Baseline

!!! abstract "Challenge 01 of 08 · Act I — Foundation"
    **Run mode:** Review · **Access:** scoped to one resource group · **Estimated time:** 20–30 min

    **Stage:** **Foundation** → Operations → Engineering → Autonomous → Major Incident

**Situation.** You've just taken over the Aetherion AirOps Operations Center at the
start of your shift, and every service tile is green. Before the SRE Agent can help
with real incidents, you need to know what *healthy* looks like, and connect the
agent with least-privilege access in **Review** mode so it proposes changes and
waits for your approval.

**Mission.** Connect the SRE Agent with Reader access, capture a validated
operational baseline, and schedule a proactive daily health check.

**Why this matters**

<div class="grid cards why-cards" markdown>

- :material-chart-box-outline: **Baseline** — healthy-state reference every later incident is measured against
- :material-flash: **Faster RCA** — spot anomalies sooner against a known-good benchmark
- :material-lock-outline: **Least privilege** — scope the agent to one resource group; in **Review** mode it proposes changes and waits for approval
- :material-shield-check-outline: **Proactive ops** — catch drift before a symptom becomes an outage

</div>

!!! example "Start this challenge"

    ```powershell
    ./scripts/start-challenge.ps1 1   # sets the scene (Challenge 1 injects no fault)
    ```

    Challenge 1 injects nothing, so the board stays green — you create the SRE
    Agent yourself in Task 3 (the order relative to this script does not matter).
    If your Operations Center is **not** all-green (for example you ran a later
    challenge on this environment), reset to a clean baseline first:

    ```powershell
    ./scripts/reset-environment.ps1
    ```

### Tasks

1. **Verify platform health.** Read the Operations Center once — this green board is your healthy reference for the day.
2. **Verify observability.** Open Grafana and confirm AKS and Application Insights data is flowing.
3. **Create and connect the SRE Agent.** Create the agent in your app resource group, then in **Set up your agent** connect three context sources: **Code** = your fork of `aetherion-airops-platform` (used for change correlation in Challenge 3); **Logs** = the app's `aetherion-law` Log Analytics workspace; **Azure resources** = your app resource group, scoped as **Resource group** only. Keep the agent in **Review** run mode. See the detailed steps below.
4. **Generate the operational baseline.** With the platform healthy, have the agent produce a baseline for the `aetherion` namespace, then validate 2–3 of its numbers against the Ops Center and Grafana. If the board was recently degraded, reset and let telemetry settle first — otherwise the baseline captures the fault as "normal".
5. **Enable proactive monitoring.** Schedule the baseline health check (an agent scheduled task) to re-run each morning so drift is caught before it becomes an incident, then check that the alert thresholds it chose are sensible.

!!! question "Stuck? Give each task a genuine attempt first"
    Working it out yourself is where the learning sticks. If you need the exact
    clicks, expand the detailed steps below.

<details markdown="1"><summary><strong>Detailed steps — create &amp; connect the agent (Task 3)</strong></summary>

1. **Create the agent.** Azure portal → search **Azure SRE Agent** → **Create**.
   On **Basics** set your subscription, your **app resource group**
   (`rg-aetherion-microhack-<suffix>`), a name (`aetherion-sre-agent`), and region.
   For **Application Insights** choose **Create new** — the agent provisions its
   own App Insights + Log Analytics, separate from the app's. For **model
   provider**, **Azure OpenAI** is a good default (lower cost, EU data boundary).
   **Review + create** → **Create**.
2. **Set up your agent** — a separate step; **Create** alone grants no app access.
   Choose **Full setup** and add:
     - **Code** → **GitHub** → sign in → add **your fork** of `aetherion-airops-platform`.
     - **Logs** → **Log Analytics Workspace** → pick the app's **`aetherion-law`**
       (not the agent's own auto-created workspace).
     - **Azure resources** → **Resource group** → select **only your app resource
       group**. Do **not** pick *Subscription* or *Management group* — that would
       also expose the hidden load generator (`…-loadgen`) to the agent. Choose the
       **Reader** permission level.
3. **Keep Review mode.** Confirm the agent's run mode is **Review** so it proposes
   actions and waits for approval. The identity is granted Monitoring Contributor
   plus a reader bundle during setup, so the "won't change anything" guarantee
   comes from **Review mode**, not from the role being read-only.
4. **Confirm scope.** Ask: *"List the resources in my resource group and summarize
   what this application does."* You should get a grounded summary. Then ask it to
   **restart a deployment** — in Review mode it must ask for approval, not act.

</details>

<details markdown="1"><summary><strong>Detailed steps — schedule the daily health check (Task 5)</strong></summary>

Ask the agent in chat to schedule your baseline, for example *"Schedule this
baseline to run every morning at 08:00 and alert me on drift from normal."* It
creates an **agent scheduled task** (Automation), resolves the timezone/cron, and
sets alert conditions. **Verify and adjust** the thresholds it chose — on a clean
baseline the booking path is sub-second, so an alert set at "p95 > 3 s" would miss
real latency.

</details>

![Challenge 1 storyboard — Sam and Aria onboard the SRE Agent and read the baseline](../assets/storyboard/img-challenge-1.webp){ .story-panel loading=lazy }

### Suggested Azure SRE Agent prompt

!!! quote "Paste into the agent chat"
    Generate an operational baseline for the `aetherion` namespace, including:
    running services and ready replica counts; dependencies (which services use
    PostgreSQL and Redis, and what sits behind the API front door); normal
    check-in and booking latency; and the top operational signals to watch.
    Support every finding with telemetry evidence, and make no changes.

### Success criteria

- All service tiles are healthy and Grafana shows live metrics.
- The agent is connected to your resource group in **Review** mode, can list every resource, and asks for approval before any change.
- You hold a validated baseline — captured while the platform was healthy — whose replica counts and latency match the Ops Center and Grafana.
- A scheduled daily health check exists, with a sensible drift threshold.

!!! success "Verify your work"

    Run this when you're done. It grades the real end state:

    ```powershell
    ./scripts/check-challenge.ps1 1
    ```

### Hints

<details markdown="1"><summary>Hint — orientation & the agent</summary>

Load the Operations Center first and let it settle. Create the agent in the **same
resource group** as the platform, keep it at Reader/Review, and ask it an open
question about the resource group to confirm scope. A write request should produce
an approval prompt, not an action.
</details>

<details markdown="1"><summary>Hint — baseline & proactive</summary>

Ask one specific question about namespace health rather than browsing pod-by-pod,
and cross-check replica counts and latency against the tiles and Grafana. Keep the
baseline somewhere you can find it again mid-incident, and schedule the same
read-only check so the agent watches for drift on its own.
</details>

### Reference

- [Create and set up the SRE Agent](https://learn.microsoft.com/en-us/azure/sre-agent/create-and-set-up)
- [Complete your setup](https://learn.microsoft.com/en-us/azure/sre-agent/complete-setup)
- [Connect Log Analytics and Application Insights](https://learn.microsoft.com/en-us/azure/sre-agent/log-analytics-app-insights)
- [Manage roles and permissions](https://learn.microsoft.com/en-us/azure/sre-agent/manage-permissions)
- [Scheduled tasks](https://learn.microsoft.com/en-us/azure/sre-agent/scheduled-tasks)
- [Azure portal walkthrough](../getting-started/portal-walkthrough.md) · [Architecture](../reference/architecture.md) · [Commands](../reference/commands.md)

!!! success "Up next — the first real symptom"
    Challenge 2 injects the first incident, so your board will go from green to
    degraded — that's expected. You'll know it's abnormal because you measured normal.

    [Proceed to Challenge 2 · Detect & Investigate →](02-detect-and-investigate.md){ .md-button .md-button--primary }

---
