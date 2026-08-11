# Challenge 6 — Autonomous Recovery and Cost-Aware Governance

!!! abstract "Challenge 06 of 08 · Act IV — Autonomous & Cost"
    **Agent mode:** Bounded Autonomous → read-only review · **Permissions:** scoped write · **Estimated time:** 30–40 min

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

1. **Confirm the symptom** — verify the baggage errors in the Ops Center and telemetry so you know what "recovered" looks like.
2. **Grant bounded autonomy** — a narrowly scoped write role plus **Autonomous** mode; let the agent detect, decide and fix without intervening, then review the action log.
3. **See where AAUs go** — inspect the agent's consumption by thread type and operational purpose.
4. **Design a cost-aware model** — name concrete reductions (consolidate workloads, delete unused pilots, right-size model choice, trim noisy plans/schedules) without losing reliability, ownership, RBAC, isolation or investigation quality.
5. **Arm the Sev1 response plan** — bind the pre-provisioned `aetherion-major-incident` alert to the agent so the next major incident auto-triggers an investigation. Do this **now**, before Challenge 7.

!!! question "Stuck? Give each task a genuine attempt first"
    Working it out yourself is where the learning sticks. If you need the exact
    clicks, the [Azure portal walkthrough](../getting-started/portal-walkthrough.md)
    has a step for every action.

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

<details markdown="1"><summary>Hint</summary>

Confirm the symptom first — you can't judge an autonomous recovery without knowing
what healthy looks like. Autonomy is safe because it's *scoped*: give the agent only
the write permission this one recovery needs, then switch to Autonomous and resist
helping. For governance, optimize what you can measure: look at real consumption by
thread type and purpose. Consolidation, deleting unused pilots, model fit,
response-plan noise, and schedule frequency are usually the biggest levers — aim for
a *balanced* model, not the cheapest possible setup. Last, wire the **Sev1** response
plan now: it's the difference between the agent auto-triggering on the next major
incident and you wiring it by hand while the board is red in Challenge 7. Match the
filter to the pre-provisioned `aetherion-major-incident` alert's severity exactly.
</details>

### Reference

- [Permissions & run modes](https://learn.microsoft.com/en-us/azure/sre-agent/permissions)
- [Security overview](https://learn.microsoft.com/en-us/azure/sre-agent/security-overview)
- [Pricing & billing](https://learn.microsoft.com/en-us/azure/sre-agent/pricing-billing)
- [Azure portal walkthrough](../getting-started/portal-walkthrough.md) · [Architecture](../reference/architecture.md) · [Commands](../reference/commands.md)

!!! success "Up next — the final major incident"
    Your Sev1 response plan is armed — so when everything breaks at once, the agent triggers itself and you commandeer the incident.

    [Proceed to Challenge 7 · Final Major Incident →](07-major-incident.md){ .md-button .md-button--primary }

---
