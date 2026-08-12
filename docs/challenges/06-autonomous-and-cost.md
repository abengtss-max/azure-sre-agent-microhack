# Challenge 6 — Autonomous Recovery and Cost-Aware Governance

!!! abstract "Challenge 06 of 08 · Act IV — Autonomous & Cost"
    **Run mode:** Autonomous (bounded) · **Access:** scoped write

    **Stage:** Foundation → Operations → Engineering → **Autonomous** → Major Incident

**Situation.** Every write so far has waited for your approval. Now a minor issue
appears: the **baggage** service returns intermittent errors to a slice of traffic.
Bags still move, no flight is grounded, and the fix is one you've already seen —
small blast radius, well-understood remedy. That's exactly when it's safe to let the
agent run **autonomously** while you supervise — then make it sustainable at scale
and arm it to trigger itself on the next major incident.

**Mission.** Let the agent recover the baggage service autonomously within
guardrails, design a cost-aware operating model for its Azure Agent Unit (AAU)
usage, and arm a **Sev1** response plan so the next major incident auto-triggers an
investigation — before you reach Challenge 7.

**Why this matters**

<div class="grid cards why-cards" markdown>

- :material-robot-happy-outline: **Bounded autonomy** — let the agent fix a small, safe issue end-to-end
- :material-cash-multiple: **Cost-aware** — see where Azure Agent Units actually go
- :material-tune-variant: **Right-sized** — cut waste without losing reliability
- :material-bell-alert-outline: **Armed for Sev1** — auto-trigger the agent on the next major incident

</div>

!!! example "Start this challenge"

    ```powershell
    ./scripts/start-challenge.ps1 6   # open the incident
    ```

### Tasks

1. **Confirm the symptom.** Verify the baggage errors in the Ops Center and telemetry so you know what "recovered" looks like.
2. **Grant bounded autonomy.** Give a narrowly scoped write role plus **Autonomous** mode, let the agent fix it end-to-end, then review the action log.
3. **See where AAUs go.** Inspect the agent's consumption by thread type and purpose.
4. **Design a cost-aware model.** Name concrete reductions without losing reliability or investigation quality.
5. **Arm the Sev1 response plan.** Bind the pre-provisioned `aetherion-major-incident` alert so the next major incident auto-triggers — do this now, before Challenge 7.

![Challenge 6 storyboard — Sam, Priya and Aria review autonomous recovery and cost governance](../assets/storyboard/img-challenge-6.webp){ .story-panel loading=lazy }

### Suggested Azure SRE Agent prompt

!!! quote "Paste into the agent chat"
    The `baggage` service is returning intermittent errors within a small blast
    radius. Using only the scoped write permission I've granted, detect the fault,
    decide the sanctioned reversible fix, apply it autonomously, and report exactly
    what you changed and why it was safe to automate.

### Success criteria

- The agent detects the baggage errors, executes a sanctioned fix autonomously, the service returns to healthy, and you can explain why it was safe to automate.
- You've reviewed real consumption data and produced a written, defensibly balanced operating model — cost-aware, not merely cheapest.
- A **Sev1 major-incident response plan** is active on the agent (bound to the pre-provisioned `aetherion-major-incident` alert), ready to auto-trigger the agent when the next major incident fires.
- `check-challenge.ps1 6` passes.

!!! warning "Ground truth only"
    Don't invent AAU rates, prices, or savings figures — use only values present in
    the [official docs](https://learn.microsoft.com/en-us/azure/sre-agent/pricing-billing)
    or your environment. Don't claim that stopping an agent ends all billing.

!!! success "Verify your work"

    Run this when you're done. It grades the real end state:

    ```powershell
    ./scripts/check-challenge.ps1 6
    ```

### Hints

<details markdown="1"><summary>Hint — make autonomy safe</summary>

Confirm the symptom first — you can't judge an autonomous recovery without knowing
what healthy looks like. Autonomy is safe because it's *scoped*: give the agent only
the write permission this one recovery needs, then switch to Autonomous and resist
helping.
</details>

<details markdown="1"><summary>Hint — cost model and the Sev1 plan</summary>

Optimize what you can measure: look at real consumption by thread type and purpose
— consolidation, deleting unused pilots, model fit, and plan/schedule noise are the
biggest levers. Aim for a *balanced* model, not the cheapest. Then wire the **Sev1**
response plan now, matching the pre-provisioned `aetherion-major-incident` alert's
severity exactly — or you'll be wiring it by hand while the board is red in
Challenge 7.
</details>

!!! question "Stuck? Step-by-step for each task"
    Give each task a genuine attempt first — and skim the hints above. When you want
    the exact clicks, open the matching task below.

    ??? note "Task 1 · Confirm the symptom"
        - Check the **baggage** tile and telemetry (Application Insights failed
          requests) so you know the current error rate and what "recovered" means.

    ??? note "Task 2 · Grant bounded autonomy"
        - Grant the agent's managed identity a **narrow** write role on just the
          baggage resource (portal → resource group → **Access control (IAM)**).
        - Set the run mode to **Autonomous** (on the response plan / task), then let
          the agent detect → decide → fix on its own. Review the action log after.

    ??? note "Task 3 · See where AAUs go"
        - In the agent, open **Settings → Agent consumption** and read the breakdown
          by thread type (Chats, Incidents, Scheduled tasks, Triggers) and by thread.

    ??? note "Task 4 · Design a cost-aware model"
        - Write a short operating model naming concrete levers: consolidate workloads
          under one agent, delete unused pilot agents, pick a model that fits the
          task, and trim noisy response plans / schedules — without losing
          reliability, ownership, RBAC, isolation, or investigation quality. Use only
          real figures.

    ??? note "Task 5 · Arm the Sev1 response plan"
        - **Builder → Incident response plans → New.** Filter by severity **Sev1** so
          it matches the pre-provisioned `aetherion-major-incident` alert exactly, and
          route it to your agent.
        - Do this **now** — Challenge 7 depends on it auto-triggering.

### Reference

- [Run modes](https://learn.microsoft.com/en-us/azure/sre-agent/run-modes)
- [Pricing and billing](https://learn.microsoft.com/en-us/azure/sre-agent/pricing-billing)
- [Incident response plans](https://learn.microsoft.com/en-us/azure/sre-agent/incident-response-plans)

!!! success "Up next — the final major incident"
    Your Sev1 response plan is armed — so when everything breaks at once, the agent triggers itself and you commandeer the incident.

    [Proceed to Challenge 7 · Final Major Incident →](07-major-incident.md){ .md-button .md-button--primary }

---
