# Challenge 1 — Onboard the Agent and Establish the Baseline

!!! abstract "Challenge 01 of 08 · Act I — Foundation"
    **Agent mode:** Review · **Permissions:** Reader · **Estimated time:** 20–30 min

    **Stage:** **Foundation** → Operations → Engineering → Autonomous → Major Incident

**Situation.** You've just taken over the Aetherion AirOps Operations Center at the
start of your shift, and every service tile is green. Before the SRE Agent can help
with real incidents, you need to know what *healthy* looks like — and connect the
agent with least-privilege, read-only access you can trust.

**Mission.** Connect the SRE Agent with Reader access, capture a validated
operational baseline, and schedule a proactive daily health check.

**Why this matters**

<div class="grid cards why-cards" markdown>

- :material-chart-box-outline: **Baseline** — healthy-state reference every later incident is measured against
- :material-flash: **Faster RCA** — spot anomalies sooner against a known-good benchmark
- :material-lock-outline: **Least privilege** — safe, read-only onboarding; nothing changes without approval
- :material-shield-check-outline: **Proactive ops** — catch drift before a symptom becomes an outage

</div>

!!! example "Start this challenge"

    ```powershell
    ./scripts/start-challenge.ps1 1   # open / set up this challenge
    ```

### Tasks

1. **Verify platform health** — read the Operations Center once; this green board is your healthy reference for the day.
2. **Verify observability** — open Grafana and confirm AKS and Application Insights data is flowing.
3. **Connect the SRE Agent** — scope it to the resource group at **Reader** + **Review**, and confirm a write action prompts for approval.
4. **Generate the operational baseline** — have the agent produce a baseline for the `aetherion` namespace, then validate 2–3 of its numbers against the Ops Center and Grafana.
5. **Enable proactive monitoring** — schedule the baseline health check to re-run each morning so drift is caught before it becomes an incident.

!!! question "Stuck? Full walkthrough available"
    Give each task a genuine attempt before reaching for help — working it out
    yourself is where the learning sticks. Only if you get truly stuck, the
    [Azure portal walkthrough](../getting-started/portal-walkthrough.md) has the
    exact click-by-click for every step.

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
- The agent is connected in **Reader** + **Review**, can list every resource, and cannot write without approval.
- You hold a validated baseline whose replica counts and latency match the Ops Center and Grafana.
- A scheduled daily health check exists and runs read-only each morning.

!!! success "Verify your work"

    Run this when you're done — it grades the real end state and unlocks the next challenge:

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
baseline one click away — a baseline you can't find mid-incident is worthless — and
schedule the same read-only check so the agent watches for drift on its own.
</details>

### Reference

- [Create and set up the SRE Agent](https://learn.microsoft.com/en-us/azure/sre-agent/create-and-set-up)
- [Complete your setup](https://learn.microsoft.com/en-us/azure/sre-agent/complete-setup)
- [Permissions & run modes](https://learn.microsoft.com/en-us/azure/sre-agent/permissions)
- [Azure portal walkthrough](../getting-started/portal-walkthrough.md) · [Architecture](../reference/architecture.md) · [Commands](../reference/commands.md)

!!! success "Up next — the first real symptom"
    The first real symptom is about to appear — and you'll know it's abnormal because you measured normal.

    [Proceed to Challenge 2 · Detect & Investigate →](02-detect-and-investigate.md){ .md-button .md-button--primary }

---
